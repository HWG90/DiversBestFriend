/* game: the read-only readers (see game.h), ported from R46's native.lua (hud, valid, snapshot) and input.lua (lookup,
 * context, code, the payload kinds). Portable C11: standard headers, memory.h, admission.h and the generated address
 * header only. Every number below is a DBF_RVA_*, DBF_OFF_* or DBF_VAL_* from that header, each with its R46 line. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "game.h"
#include "memory.h"

_Static_assert(DBF_VAL_CODE_MAX <= DBF_CODE_CAPACITY, "DbfRow.code holds R46's longest code");
_Static_assert(DBF_OFF_CODE_STRIDE == sizeof(uint32_t), "a code array is read whole as uint32_t directions");

static uintptr_t g_base; /* game.dll; 0 before game_init */
static uint32_t g_image_size;
static bool g_table_ok; /* g_table_rva passed R46's rule and its entries were readable */
static uint32_t g_table_rva;
static bool g_have_identity; /* the local identity of the last read that found one */
static uint64_t g_identity_peer;
static uintptr_t g_identity_payload;

typedef struct Local {
    uint64_t peer;
    uintptr_t payload;
} Local;

/* --- reasons --------------------------------------------------------------------------------------------------- */

/* reason = a b c, cut to fit, unless a reason is already there: the first one stays. Every reason given is non-empty. */
static void note(GameView* v, const char* a, const char* b, const char* c)
{
    const char* parts[3] = { a, b, c };
    size_t n = 0;
    if (v->reason[0] != '\0') return;
    for (int i = 0; i < 3; i++)
        for (const char* p = parts[i]; p && *p && n < sizeof v->reason - 1; p++) v->reason[n++] = *p;
    v->reason[n] = '\0';
}

static bool fail(GameView* v, const char* text)
{
    note(v, text, "", "");
    return false;
}

/* "card <index><what>" */
static void card_fails(GameView* v, unsigned index, const char* what)
{
    char digits[12], number[12];
    size_t d = 0, n = 0;
    do {
        digits[d++] = (char)('0' + index % 10u);
        index /= 10u;
    } while (index != 0 && d < sizeof digits);
    while (d > 0) number[n++] = digits[--d];
    number[n] = '\0';
    note(v, "card ", number, what);
}

/* True when admission admits `f`; otherwise reason gets "<feature name>: <admission's reason>", copied now (admission's
 * reason strings are only valid until its next call). */
static bool admitted(GameView* v, Feature f)
{
    const char* why = NULL;
    if (adm_feature(f, &why) == ADMIT_OK) return true;
    note(v, adm_feature_name(f), ": ", why && *why ? why : "not admitted");
    return false;
}

/* --- the local player (R46 input.lua:74-139) ------------------------------------------------------------------- */

/* input.lua:74-94: an open-addressing table at owner+offset holding the slots' pointer (4-aligned), the capacity (+8, a
 * power of two up to 65536), the empty key (+12) and the seed (+16). Slots are {key, index} pairs of uint32_t; a key's
 * probe starts at key * seed (mod 2^32) and ends at the empty key. The index must be below `limit`. */
static bool lookup(GameView* v, uintptr_t owner, uint32_t offset, uint32_t key, uint32_t limit, uint32_t* index)
{
    uintptr_t table = owner + offset, slots;
    uint32_t capacity, empty, seed, hash;
    if (!mem_u32(table + DBF_OFF_LOOKUP_CAPACITY_OFFSET, &capacity)) return fail(v, "lookup unreadable");
    if (capacity == 0 || capacity > DBF_VAL_LOOKUP_MAX_CAPACITY) return fail(v, "invalid lookup capacity");
    if ((capacity & (capacity - 1u)) != 0) return fail(v, "lookup capacity is not a power of two");
    if (!mem_u32(table + DBF_OFF_LOOKUP_EMPTY_OFFSET, &empty) || !mem_u32(table + DBF_OFF_LOOKUP_SEED_OFFSET, &seed)
        || !mem_ptr_aligned(table, &slots, DBF_VAL_LOOKUP_ALIGN))
        return fail(v, "lookup unreadable");
    hash = key * seed;
    for (uint32_t probe = 0; probe < capacity; probe++) {
        uintptr_t slot = slots + (uintptr_t)(((uint64_t)hash + probe) % capacity) * DBF_OFF_LOOKUP_SLOT_SIZE;
        uint32_t found;
        if (!mem_u32(slot, &found)) return fail(v, "lookup unreadable");
        if (found == key) {
            if (!mem_u32(slot + DBF_OFF_LOOKUP_SLOT_INDEX_OFFSET, index)) return fail(v, "lookup unreadable");
            if (*index >= limit) return fail(v, "lookup index out of bounds");
            return true;
        }
        if (found == empty) break;
    }
    return fail(v, "local ownership mapping unavailable");
}

static bool session_peer(uint64_t* peer)
{
    uintptr_t session;
    return mem_ptr(g_base + DBF_RVA_SESSION, &session) && mem_u64(session + DBF_OFF_SESSION_PEER_OFFSET, peer);
}

static bool identity_changed(GameView* v)
{
    g_have_identity = false; /* the next read that finds a local payload takes it as the identity */
    return fail(v, "local payload changed");
}

/* input.lua:95-139 (context): player manager -> network index -> registry key -> avatar (unit and input owner agree)
 * -> player context -> the player's peer, which must be the session's -> the one mission entry with that peer, whose
 * payload is the local one. */
static bool read_local(GameView* v, Local* out)
{
    uintptr_t pm, registry, manager, unit, avatar, mission, payload = 0;
    uint32_t players, network, registry_index, key, avatars, avatar_index, unit_key, owner, context, player_index, peers;
    uint64_t peer, session;

    /* The session's peer is the identity: when it is not the last one, this is another payload, whatever else this read
     * would find. */
    if (g_have_identity && session_peer(&session) && session != g_identity_peer) return identity_changed(v);

    if (!mem_ptr(g_base + DBF_RVA_PLAYERS, &pm) || !mem_u32(pm + DBF_OFF_PLAYERS_COUNT_OFFSET, &players))
        return fail(v, "player manager unreadable");
    if (players == 0) return fail(v, "no local player");
    if (!mem_u32(pm + DBF_OFF_PLAYERS_NETWORK_OFFSET, &network)) return fail(v, "player manager unreadable");
    if (network >= DBF_VAL_NETWORK_LIMIT) return fail(v, "local network index unavailable");

    if (!mem_ptr(g_base + DBF_RVA_REGISTRY, &registry)) return fail(v, "registry unreadable");
    if (!lookup(v, registry, DBF_OFF_REGISTRY_LOOKUP_OFFSET, network, DBF_VAL_REGISTRY_INDEX_LIMIT, &registry_index))
        return false;
    if (!mem_u32(registry + DBF_OFF_REGISTRY_KEYS_OFFSET + (uintptr_t)DBF_OFF_REGISTRY_KEY_STRIDE * registry_index, &key))
        return fail(v, "registry unreadable");

    if (!mem_ptr(g_base + DBF_RVA_AVATARS, &manager) || !mem_u32(manager + DBF_OFF_AVATARS_COUNT_OFFSET, &avatars))
        return fail(v, "avatar manager unreadable");
    if (avatars == 0 || avatars > DBF_VAL_AVATAR_MAX) return fail(v, "invalid avatar count");
    if (!lookup(v, manager, DBF_OFF_AVATARS_LOOKUP_OFFSET, key, avatars, &avatar_index)) return false;
    if (!mem_ptr(manager + DBF_OFF_AVATARS_UNITS_OFFSET + (uintptr_t)DBF_OFF_AVATARS_UNIT_STRIDE * avatar_index, &unit)
        || !mem_u32(unit + DBF_OFF_UNIT_KEY_OFFSET, &unit_key))
        return fail(v, "avatar unreadable");
    if (unit_key != key) return fail(v, "avatar identity mismatch");
    avatar = manager + DBF_OFF_AVATAR_FIRST + (uintptr_t)avatar_index * DBF_OFF_AVATAR_STRIDE;
    if (!mem_u32(avatar + DBF_OFF_AVATAR_COMPONENT_OFFSET + DBF_OFF_COMPONENT_OWNER_OFFSET, &owner))
        return fail(v, "avatar unreadable");
    if (owner != key) return fail(v, "input owner mismatch");
    if (!mem_u32(avatar + DBF_OFF_AVATAR_CONTEXT_OFFSET, &context)) return fail(v, "avatar unreadable");

    if (!lookup(v, pm, DBF_OFF_PLAYERS_LOOKUP_OFFSET, context, DBF_VAL_PLAYER_INDEX_LIMIT, &player_index)) return false;
    if (!mem_u64(pm + DBF_OFF_PLAYERS_PEER_OFFSET + (uintptr_t)player_index * DBF_OFF_PLAYERS_PEER_STRIDE, &peer))
        return fail(v, "player manager unreadable");
    if (!session_peer(&session)) return fail(v, "session unreadable");
    if (peer != session || peer == 0) return fail(v, "local peer mismatch");

    if (!mem_ptr(g_base + DBF_RVA_MISSION, &mission) || !mem_u32(mission + DBF_OFF_MISSION_PEER_COUNT_OFFSET, &peers))
        return fail(v, "mission unreadable");
    if (peers > DBF_VAL_MISSION_PEER_MAX) return fail(v, "invalid mission peer count");
    for (uint32_t i = 0; i < peers; i++) {
        uintptr_t entry = mission + (uintptr_t)i * DBF_OFF_MISSION_ENTRY_STRIDE;
        uint64_t entry_peer;
        if (!mem_u64(entry, &entry_peer)) return fail(v, "mission unreadable");
        if (entry_peer != peer) continue;
        if (payload != 0) return fail(v, "ambiguous local payload");
        payload = entry + DBF_OFF_MISSION_PAYLOAD_OFFSET;
    }
    if (payload == 0) return fail(v, "local mission payload unavailable");

    if (g_have_identity && payload != g_identity_payload) return identity_changed(v);
    g_have_identity = true;
    g_identity_peer = peer;
    g_identity_payload = payload;
    out->peer = peer;
    out->payload = payload;
    return true;
}

/* --- payload, definitions and codes (R46 input.lua:141-179, 230-234; native.lua:47-55) ------------------------- */

static bool read_entry_count(GameView* v, uintptr_t payload, uint32_t* count)
{
    if (!mem_u32(payload + DBF_OFF_PAYLOAD_COUNT_OFFSET, count)) return fail(v, "stratagem entries unreadable");
    if (*count > DBF_VAL_PAYLOAD_ENTRY_MAX) return fail(v, "invalid stratagem entry count");
    return true;
}

/* native.lua:51-55: the definition table is where the live displacement of [image + kind*8 + disp] says. Accepted: the
 * vanilla 0x37cb600, or an 8-aligned RVA in HellForge's reservation [image_size, image_size + 0x400000); and its entries
 * for kinds 1 to 149 must be readable. An accepted RVA is not checked again until the displacement changes. */
static bool read_table(GameView* v)
{
    uint8_t entries[DBF_VAL_VANILLA_KINDS * DBF_OFF_DEFINITION_STRIDE];
    uint32_t rva;
    if (!mem_u32(g_base + DBF_RVA_DEFINITION_DISPLACEMENT, &rva)) {
        g_table_ok = false;
        return fail(v, "definition table unreadable");
    }
    if (g_table_ok && rva == g_table_rva) return true;
    g_table_ok = false;
    if (rva != DBF_RVA_DEFINITION_TABLE_VANILLA
        && (rva % DBF_VAL_DEFINITION_TABLE_ALIGN != 0 || rva < g_image_size
            || (uint64_t)rva >= (uint64_t)g_image_size + DBF_VAL_DEFINITION_RELOCATION_SPAN))
        return fail(v, "definition table unrecognised");
    if (!mem_read(g_base + rva + DBF_OFF_DEFINITION_STRIDE, entries, sizeof entries))
        return fail(v, "definition table unreadable");
    g_table_ok = true;
    g_table_rva = rva;
    return true;
}

/* input.lua:160-177 without the scramble remap: the kind's definition is a settings descriptor (4-aligned, inside the
 * settings block, naming the kind), its code array (4-aligned, 1 to 12 directions, inside the settings block) holds
 * directions 1 to 4. Any failure leaves the row without a code. */
static void read_code(GameView* v, DbfRow* row)
{
    uintptr_t settings, info, data;
    uint32_t kind = row->kind, named, n, d[DBF_VAL_CODE_MAX];
    if (kind == 0 || kind >= DBF_VAL_KIND_LIMIT) return; /* no vanilla definition (input.lua:5) */
    if (!mem_ptr(g_base + DBF_RVA_SETTINGS, &settings)) {
        fail(v, "settings unreadable");
        return;
    }
    if (!mem_ptr_aligned(g_base + g_table_rva + (uintptr_t)kind * DBF_OFF_DEFINITION_STRIDE, &info,
                         DBF_VAL_DEFINITION_ALIGN)
        || info < settings || info + DBF_OFF_DEFINITION_SIZE > settings + DBF_OFF_SETTINGS_SIZE || !mem_u32(info, &named)
        || named != kind) {
        fail(v, "invalid definition");
        return;
    }
    if (!mem_u32(info + DBF_OFF_DEFINITION_CODE_COUNT_OFFSET, &n)
        || !mem_ptr_aligned(info + DBF_OFF_DEFINITION_CODE_OFFSET, &data, DBF_VAL_CODE_ALIGN) || n < DBF_VAL_CODE_MIN
        || n > DBF_VAL_CODE_MAX) {
        fail(v, "invalid code array");
        return;
    }
    /* R46 took an array outside the block only when the Lua HD2Runtime mod owned it (input.lua:167-168). */
    if (data < settings || data + (uintptr_t)n * DBF_OFF_CODE_STRIDE > settings + DBF_OFF_SETTINGS_SIZE) {
        fail(v, "code array outside the settings block");
        return;
    }
    if (!mem_read(data, d, (size_t)n * DBF_OFF_CODE_STRIDE)) {
        fail(v, "code array unreadable");
        return;
    }
    for (uint32_t i = 0; i < n; i++) {
        if (d[i] < DBF_VAL_DIRECTION_MIN || d[i] > DBF_VAL_DIRECTION_MAX) {
            fail(v, "invalid direction");
            return;
        }
    }
    for (uint32_t i = 0; i < n; i++) row->code[i] = (uint8_t)d[i];
    row->code_len = (uint8_t)n;
}

/* --- the list cards (R46 native.lua:85-100, 264-278; input.lua:230-237) ---------------------------------------- */

static void read_cards(GameView* v, uintptr_t root, uintptr_t payload, bool have_kinds, uint32_t entries,
                       bool have_table)
{
    uintptr_t panel = root + DBF_OFF_HUD_PANEL_OFFSET, list = panel + DBF_OFF_LIST_OFFSET;
    const struct {
        uintptr_t node, parent;
        const char* name;
    } chain[] = {
        { panel, root + DBF_OFF_HUD_CONTAINER_OFFSET, "panel" },
        { root + DBF_OFF_HUD_CONTAINER_OFFSET, root + DBF_OFF_HUD_VIEWPORT_OFFSET, "HUD container" },
        { panel + DBF_OFF_PANEL_FADE_OFFSET, panel, "fade container" },
        { panel + DBF_OFF_PANEL_CONTENT_OFFSET, panel + DBF_OFF_PANEL_FADE_OFFSET, "content container" },
        { list, panel + DBF_OFF_PANEL_CONTENT_OFFSET, "list" },
    };
    for (size_t i = 0; i < sizeof chain / sizeof chain[0]; i++) {
        uintptr_t parent;
        if (!mem_ptr(chain[i].node + DBF_OFF_NODE_PARENT_OFFSET, &parent) || parent != chain[i].parent) {
            note(v, "HUD hierarchy not recognized: ", chain[i].name, " parent mismatch");
            return;
        }
    }
    for (unsigned i = 0; i < DBF_VAL_CARD_COUNT; i++) {
        uintptr_t card = list + DBF_OFF_CARD_FIRST + (uintptr_t)i * DBF_OFF_CARD_STRIDE, parent;
        DbfRow* row = &v->rows[v->row_count];
        uint8_t active;
        if (!mem_ptr(card + DBF_OFF_NODE_PARENT_OFFSET, &parent) || parent != list) {
            card_fails(v, i, " parent mismatch");
            continue;
        }
        if (!mem_u8(card + DBF_OFF_CARD_ACTIVE_OFFSET, &active)) {
            card_fails(v, i, " unreadable");
            continue;
        }
        if (active == DBF_VAL_CARD_INACTIVE) continue;
        if (active != DBF_VAL_CARD_ACTIVE) {
            card_fails(v, i, " state invalid");
            continue;
        }
        if (!mem_u32(card + DBF_OFF_CARD_ENTRY_OFFSET, &row->entry)
            || !mem_read(card + DBF_OFF_CARD_TIMER_OFFSET, row->timer, sizeof row->timer)) {
            memset(row, 0, sizeof *row);
            card_fails(v, i, " unreadable");
            continue;
        }
        row->active = true;
        /* Card +0x3748 is the payload entry; entries past the payload's count have no kind (input.lua:234). */
        if (have_kinds && row->entry < entries
            && !mem_u32(payload + DBF_OFF_PAYLOAD_KINDS_OFFSET + (uintptr_t)row->entry * DBF_OFF_PAYLOAD_ENTRY_STRIDE,
                        &row->kind)) {
            row->kind = 0;
            fail(v, "stratagem entries unreadable");
        }
        if (have_table) read_code(v, row);
        v->row_count++;
    }
}

/* --- the tick -------------------------------------------------------------------------------------------------- */

void game_init(uintptr_t game_dll_base, uint32_t image_size)
{
    g_base = game_dll_base;
    g_image_size = image_size;
    g_table_ok = false;
    g_table_rva = 0;
    g_have_identity = false;
    g_identity_peer = 0;
    g_identity_payload = 0;
}

void game_read(GameView* out)
{
    uintptr_t state, root;
    uint32_t mode, entries = 0;
    uint8_t ready, open;
    bool open_ok, have_kinds = false, have_table = false;
    Local local;
    if (!out) return;
    memset(out, 0, sizeof *out);
    out->build_ok = adm_build_ok(NULL);
    if (g_base == 0) {
        fail(out, "not initialised");
        return;
    }
    if (!admitted(out, FEAT_STATE)) return;

    /* The game state and the HUD (native.lua:76-84, 214-216). */
    if (!mem_ptr(g_base + DBF_RVA_GAME_STATE, &state) || !mem_u32(state + DBF_OFF_GAME_MODE_OFFSET, &mode)) {
        fail(out, "game state unreadable");
        return;
    }
    if (mode != DBF_VAL_GAMEPLAY_MODE) {
        fail(out, "not in gameplay");
        return;
    }
    out->in_gameplay = true;
    if (!mem_ptr(g_base + DBF_RVA_HUD_ROOT, &root) || !mem_u8(root + DBF_OFF_HUD_READY_OFFSET, &ready)
        || ready != DBF_VAL_HUD_READY) {
        fail(out, "HUD not ready");
        return;
    }
    out->hud_ready = true;
    open_ok = mem_u8(root + DBF_OFF_HUD_PANEL_OFFSET + DBF_OFF_OPEN_BYTE_OFFSET, &open);
    if (!open_ok) {
        fail(out, "menu-open flag unreadable");
    } else if (open != DBF_VAL_MENU_OPEN && open != DBF_VAL_MENU_CLOSED) {
        open_ok = false;
        fail(out, "invalid menu-open flag");
    } else {
        out->menu_open = open == DBF_VAL_MENU_OPEN;
    }

    /* The local player and its payload (input.lua:95-139). No payload, no rows. */
    if (!read_local(out, &local)) return;
    out->local_ok = true;

    /* The payload's kinds and the definitions. */
    if (admitted(out, FEAT_STRATAGEMS)) {
        have_kinds = read_entry_count(out, local.payload, &entries);
        have_table = read_table(out);
        if (have_table) out->table_rva = g_table_rva;
    }

    /* The cards, open menu or closed; not when the menu-open byte is not a flag (R46 drops the snapshot then). */
    if (!open_ok || !admitted(out, FEAT_HUD_READ)) return;
    read_cards(out, root, local.payload, have_kinds, entries, have_table);
}
