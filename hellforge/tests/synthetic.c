/* synthetic: the fake 25480438 game for the reader tests (see synthetic.h). Portable C11.
 *
 * The layout below is spelled with R46's own numbers, each with the R46 line it comes from, and on purpose not with the
 * generated header's DBF_RVA_* / DBF_OFF_* / DBF_VAL_* names: the tests then check the address table as well as the
 * readers (a value given to the wrong name in tools/addresses_25480438.json makes a reader miss this image). */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "synthetic.h"

_Static_assert(sizeof(uintptr_t) == 8, "the synthetic image is a 64-bit address space");
_Static_assert(DBF_OFF_CARD_TIMER_SIZE == 0x44u, "the timer block is 0x44 bytes (R46 input.lua:25)");

/* PE headers (R46 native.lua:36-41, 50). */
#define LFANEW 0x80u
#define NT_STAMP 8u       /* TimeDateStamp within the NT headers */
#define NT_IMAGE_SIZE 80u /* SizeOfImage within the NT headers */

/* game.dll globals. */
#define RVA_GAME_STATE 0x3326340u   /* native.lua:81, input.lua:96 */
#define RVA_PLAYERS 0x3326468u      /* input.lua:102 */
#define RVA_AVATARS 0x3326d20u      /* input.lua:108 */
#define RVA_REGISTRY 0x346bf98u     /* input.lua:106 */
#define RVA_HUD_ROOT 0x346d538u     /* native.lua:77 */
#define RVA_MISSION 0x347ce50u      /* input.lua:127 */
#define RVA_SESSION 0x347cef0u      /* input.lua:125 */
#define RVA_SETTINGS 0x348e8f8u     /* input.lua:146 */
#define RVA_DISPLACEMENT 0x66d550u  /* native.lua:51 */
#define RVA_TABLE 0x37cb600u        /* native.lua:52 */
#define TABLE_ENTRIES 150u          /* entries 0..149, 8 bytes each (native.lua:55) */

/* The game's objects, at fixed fake addresses (user space, 8-aligned, far apart). */
#define AT_HUD_ROOT ((uintptr_t)0x20000000000ull)
#define AT_STATE ((uintptr_t)0x21000000000ull)
#define AT_PLAYERS ((uintptr_t)0x22000000000ull)
#define AT_REGISTRY ((uintptr_t)0x23000000000ull)
#define AT_AVATARS ((uintptr_t)0x24000000000ull)
#define AT_UNITS ((uintptr_t)0x25000000000ull)
#define AT_SESSION ((uintptr_t)0x26000000000ull)
#define AT_MISSION ((uintptr_t)0x27000000000ull)
#define AT_SETTINGS ((uintptr_t)0x28000000000ull)
#define AT_LOOKUPS ((uintptr_t)0x29000000000ull)

/* HUD (native.lua:76-100, 203-281). */
#define HUD_READY 0x24e334u            /* native.lua:78 */
#define HUD_VIEWPORT 0x258u            /* native.lua:90 */
#define HUD_CONTAINER 0x820u           /* native.lua:89 */
#define HUD_PANEL (0x24e340u + 0x146dc0u) /* native.lua:87 */
#define PANEL_FADE 0x110u              /* native.lua:91 */
#define PANEL_CONTENT 0x220u           /* native.lua:92 */
#define PANEL_LIST 0x1040u             /* native.lua:88 */
#define PANEL_OPEN 0x38769u            /* native.lua:214 */
#define NODE_PARENT 0xf0u              /* native.lua:95 */
#define CARD_FIRST 0x110u              /* native.lua:98 */
#define CARD_STRIDE 0x3760u            /* native.lua:98 */
#define CARD_ACTIVE 0x36f0u            /* native.lua:267 */
#define CARD_TIMER 0x3718u             /* input.lua:25 */
#define CARD_ENTRY 0x3748u             /* native.lua:276 */
#define CARDS 16

/* Game state (native.lua:82). */
#define STATE_MODE 0xac21cu

/* Lookups (input.lua:74-94): data pointer, capacity +8, empty key +12, seed +16; slots of {key, index}. */
#define LOOKUP_CAPACITY 8u
#define LOOKUP_EMPTY 12u
#define LOOKUP_SEED 16u
#define SLOT_SIZE 8u

/* Local player (input.lua:102-136). */
#define PLAYERS_COUNT 0x88u
#define PLAYERS_NETWORK 0x3a8u
#define PLAYERS_LOOKUP 0xd0u
#define PLAYERS_PEER 0x2c8u
#define PLAYERS_PEER_STRIDE 0x38u
#define REGISTRY_LOOKUP 0xf22ec8u
#define REGISTRY_KEYS 0xf32f20u
#define REGISTRY_KEY_STRIDE 24u
#define AVATARS_COUNT 0x70u
#define AVATARS_LOOKUP 0xf8u
#define AVATARS_UNITS 0x110u
#define AVATARS_FIRST 0x53d8b0u
#define AVATAR_STRIDE 0x1238u
#define UNIT_KEY 8u
#define AVATAR_COMPONENT 0x8d0u
#define COMPONENT_OWNER 0x28u
#define AVATAR_CONTEXT 0x110cu
#define SESSION_PEER 0xb398u
#define MISSION_STRIDE 0x1690u
#define MISSION_PAYLOAD 0x38u
#define MISSION_COUNT 0x2d200u

/* Payload (input.lua:230-234) and definitions (input.lua:163-171). */
#define PAYLOAD_COUNT 0x788u
#define PAYLOAD_KINDS 0x188u
#define PAYLOAD_STRIDE 0x30u
#define DEF_CODE 0x40u
#define DEF_COUNT 0x48u
#define SETTINGS_SIZE 80280u
#define DEF_STRIDE 408u    /* one 400-byte definition per kind, 8 apart, even kinds 4 bytes in (4 mod 8, as live kind 50) */
#define CODES_AT 0xf000u   /* the code arrays, inside the settings block after the definitions */
#define CODE_STRIDE 96u

/* Who the local player is. */
#define LOCAL_NETWORK 3u
#define LOCAL_REGISTRY_INDEX 5u
#define LOCAL_KEY 0x5eed0042u
#define LOCAL_AVATAR 1u
#define LOCAL_CONTEXT 0x2au
#define LOCAL_PLAYER 2u
#define OTHER_NETWORK 9u
#define OTHER_REGISTRY_INDEX 1u
#define OTHER_KEY 0x5eed0001u
#define OTHER_AVATAR 0u
#define OTHER_CONTEXT 0x15u
#define OTHER_PLAYER 0u

static void* g_raw;      /* what calloc returned */
static uint8_t* g_arena; /* g_raw rounded up to 16 */
static int g_carved;     /* arena pages handed out (never reused, so a new page is always zero) */
static int g_count;      /* pages mapped */
static uintptr_t g_page_at[SYN_MAX_PAGES];
static uint8_t* g_page_data[SYN_MAX_PAGES];
static int g_writes;
static bool g_built;
static SynScene g_scene;

/* --- pages ----------------------------------------------------------------------------------------------------- */

static uint8_t* find_page(uintptr_t page)
{
    for (int i = 0; i < g_count; i++)
        if (g_page_at[i] == page) return g_page_data[i];
    return NULL;
}

static uint8_t* make_page(uintptr_t page)
{
    uint8_t* p = find_page(page);
    if (p) return p;
    if (!g_arena) {
        g_raw = calloc((size_t)SYN_MAX_PAGES * SYN_PAGE + 16u, 1);
        if (!g_raw) return NULL;
        g_arena = (uint8_t*)(((uintptr_t)g_raw + 15u) & ~(uintptr_t)15u);
        g_carved = 0;
    }
    if (g_carved >= SYN_MAX_PAGES || g_count >= SYN_MAX_PAGES) return NULL;
    p = g_arena + (size_t)g_carved++ * SYN_PAGE;
    g_page_at[g_count] = page;
    g_page_data[g_count] = p;
    g_count++;
    return p;
}

void syn_free(void)
{
    free(g_raw);
    g_raw = NULL;
    g_arena = NULL;
    g_carved = g_count = 0;
    g_built = false;
}

int syn_read(uintptr_t address, void* out, size_t size)
{
    uint8_t* dst = out;
    if (!out || size == 0 || size - 1 > UINTPTR_MAX - address) return -1;
    while (size > 0) {
        uintptr_t page = address & ~(uintptr_t)(SYN_PAGE - 1u);
        size_t off = (size_t)(address - page), n = SYN_PAGE - off;
        const uint8_t* p = find_page(page);
        if (n > size) n = size;
        if (!p) return -1;
        memcpy(dst, p + off, n);
        dst += n;
        address += n;
        size -= n;
    }
    return 0;
}

int syn_write(uintptr_t address, const void* data, size_t size)
{
    g_writes++;
    return -1;
}

int syn_write_count(void)
{
    return g_writes;
}

bool syn_poke(uintptr_t address, const void* data, size_t size)
{
    const uint8_t* src = data;
    if (!data || size == 0 || size - 1 > UINTPTR_MAX - address) return false;
    while (size > 0) {
        uintptr_t page = address & ~(uintptr_t)(SYN_PAGE - 1u);
        size_t off = (size_t)(address - page), n = SYN_PAGE - off;
        uint8_t* p = make_page(page);
        if (n > size) n = size;
        if (!p) return false;
        memcpy(p + off, src, n);
        src += n;
        address += n;
        size -= n;
    }
    return true;
}

bool syn_poke_u8(uintptr_t address, uint8_t v) { return syn_poke(address, &v, sizeof v); }
bool syn_poke_u32(uintptr_t address, uint32_t v) { return syn_poke(address, &v, sizeof v); }
bool syn_poke_u64(uintptr_t address, uint64_t v) { return syn_poke(address, &v, sizeof v); }

bool syn_unmap(uintptr_t address)
{
    uintptr_t page = address & ~(uintptr_t)(SYN_PAGE - 1u);
    for (int i = 0; i < g_count; i++) {
        if (g_page_at[i] != page) continue;
        g_page_at[i] = g_page_at[g_count - 1];
        g_page_data[i] = g_page_data[g_count - 1];
        g_count--;
        return true;
    }
    return false;
}

/* --- ports ----------------------------------------------------------------------------------------------------- */

static uintptr_t syn_module_base(const char* module, size_t* size)
{
    if (!g_built || !module) return 0;
    if (strcmp(module, "game.dll") == 0) {
        if (size) *size = SYN_IMAGE_SIZE;
        return SYN_GAME_BASE;
    }
    if (strcmp(module, "helldivers2.exe") == 0) {
        if (size) *size = SYN_EXE_SIZE;
        return SYN_EXE_BASE;
    }
    return 0;
}

/* HellForge rewrites the definition-table displacement when it moves the table. */
static int syn_rewrites(uint32_t rva, uint32_t size)
{
    return rva < RVA_DISPLACEMENT + 4u && rva + size > RVA_DISPLACEMENT;
}

static const MemPort MEM_PORT = { syn_read, syn_write };
static const AdmPort ADM_PORT = { syn_module_base, syn_read, syn_rewrites };

const MemPort* syn_mem_port(void) { return &MEM_PORT; }
const AdmPort* syn_adm_port(void) { return &ADM_PORT; }

/* --- where things are ------------------------------------------------------------------------------------------ */

uintptr_t syn_hud_root(void) { return AT_HUD_ROOT; }
uintptr_t syn_panel(void) { return AT_HUD_ROOT + HUD_PANEL; }
uintptr_t syn_list(void) { return syn_panel() + PANEL_LIST; }
uintptr_t syn_card(int index) { return syn_list() + CARD_FIRST + (uintptr_t)index * CARD_STRIDE; }
uintptr_t syn_game_state(void) { return AT_STATE; }
uintptr_t syn_players(void) { return AT_PLAYERS; }
uintptr_t syn_registry(void) { return AT_REGISTRY; }
uintptr_t syn_avatars(void) { return AT_AVATARS; }
uintptr_t syn_local_unit(void) { return AT_UNITS + 0x100u * LOCAL_AVATAR; }
uintptr_t syn_local_avatar(void) { return AT_AVATARS + AVATARS_FIRST + (uintptr_t)LOCAL_AVATAR * AVATAR_STRIDE; }
uintptr_t syn_session(void) { return AT_SESSION; }
uintptr_t syn_mission(void) { return AT_MISSION; }
uintptr_t syn_payload(int mission_entry) { return AT_MISSION + (uintptr_t)mission_entry * MISSION_STRIDE + MISSION_PAYLOAD; }
uintptr_t syn_settings(void) { return AT_SETTINGS; }
uintptr_t syn_definition(uint32_t kind) { return AT_SETTINGS + (uintptr_t)kind * DEF_STRIDE + (kind & 1u ? 0u : 4u); }
uintptr_t syn_code_array(uint32_t kind) { return AT_SETTINGS + CODES_AT + (uintptr_t)kind * CODE_STRIDE + (kind & 1u ? 0u : 4u); }

void syn_timer_bytes(int card, uint32_t entry, uint32_t kind, uint8_t out[DBF_OFF_CARD_TIMER_SIZE])
{
    uint32_t state = 4; /* cooldown (input.lua:27-30) */
    for (unsigned i = 0; i < DBF_OFF_CARD_TIMER_SIZE; i++) out[i] = (uint8_t)(0xa0u + (unsigned)card * 5u + i);
    memcpy(out + (CARD_ENTRY - CARD_TIMER), &entry, sizeof entry); /* the card's entry field */
    memcpy(out + 0x34, &kind, sizeof kind);                          /* the kind the timer is for (input.lua:26) */
    memcpy(out + 0x40, &state, sizeof state);                        /* its state (input.lua:27) */
}

/* --- building -------------------------------------------------------------------------------------------------- */

typedef struct Builder {
    bool ok;
} Builder;

static void put(Builder* b, uintptr_t address, const void* data, size_t size)
{
    if (b->ok && !syn_poke(address, data, size)) b->ok = false;
}
static void put8(Builder* b, uintptr_t address, uint8_t v) { put(b, address, &v, sizeof v); }
static void put32(Builder* b, uintptr_t address, uint32_t v) { put(b, address, &v, sizeof v); }
static void put64(Builder* b, uintptr_t address, uint64_t v) { put(b, address, &v, sizeof v); }

/* A lookup as input.lua:74-94 reads it: every slot empty, then each key at its first free slot from key * seed. */
static void put_lookup(Builder* b, uintptr_t owner, uint32_t offset, uintptr_t data, uint32_t capacity, uint32_t seed,
                       uint32_t empty, int n, const uint32_t* keys, const uint32_t* indices)
{
    put64(b, owner + offset, data);
    put32(b, owner + offset + LOOKUP_CAPACITY, capacity);
    put32(b, owner + offset + LOOKUP_EMPTY, empty);
    put32(b, owner + offset + LOOKUP_SEED, seed);
    for (uint32_t s = 0; s < capacity; s++) {
        put32(b, data + (uintptr_t)s * SLOT_SIZE, empty);
        put32(b, data + (uintptr_t)s * SLOT_SIZE + 4u, 0);
    }
    for (int i = 0; i < n && b->ok; i++) {
        uint32_t hash = keys[i] * seed;
        for (uint32_t probe = 0; probe < capacity; probe++) {
            uintptr_t slot = data + (uintptr_t)((hash + probe) % capacity) * SLOT_SIZE;
            uint32_t current = 0;
            if (syn_read(slot, &current, sizeof current) != 0) b->ok = false;
            if (current != empty) continue;
            put32(b, slot, keys[i]);
            put32(b, slot + 4u, indices[i]);
            break;
        }
    }
}

static void put_header(Builder* b, uintptr_t base, uint32_t stamp, uint32_t image_size)
{
    put(b, base, "MZ", 2);
    put32(b, base + 0x3cu, LFANEW);
    put(b, base + LFANEW, "PE\0\0", 4);
    put32(b, base + LFANEW + NT_STAMP, stamp);
    put32(b, base + LFANEW + NT_IMAGE_SIZE, image_size);
}

/* A peer that is not the local one (entry 0..32 gives 33 different ones). */
static uint64_t other_peer(const SynScene* s, int entry)
{
    return s->peer ^ (0x0101010101010101ull * (uint64_t)(entry + 1));
}

static void put_table(Builder* b, uint32_t rva)
{
    put64(b, SYN_GAME_BASE + rva, 0); /* kind 0 has no definition */
    for (uint32_t kind = 1; kind < TABLE_ENTRIES; kind++) put64(b, SYN_GAME_BASE + rva + kind * 8u, syn_definition(kind));
}

static void put_code(Builder* b, uint32_t kind, int n, const uint8_t* code)
{
    uintptr_t info = syn_definition(kind), data = syn_code_array(kind);
    put32(b, info, kind);
    put64(b, info + DEF_CODE, data);
    put32(b, info + DEF_COUNT, (uint32_t)n);
    for (int i = 0; i < n; i++) put32(b, data + (uintptr_t)i * 4u, code[i]);
}

bool syn_build(const SynScene* s)
{
    Builder b = { true };
    uintptr_t root = AT_HUD_ROOT, panel = syn_panel(), list = syn_list();
    if (!s || s->stratagem_count < 0 || s->stratagem_count > SYN_MAX_STRATAGEMS || s->mission_peers < 1
        || s->mission_peers > 32 || s->local_entry < 0 || s->local_entry >= s->mission_peers)
        return false;
    for (int i = 0; i < s->stratagem_count; i++)
        if (s->stratagems[i].code_len > SYN_CODE_MAX) return false;
    for (int i = 0; i < CARDS; i++)
        if (s->card_entry[i] < SYN_INACTIVE) return false;
    syn_free();
    g_scene = *s;
    g_built = true;

    /* The modules: headers, then every witness, then the globals (a global wins over a witness byte). */
    put_header(&b, SYN_GAME_BASE, SYN_GAME_STAMP, SYN_IMAGE_SIZE);
    put_header(&b, SYN_EXE_BASE, SYN_EXE_STAMP, SYN_EXE_SIZE);
    for (int i = 0; i < dbf_witness_count; i++)
        if (dbf_witnesses[i].size > 0 && dbf_witnesses[i].bytes)
            put(&b, SYN_GAME_BASE + dbf_witnesses[i].rva, dbf_witnesses[i].bytes, dbf_witnesses[i].size);
    put64(&b, SYN_GAME_BASE + RVA_GAME_STATE, AT_STATE);
    put64(&b, SYN_GAME_BASE + RVA_PLAYERS, AT_PLAYERS);
    put64(&b, SYN_GAME_BASE + RVA_AVATARS, AT_AVATARS);
    put64(&b, SYN_GAME_BASE + RVA_REGISTRY, AT_REGISTRY);
    put64(&b, SYN_GAME_BASE + RVA_HUD_ROOT, AT_HUD_ROOT);
    put64(&b, SYN_GAME_BASE + RVA_MISSION, AT_MISSION);
    put64(&b, SYN_GAME_BASE + RVA_SESSION, AT_SESSION);
    put64(&b, SYN_GAME_BASE + RVA_SETTINGS, AT_SETTINGS);
    put32(&b, SYN_GAME_BASE + RVA_DISPLACEMENT, s->table_rva);
    put_table(&b, RVA_TABLE); /* the vanilla table is always there; a moved one is a copy */
    if (s->table_rva != RVA_TABLE) put_table(&b, s->table_rva);

    /* Game state and HUD. */
    put32(&b, AT_STATE + STATE_MODE, s->game_mode);
    put8(&b, root + HUD_READY, s->hud_ready);
    put64(&b, root + HUD_VIEWPORT + NODE_PARENT, root);
    put64(&b, root + HUD_CONTAINER + NODE_PARENT, root + HUD_VIEWPORT);
    put64(&b, panel + NODE_PARENT, root + HUD_CONTAINER);
    put64(&b, panel + PANEL_FADE + NODE_PARENT, panel);
    put64(&b, panel + PANEL_CONTENT + NODE_PARENT, panel + PANEL_FADE);
    put64(&b, list + NODE_PARENT, panel + PANEL_CONTENT);
    put8(&b, panel + PANEL_OPEN, s->menu_open);
    for (int i = 0; i < CARDS; i++) {
        uintptr_t card = syn_card(i);
        int entry = s->card_entry[i];
        put64(&b, card + NODE_PARENT, list);
        put8(&b, card + CARD_ACTIVE, entry == SYN_INACTIVE ? 0 : 1);
        if (entry != SYN_INACTIVE) {
            uint8_t timer[DBF_OFF_CARD_TIMER_SIZE];
            uint32_t kind = entry < s->stratagem_count ? s->stratagems[entry].kind : 0;
            syn_timer_bytes(i, (uint32_t)entry, kind, timer); /* holds the entry field too */
            put(&b, card + CARD_TIMER, timer, sizeof timer);
        }
    }

    /* The local player: player manager -> registry -> avatar manager -> unit and avatar -> player manager's peer. */
    {
        static const uint32_t NETWORKS[2] = { LOCAL_NETWORK, OTHER_NETWORK };
        static const uint32_t REGISTRY_INDICES[2] = { LOCAL_REGISTRY_INDEX, OTHER_REGISTRY_INDEX };
        static const uint32_t KEYS[2] = { LOCAL_KEY, OTHER_KEY };
        static const uint32_t AVATARS[2] = { LOCAL_AVATAR, OTHER_AVATAR };
        static const uint32_t CONTEXTS[2] = { LOCAL_CONTEXT, OTHER_CONTEXT };
        static const uint32_t PLAYERS[2] = { LOCAL_PLAYER, OTHER_PLAYER };
        put32(&b, AT_PLAYERS + PLAYERS_COUNT, 2);
        put32(&b, AT_PLAYERS + PLAYERS_NETWORK, LOCAL_NETWORK);
        /* The registry's slots are 4 mod 8, as the live r7 capture's (input.lua:82). */
        put_lookup(&b, AT_REGISTRY, REGISTRY_LOOKUP, AT_LOOKUPS + 0xc4cu, 64, 0x9e3779b1u, 0xffffffffu, 2, NETWORKS,
                   REGISTRY_INDICES);
        put32(&b, AT_REGISTRY + REGISTRY_KEYS + REGISTRY_KEY_STRIDE * LOCAL_REGISTRY_INDEX, LOCAL_KEY);
        put32(&b, AT_REGISTRY + REGISTRY_KEYS + REGISTRY_KEY_STRIDE * OTHER_REGISTRY_INDEX, OTHER_KEY);
        put32(&b, AT_AVATARS + AVATARS_COUNT, 2);
        put_lookup(&b, AT_AVATARS, AVATARS_LOOKUP, AT_LOOKUPS + 0x1000u, 8, 0x85ebca6bu, 0xffffffffu, 2, KEYS, AVATARS);
        for (int i = 0; i < 2; i++) {
            uintptr_t unit = AT_UNITS + 0x100u * AVATARS[i];
            uintptr_t avatar = AT_AVATARS + AVATARS_FIRST + (uintptr_t)AVATARS[i] * AVATAR_STRIDE;
            put64(&b, AT_AVATARS + AVATARS_UNITS + 8u * AVATARS[i], unit);
            put32(&b, unit + UNIT_KEY, KEYS[i]);
            put32(&b, avatar + AVATAR_COMPONENT + COMPONENT_OWNER, KEYS[i]);
            put32(&b, avatar + AVATAR_CONTEXT, CONTEXTS[i]);
        }
        put_lookup(&b, AT_PLAYERS, PLAYERS_LOOKUP, AT_LOOKUPS + 0x2000u, 32, 0xc2b2ae35u, 0, 2, CONTEXTS, PLAYERS);
        put64(&b, AT_PLAYERS + PLAYERS_PEER + PLAYERS_PEER_STRIDE * LOCAL_PLAYER, s->peer);
        put64(&b, AT_PLAYERS + PLAYERS_PEER + PLAYERS_PEER_STRIDE * OTHER_PLAYER, other_peer(s, 32));
        put64(&b, AT_SESSION + SESSION_PEER, s->peer);
    }

    /* The mission: one entry per peer; the local one carries the scene's stratagems, the others two of their own. */
    put32(&b, AT_MISSION + MISSION_COUNT, (uint32_t)s->mission_peers);
    for (int i = 0; i < s->mission_peers; i++) {
        uintptr_t payload = syn_payload(i);
        put64(&b, AT_MISSION + (uintptr_t)i * MISSION_STRIDE, i == s->local_entry ? s->peer : other_peer(s, i));
        if (i == s->local_entry) {
            put32(&b, payload + PAYLOAD_COUNT, (uint32_t)s->stratagem_count);
            for (int j = 0; j < s->stratagem_count; j++)
                put32(&b, payload + PAYLOAD_KINDS + (uintptr_t)j * PAYLOAD_STRIDE, s->stratagems[j].kind);
        } else {
            put32(&b, payload + PAYLOAD_COUNT, 2);
            put32(&b, payload + PAYLOAD_KINDS, 7);
            put32(&b, payload + PAYLOAD_KINDS + PAYLOAD_STRIDE, 33);
        }
    }

    /* Settings: a definition and a code for every vanilla kind (made-up codes), then the scene's codes over them. */
    for (uint32_t kind = 1; kind < TABLE_ENTRIES; kind++) {
        uint8_t code[3] = { (uint8_t)(1u + kind % 4u), (uint8_t)(1u + (kind + 1u) % 4u), (uint8_t)(1u + (kind + 2u) % 4u) };
        put_code(&b, kind, 3, code);
    }
    for (int i = 0; i < s->stratagem_count; i++) {
        const SynStratagem* st = &s->stratagems[i];
        if (st->kind >= 1 && st->kind < TABLE_ENTRIES) put_code(&b, st->kind, st->code_len, st->code);
    }
    if (syn_definition(TABLE_ENTRIES - 1u) + 400u > AT_SETTINGS + CODES_AT
        || syn_code_array(TABLE_ENTRIES - 1u) + 4u * SYN_CODE_MAX > AT_SETTINGS + SETTINGS_SIZE)
        b.ok = false;
    return b.ok;
}

void syn_default(SynScene* s)
{
    static const SynStratagem DEFAULTS[4] = {
        { 118, 3, { 2, 2, 1 } },          /* Orbital Precision Strike (codes here are made up) */
        { 4, 5, { 2, 3, 4, 1, 1 } },      /* Orbital Gatling Barrage */
        { 50, 6, { 3, 4, 1, 2, 3, 3 } },  /* TD-110 Maelstrom: its definition is 4 mod 8, as live */
        { 63, 5, { 3, 4, 3, 1, 4 } },     /* LAS-98 Laser Cannon: an odd kind, its definition 8-aligned */
    };
    if (!s) return;
    memset(s, 0, sizeof *s);
    s->game_mode = 4;
    s->hud_ready = 1;
    s->menu_open = 1;
    s->peer = 0x1100aabbccdd2233ull;
    s->mission_peers = 3;
    s->local_entry = 1;
    s->stratagem_count = 4;
    memcpy(s->stratagems, DEFAULTS, sizeof DEFAULTS);
    for (int i = 0; i < CARDS; i++) s->card_entry[i] = i < 4 ? i : SYN_INACTIVE;
    s->table_rva = RVA_TABLE;
}

bool syn_relocate_table(uint32_t rva)
{
    uint8_t table[TABLE_ENTRIES * 8u];
    if (!g_built || syn_read(SYN_GAME_BASE + RVA_TABLE, table, sizeof table) != 0) return false;
    return syn_poke(SYN_GAME_BASE + rva, table, sizeof table) && syn_poke_u32(SYN_GAME_BASE + RVA_DISPLACEMENT, rva);
}

bool syn_change_peer(uint64_t peer)
{
    if (!g_built) return false;
    g_scene.peer = peer;
    return syn_poke_u64(AT_SESSION + SESSION_PEER, peer)
        && syn_poke_u64(AT_PLAYERS + PLAYERS_PEER + PLAYERS_PEER_STRIDE * LOCAL_PLAYER, peer)
        && syn_poke_u64(AT_MISSION + (uintptr_t)g_scene.local_entry * MISSION_STRIDE, peer);
}
