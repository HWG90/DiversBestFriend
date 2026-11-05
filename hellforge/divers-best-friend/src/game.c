/* game: the read-only readers (see game.h), ported from R46's native.lua (hud, valid, snapshot) and input.lua (lookup,
 * context, decorate's payload and kinds); the definition table and the codes are codes.c's. Portable C11: standard
 * headers, memory.h, admission.h, codes.h and the generated address header only. Every number below is a DBF_RVA_*,
 * DBF_OFF_* or DBF_VAL_* from that header, each with its R46 line, except LOOKUP_PROBE_LIMIT, which is DBF's own (Plan
 * 1's final review). */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "codes.h"
#include "game.h"
#include "memory.h"

_Static_assert(DBF_VAL_CODE_MAX <= DBF_CODE_CAPACITY, "DbfRow.code holds R46's longest code");
_Static_assert(sizeof(float) == sizeof(uint32_t), "a card's layout target is two 4-byte floats (R46 native.lua:65-70)");

/* Not from R46 (which probed up to the whole capacity, 65536 reads for one lookup): Plan 1's final review capped the
 * probes of one lookup at 256, so a table with no empty slot costs at most 256 reads. */
#define LOOKUP_PROBE_LIMIT 256u

static uintptr_t g_base; /* game.dll; 0 before game_init */
static bool g_have_identity; /* the local identity of the last read that found one */
static uint64_t g_identity_peer;
static uintptr_t g_identity_payload;
static const char* g_lookup_why; /* why the last game_lookup failed (a static string), for game_read's reason */

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

static bool lookup_fails(const char* why)
{
    g_lookup_why = why;
    return false;
}

/* input.lua:74-94: an open-addressing table at owner+offset holding the slots' pointer (4-aligned), the capacity (+8, a
 * power of two up to 65536), the empty key (+12) and the seed (+16). Slots are {key, index} pairs of uint32_t; a key's
 * probe starts at key * seed (mod 2^32) and ends at the empty key, or after LOOKUP_PROBE_LIMIT probes. The index must
 * be below `limit`. */
bool game_lookup(uintptr_t owner, uint32_t offset, uint32_t key, uint32_t limit, uint32_t* index)
{
    uintptr_t table = owner + offset, slots;
    uint32_t capacity, empty, seed, hash, probes, at;
    if (!index) return lookup_fails("lookup unreadable");
    if (!mem_u32(table + DBF_OFF_LOOKUP_CAPACITY_OFFSET, &capacity)) return lookup_fails("lookup unreadable");
    if (capacity == 0 || capacity > DBF_VAL_LOOKUP_MAX_CAPACITY) return lookup_fails("invalid lookup capacity");
    if ((capacity & (capacity - 1u)) != 0) return lookup_fails("lookup capacity is not a power of two");
    if (!mem_u32(table + DBF_OFF_LOOKUP_EMPTY_OFFSET, &empty) || !mem_u32(table + DBF_OFF_LOOKUP_SEED_OFFSET, &seed)
        || !mem_ptr_aligned(table, &slots, DBF_VAL_LOOKUP_ALIGN))
        return lookup_fails("lookup unreadable");
    hash = key * seed;
    probes = capacity < LOOKUP_PROBE_LIMIT ? capacity : LOOKUP_PROBE_LIMIT;
    for (uint32_t probe = 0; probe < probes; probe++) {
        uintptr_t slot = slots + (uintptr_t)(((uint64_t)hash + probe) % capacity) * DBF_OFF_LOOKUP_SLOT_SIZE;
        uint32_t found;
        if (!mem_u32(slot, &found)) return lookup_fails("lookup unreadable");
        if (found == key) {
            if (!mem_u32(slot + DBF_OFF_LOOKUP_SLOT_INDEX_OFFSET, &at)) return lookup_fails("lookup unreadable");
            if (at >= limit) return lookup_fails("lookup index out of bounds");
            *index = at;
            return true;
        }
        if (found == empty) return lookup_fails("local ownership mapping unavailable");
    }
    return lookup_fails(probes < capacity ? "lookup probe limit" : "local ownership mapping unavailable");
}

/* game_lookup, with its failure in the view's reason. */
static bool lookup(GameView* v, uintptr_t owner, uint32_t offset, uint32_t key, uint32_t limit, uint32_t* index)
{
    if (game_lookup(owner, offset, key, limit, index)) return true;
    return fail(v, g_lookup_why);
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

/* R46's display path (input.lua:218-229, what decorate and the cooldown dock use): the session's peer, the one mission
 * entry carrying it, and that entry's payload. The (peer, payload) found is the local identity: when either is not the
 * last one found, this read reports the change instead of a payload. */
static bool read_payload(GameView* v, Local* out)
{
    uintptr_t mission, payload = 0;
    uint32_t peers;
    uint64_t peer;
    if (!session_peer(&peer)) return fail(v, "session unreadable");
    if (peer == 0) return fail(v, "local session unavailable");
    if (g_have_identity && peer != g_identity_peer) return identity_changed(v);
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

/* R46's code-entry context (input.lua:102-126, what display_codes and entry use): player manager -> network index ->
 * registry key -> avatar (unit and input owner agree, the menu-active word readable) -> player context -> the player's
 * peer, which must be the session's. Its mission step (input.lua:127-136) finds the entry carrying that same peer, the
 * payload read_payload found. local_ok, the codes and `out` depend on it; `out` is written only when it holds. */
static bool read_local_player(GameView* v, const Local* local, GameLocal* out)
{
    uintptr_t pm, registry, manager, unit, avatar, ui;
    uint32_t players, network, registry_index, key, avatars, avatar_index, unit_key, owner, menu, context, player_index;
    uint32_t word;
    uint64_t peer;
    GameLocal l;
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
    /* The menu-active word (input.lua:118-119) is read but its bit is not required: R46's allow_closed. */
    if (!mem_u32(avatar + DBF_OFF_AVATAR_MENU_OFFSET, &menu) || !mem_u32(avatar + DBF_OFF_AVATAR_CONTEXT_OFFSET, &context))
        return fail(v, "avatar unreadable");

    if (!lookup(v, pm, DBF_OFF_PLAYERS_LOOKUP_OFFSET, context, DBF_VAL_PLAYER_INDEX_LIMIT, &player_index)) return false;
    if (!mem_u64(pm + DBF_OFF_PLAYERS_PEER_OFFSET + (uintptr_t)player_index * DBF_OFF_PLAYERS_PEER_STRIDE, &peer))
        return fail(v, "player manager unreadable");
    if (peer == 0 || peer != local->peer) return fail(v, "local peer mismatch"); /* input.lua:126 */

    /* The context R46's context() returns (input.lua:114-137). */
    memset(&l, 0, sizeof l);
    l.manager = manager;
    l.avatar = avatar;
    l.component = avatar + DBF_OFF_AVATAR_COMPONENT_OFFSET;
    l.actions = manager + (uintptr_t)avatar_index * DBF_OFF_ACTIONS_STRIDE + DBF_OFF_ACTIONS_OFFSET;
    l.input_owner = manager + (uintptr_t)avatar_index * DBF_OFF_ACTIONS_STRIDE + DBF_OFF_INPUT_OWNER_OFFSET;
    l.payload = local->payload;
    l.key = key;
    l.index = avatar_index;
    l.menu_active = (menu & DBF_VAL_MENU_ACTIVE_MASK) != 0;
    /* R46 reads these two in its release paths (input.lua:294-295, 313), not in context(): when they cannot be read the
     * chain still holds, controls stays 0 and unobstructed false, and reason says which. */
    if (!mem_ptr(g_base + DBF_RVA_CONTROLS, &l.controls)) fail(v, "controls unreadable");
    if (mem_ptr(g_base + DBF_RVA_UI, &ui)
        && mem_u32(ui + DBF_OFF_UI_OBSTRUCTION_OFFSET + DBF_OFF_UI_OBSTRUCTION_WORD_OFFSET, &word))
        l.unobstructed = word == DBF_VAL_UI_UNOBSTRUCTED;
    else
        fail(v, "UI unreadable");
    *out = l;
    return true;
}

/* --- payload, definitions and codes (R46 input.lua:230-234; the table and codes are codes.c's) ------------------ */

static bool read_entry_count(GameView* v, uintptr_t payload, uint32_t* count)
{
    if (!mem_u32(payload + DBF_OFF_PAYLOAD_COUNT_OFFSET, count)) return fail(v, "stratagem entries unreadable");
    if (*count > DBF_VAL_PAYLOAD_ENTRY_MAX) return fail(v, "invalid stratagem entry count");
    return true;
}

/* The definition table, read again on every read (codes_table): its reason is the view's. */
static bool read_table(GameView* v)
{
    char why[DBF_REASON_SIZE];
    uint32_t max_kind;
    if (codes_table(&max_kind, why, sizeof why)) return true;
    return fail(v, why);
}

/* The row's code (codes_read, with the scramble remap when the code-entry context is given). A row without a kind (its
 * entry is not in the payload) gets none and no reason; any other failure leaves the row without a code and gives the
 * reason. Returns the kind whose code was read (the scramble may remap it), 0 for none. */
static uint32_t read_code(GameView* v, DbfRow* row, const GameLocal* local)
{
    DbfCode code;
    char why[DBF_REASON_SIZE];
    if (row->kind == 0) return 0;
    if (!codes_read(row->kind, local, &code, why, sizeof why)) {
        if (why[0] != '\0') fail(v, why);
        return 0;
    }
    memcpy(row->code, code.dir, code.len);
    row->code_len = code.len;
    return code.kind_used;
}

/* --- the list cards (R46 native.lua:85-100, 264-278; input.lua:230-237) ---------------------------------------- */

/* R46's pair() (native.lua:71): a layout float is usable when it is a number no further than 100000 from 0. */
static bool position_ok(float f)
{
    return f >= -(float)DBF_VAL_CARD_POSITION_MAX && f <= (float)DBF_VAL_CARD_POSITION_MAX; /* false for NaN */
}

/* Codes are read only when `local` is not NULL: the definition table was accepted and the code-entry chain held. */
static void read_cards(GameView* v, uintptr_t root, uintptr_t payload, bool have_kinds, uint32_t entries,
                       const GameLocal* local)
{
    uint32_t used[DBF_VAL_CARD_COUNT]; /* per row: the kind whose code it got, 0 for none */
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
        float target[2];
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
            || !mem_read(card + DBF_OFF_CARD_TIMER_OFFSET, row->timer, sizeof row->timer)
            || !mem_read(card + DBF_OFF_CARD_TARGET_OFFSET, target, sizeof target)) {
            memset(row, 0, sizeof *row);
            card_fails(v, i, " unreadable");
            continue;
        }
        /* The card's layout target (native.lua:274-276): its second float is the row's list position. R46 dropped the
         * whole list when a pair was unusable ("Native row layout unavailable"); here that card is skipped. */
        if (!position_ok(target[0]) || !position_ok(target[1])) {
            memset(row, 0, sizeof *row);
            card_fails(v, i, " layout unavailable");
            continue;
        }
        row->card = card;
        row->list_y = target[1];
        row->active = true;
        /* Card +0x3748 is the payload entry; entries past the payload's count have no kind (input.lua:234). */
        if (have_kinds && row->entry < entries
            && !mem_u32(payload + DBF_OFF_PAYLOAD_KINDS_OFFSET + (uintptr_t)row->entry * DBF_OFF_PAYLOAD_ENTRY_STRIDE,
                        &row->kind)) {
            row->kind = 0;
            fail(v, "stratagem entries unreadable");
        }
        used[v->row_count] = local ? read_code(v, row, local) : 0;
        v->row_count++;
    }
    /* Two kinds on one HellForge array (codes.h, rule 3): the kind read first got its code before the second showed the
     * share, so it is dropped here, and both rows go without. */
    for (int i = 0; i < v->row_count; i++) {
        if (used[i] == 0 || !codes_shared(used[i])) continue;
        memset(v->rows[i].code, 0, sizeof v->rows[i].code);
        v->rows[i].code_len = 0;
        fail(v, "shared code array");
    }
}

/* --- the tick -------------------------------------------------------------------------------------------------- */

void game_init(uintptr_t game_dll_base, uint32_t image_size)
{
    /* Both or neither (Plan 1's final review): codes' moved-table rule needs the image's size to tell inside from
     * outside. */
    g_base = image_size != 0 ? game_dll_base : 0;
    codes_set_image(g_base, g_base != 0 ? image_size : 0);
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

    /* The local payload by R46's display path: no payload (or a new one), no rows. Then the code-entry chain, which
     * only codes need. */
    if (!read_payload(out, &local)) return;
    out->local_ok = read_local_player(out, &local, &out->local);

    /* The payload's kinds and the definitions. */
    if (admitted(out, FEAT_STRATAGEMS)) {
        have_kinds = read_entry_count(out, local.payload, &entries);
        have_table = read_table(out);
        if (have_table) out->table_rva = (uint32_t)(codes_table_at() - g_base); /* the disp32: negative below the image */
    }

    /* The cards, open menu or closed; not when the menu-open byte is not a flag (R46 drops the snapshot then). */
    if (!open_ok || !admitted(out, FEAT_HUD_READ)) return;
    read_cards(out, root, local.payload, have_kinds, entries, have_table && out->local_ok ? &out->local : NULL);
    out->scramble_known = have_table && codes_scramble_asked();
}
