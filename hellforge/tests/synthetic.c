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
#define RVA_UI 0x347ce28u           /* input.lua:294 */
#define RVA_CONTROLS 0x347cf18u     /* input.lua:313 */
#define RVA_DISPLACEMENT 0x66d550u  /* native.lua:51 */
#define RVA_TABLE 0x37cb600u        /* native.lua:52 */
#define TABLE_ENTRIES 150u          /* entries 0..149, 8 bytes each (native.lua:55) */
#define RVA_POSITIONS 0x3326508u    /* input.lua:150 */

/* HellForge's moved definition table (HF stratagems.c:42-44, 372-387): 198 slots (150 + 48), the names (198 + 1), then a
 * 400-byte row per new type. */
#define HF_SLOTS 198u
#define HF_ROWS_AT (HF_SLOTS * 8u + HF_SLOTS * 8u + 8u)
#define HF_ROW 400u
#define HF_NEW 48u
#define LOADER_MOD_CODES 0x1000u    /* the fake loader image: one 64-byte array per new type from here */
#define LOADER_SPARES 0x8000u       /* and 64 spare 64-byte arrays from here (a Lua mod's set_code) */
#define LOADER_ARRAY 0x40u
#define LOADER_SPARE_COUNT 64

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
#define AT_UI ((uintptr_t)0x2a000000000ull)
#define AT_CONTROLS ((uintptr_t)0x2b000000000ull)
#define AT_BINDINGS ((uintptr_t)0x2e000000000ull) /* the live binding map's bucket table */
#define AT_POSITIONS ((uintptr_t)0x2f000000000ull)
#define AT_POSITION_ENTRIES ((uintptr_t)0x2f100000000ull)

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
#define CARD_TARGET 0x3740u            /* native.lua:60 (animation_b), its second float the row's list_y (native.lua:276) */
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
#define AVATAR_MENU 0xfd8u             /* input.lua:118: bit 9 (/512 % 2) is the menu-active bit */
#define MENU_ACTIVE_BIT 512u
#define ACTIONS_STRIDE 0xa7aecu        /* input.lua:137 */
#define ACTIONS 0x4118u
#define INPUT_OWNER 0x150u
#define UI_OBSTRUCTION (0x429cu + 20u) /* input.lua:295 */
#define AVATAR_SEED 0x11b8u           /* input.lua:157: the scramble remap's seed */
#define POSITIONS_LOOKUP 0x40u         /* input.lua:151 */
#define POSITIONS_ENTRIES 0x68u        /* input.lua:152 */
#define POSITION_STRIDE 0x308u         /* input.lua:152 */
#define POSITION_AT 0x2e0u             /* input.lua:152: 12 bytes */
#define SESSION_PEER 0xb398u
/* The input component and the direction actions (input.lua:240-282). */
#define COMPONENT_COUNT 0x0u           /* input.lua:241, 258: u32, the directions the game has taken */
#define COMPONENT_DIRECTIONS 3u        /* input.lua:260: direction i (1-based) at component + 3 + i */
#define COMPONENT_MATCHED 0x14u        /* input.lua:242, 259, 275: u32, the kind matched once the code is complete */
#define COMPONENT_QUEUED 0x2cu         /* input.lua:242: u32 */
#define ACTION_STRIDE 32u              /* input.lua:188, 265: action a's byte at actions + 32 * a */
#define ACTION_LEFT 1u                 /* input.lua:263: "left=1 right=2 up=3 down=4" */
#define ACTION_DOWN 4u
#define ACTION_PRESSED 1u              /* input.lua:267: the byte a press sets (0 released, input.lua:271) */
#define INPUT_CODE_MAX 12u             /* input.lua:166: a code has at most 12 directions */
/* The menu latch (R46 menu_latch.lua:9-75, input.lua:283-340), spelled with R46's numbers. */
#define BINDING_MAP 686800u            /* menu_latch.lua:11: the live binding map at controls + 686800 */
#define BINDING_CAPACITY_AT 8u         /* menu_latch.lua:12: u32 map+8, the bucket count */
#define BINDING_CAPACITY 256u          /* menu_latch.lua:12, 14 */
#define BUCKET_STRIDE 328u             /* menu_latch.lua:15 */
#define BUCKET_COUNT_AT 4u             /* menu_latch.lua:17: u32, the bucket's records (at most 16) */
#define BUCKET_RECORDS 8u              /* menu_latch.lua:32, 64-65: record i at bucket + 8 + i * 20 */
#define RECORD_SIZE 20u                /* menu_latch.lua:65 */
#define MENU_KEY 0x50000u              /* menu_latch.lua:16: Display Stratagem List's bucket */
#define MENU_BUCKET 37                 /* where this image puts it (not first, so a wrong stride misses it) */
#define OTHER_BUCKET 12                /* another action's bucket, with a Hold record of its own */
#define OTHER_KEY_BINDING 0x40000u
#define FILLER_KEY 0x60000u            /* the other buckets' keys: 0x60000 + i */
#define CONTROLS_MENU_ACTION (808u + 32u * (97u * 5u))       /* input.lua:314: u8, 0 or 1 */
#define CONTROLS_MENU_TRIGGER (808u + 32u * (97u * 5u) + 24u) /* menu_latch.lua:38, 53: u32 trigger type */
#define ACTION_TRIGGER 24u             /* input.lua:287, menu_latch.lua:53: u32 at actions + 24, the menu action's */
#define MENU_DOWN 0u                   /* input.lua:289: the menu action's byte, at actions + 0 */
#define WEAPON 0x420u                  /* input.lua:139: the weapon block at avatar + 0x420, its owner key at + 0 */
#define WEAPON_SLOT 4u                 /* input.lua:332: u32, the requested slot */
#define TRIGGER_HOLD 2u                /* menu_latch.lua:67 */
#define START_SLOT 1u                  /* the slot this image's weapon has requested (a primary) */
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
#define ALTERNATE_AT 0x12c00u /* syn_alternate_definition: 400 bytes, then its code array, before SETTINGS_SIZE */

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
#define LOCAL_POSITION 6u
#define OTHER_POSITION 2u
#define PROBE_AT 0x8c4cu     /* syn_registry_probe's slots: 4 mod 8, as the registry's */
#define PROBE_MAX 1024u
#define PROBE_FILLER 0x100000u /* keys that are neither the local network index nor the empty key */

static void* g_raw;      /* what calloc returned */
static uint8_t* g_arena; /* g_raw rounded up to 16 */
static int g_carved;     /* arena pages handed out (never reused, so a new page is always zero) */
static int g_count;      /* pages mapped */
static uintptr_t g_page_at[SYN_MAX_PAGES];
static uint8_t* g_page_data[SYN_MAX_PAGES];
static int g_writes;
static int g_mapped_writes;
static bool g_built;
static SynScene g_scene;
static uintptr_t g_block;               /* HellForge's moved block (syn_move_table); 0 when the table is not moved */
static uintptr_t g_mod_row[HF_NEW];     /* rows of the mod stratagems added (by kind - 150); 0 when not added */
static bool g_mod_tomb[HF_NEW];         /* tombstoned: stratagem_row says 0 */

/* Display Stratagem List's records (menu_latch.lua:64-71): flags at + 0 (format nibble (flags / 16) % 16 == 4, trigger
 * nibble (flags / 65536) % 16), a u32 the latch keeps, the trigger at + 8 (Hold 2, LongHold 9, Press 0) and eight more
 * bytes it keeps. A keyboard Hold, a Press record and a controller LongHold. */
const uint8_t SYN_MENU_RECORDS[3][20] = {
    { 0x43, 0x00, 0x12, 0x00, 0x4b, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x11, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00 },
    { 0x41, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x33, 0x00, 0x00, 0x00, 0x44, 0x00, 0x00, 0x00 },
    { 0x47, 0x00, 0x39, 0x00, 0x02, 0x20, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x55, 0x00, 0x00, 0x00, 0x66, 0x00, 0x00, 0x00 },
};
/* Another action's Hold record, in its own bucket: the latch never touches it. */
const uint8_t SYN_OTHER_RECORD[20] = {
    0x43, 0x00, 0x12, 0x00, 0x4c, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x77, 0x00, 0x00, 0x00, 0x88, 0x00, 0x00, 0x00,
};

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

int syn_write_mapped(uintptr_t address, const void* data, size_t size)
{
    g_mapped_writes++;
    if (!data || size == 0 || size - 1 > UINTPTR_MAX - address) return -1;
    /* Every page first, so a range that leaves the mapped pages writes nothing. */
    for (uintptr_t page = address & ~(uintptr_t)(SYN_PAGE - 1u); page <= address + (size - 1); page += SYN_PAGE) {
        if (!find_page(page)) return -1;
        if (page > UINTPTR_MAX - SYN_PAGE) break;
    }
    return syn_poke(address, data, size) ? 0 : -1;
}

int syn_mapped_write_count(void)
{
    return g_mapped_writes;
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
static const MemPort MEM_PORT_WRITABLE = { syn_read, syn_write_mapped };
static const AdmPort ADM_PORT = { syn_module_base, syn_read, syn_rewrites };

const MemPort* syn_mem_port(void) { return &MEM_PORT; }
const MemPort* syn_mem_port_writable(void) { return &MEM_PORT_WRITABLE; }
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
uintptr_t syn_ui(void) { return AT_UI; }
uintptr_t syn_controls(void) { return AT_CONTROLS; }
uintptr_t syn_bindings(void) { return AT_BINDINGS; }
uintptr_t syn_binding_bucket(int index) { return AT_BINDINGS + (uintptr_t)index * BUCKET_STRIDE; }
uintptr_t syn_binding_record(int bucket, int record)
{
    return syn_binding_bucket(bucket) + BUCKET_RECORDS + (uintptr_t)record * RECORD_SIZE;
}
int syn_menu_bucket(void) { return MENU_BUCKET; }
int syn_other_bucket(void) { return OTHER_BUCKET; }
uintptr_t syn_controls_menu_action(void) { return AT_CONTROLS + CONTROLS_MENU_ACTION; }
uintptr_t syn_controls_menu_trigger(void) { return AT_CONTROLS + CONTROLS_MENU_TRIGGER; }
uintptr_t syn_local_menu_trigger(void) { return syn_local_actions() + ACTION_TRIGGER; }
uintptr_t syn_local_weapon(void) { return syn_local_avatar() + WEAPON; }
uintptr_t syn_local_component(void) { return syn_local_avatar() + AVATAR_COMPONENT; }
uintptr_t syn_local_actions(void) { return AT_AVATARS + (uintptr_t)LOCAL_AVATAR * ACTIONS_STRIDE + ACTIONS; }
uintptr_t syn_local_input_owner(void) { return AT_AVATARS + (uintptr_t)LOCAL_AVATAR * ACTIONS_STRIDE + INPUT_OWNER; }
uint32_t syn_local_key(void) { return LOCAL_KEY; }
uint32_t syn_local_index(void) { return LOCAL_AVATAR; }
float syn_list_y(int card) { return 412.5f - 47.25f * (float)card; }

void syn_timer_bytes(int card, uint32_t entry, uint32_t kind, uint8_t out[DBF_OFF_CARD_TIMER_SIZE])
{
    uint32_t state = 4; /* cooldown (input.lua:27-30) */
    for (unsigned i = 0; i < DBF_OFF_CARD_TIMER_SIZE; i++) out[i] = (uint8_t)(0xa0u + (unsigned)card * 5u + i);
    float target[2] = { 30.0f + (float)card, syn_list_y(card) };
    memcpy(out + (CARD_TARGET - CARD_TIMER), target, sizeof target); /* the card's layout target (inside the block) */
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

/* game.dll + the displacement, sign-extended as the CPU extends the instruction's disp32. */
static uintptr_t table_at(uint32_t rva)
{
    return SYN_GAME_BASE + (uintptr_t)(int64_t)(int32_t)rva;
}

static void put_table(Builder* b, uint32_t rva)
{
    put64(b, table_at(rva), 0); /* kind 0 has no definition */
    for (uint32_t kind = 1; kind < TABLE_ENTRIES; kind++) put64(b, table_at(rva) + kind * 8u, syn_definition(kind));
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
    g_block = 0;
    memset(g_mod_row, 0, sizeof g_mod_row);
    memset(g_mod_tomb, 0, sizeof g_mod_tomb);

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
    if (s->table_rva != RVA_TABLE) { /* moved before the first read: a block of HellForge's shape */
        put_table(&b, s->table_rva);
        for (uint32_t kind = TABLE_ENTRIES; kind < HF_SLOTS; kind++) put64(&b, table_at(s->table_rva) + kind * 8u, 0);
        g_block = table_at(s->table_rva);
    }

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
            /* The input component is clean (input.lua:241-242) and the four direction actions idle (input.lua:187-188). */
            put32(&b, avatar + AVATAR_COMPONENT + COMPONENT_COUNT, 0);
            put32(&b, avatar + AVATAR_COMPONENT + COMPONENT_MATCHED, 0);
            put32(&b, avatar + AVATAR_COMPONENT + COMPONENT_QUEUED, 0);
            for (uint32_t a = ACTION_LEFT; a <= ACTION_DOWN; a++)
                put8(&b, AT_AVATARS + (uintptr_t)AVATARS[i] * ACTIONS_STRIDE + ACTIONS + ACTION_STRIDE * a, 0);
            /* The local one's menu is active: bit 9 and two other bits, so a reader must test the bit, not the word. */
            put32(&b, avatar + AVATAR_MENU, i == 0 ? MENU_ACTIVE_BIT | 0x5u : 0u);
        }
        put_lookup(&b, AT_PLAYERS, PLAYERS_LOOKUP, AT_LOOKUPS + 0x2000u, 32, 0xc2b2ae35u, 0, 2, CONTEXTS, PLAYERS);
        /* The scramble query's positions (input.lua:150-152): the avatars' keys to their position entries, each with
         * its 12 bytes; and the local avatar's scramble seed (input.lua:157). */
        {
            static const uint32_t POSITIONS[2] = { LOCAL_POSITION, OTHER_POSITION };
            put64(&b, SYN_GAME_BASE + RVA_POSITIONS, AT_POSITIONS);
            put_lookup(&b, AT_POSITIONS, POSITIONS_LOOKUP, AT_LOOKUPS + 0x3000u, 16, 0x27d4eb2fu, 0xffffffffu, 2, KEYS,
                       POSITIONS);
            put64(&b, AT_POSITIONS + POSITIONS_ENTRIES, AT_POSITION_ENTRIES);
            for (int i = 0; i < 2; i++) {
                float where[3] = { 10.0f * (float)i, 2.5f, -7.0f };
                put(&b, syn_position(POSITIONS[i]), where, sizeof where);
            }
            put32(&b, syn_local_avatar() + AVATAR_SEED, s->scramble_seed);
        }
        put64(&b, AT_PLAYERS + PLAYERS_PEER + PLAYERS_PEER_STRIDE * LOCAL_PLAYER, s->peer);
        put64(&b, AT_PLAYERS + PLAYERS_PEER + PLAYERS_PEER_STRIDE * OTHER_PLAYER, other_peer(s, 32));
        put64(&b, AT_SESSION + SESSION_PEER, s->peer);
    }

    /* The UI (unobstructed: its word is 0) and the controls. */
    put64(&b, SYN_GAME_BASE + RVA_UI, AT_UI);
    put32(&b, AT_UI + UI_OBSTRUCTION, 0);
    put64(&b, SYN_GAME_BASE + RVA_CONTROLS, AT_CONTROLS);
    put32(&b, AT_CONTROLS, 0);

    /* The menu latch's inputs (menu_latch.lua:9-75, input.lua:283-340): the controls' menu action (not down) and its
     * Hold trigger, the live binding map with Display Stratagem List's bucket, the local menu action's byte and trigger,
     * and the local weapon block (its owner key, slot 1 requested). */
    put8(&b, AT_CONTROLS + CONTROLS_MENU_ACTION, 0);
    put32(&b, AT_CONTROLS + CONTROLS_MENU_TRIGGER, TRIGGER_HOLD);
    put64(&b, AT_CONTROLS + BINDING_MAP, AT_BINDINGS);
    put32(&b, AT_CONTROLS + BINDING_MAP + BINDING_CAPACITY_AT, BINDING_CAPACITY);
    for (uint32_t i = 0; i < BINDING_CAPACITY; i++) {
        uintptr_t bucket = syn_binding_bucket((int)i);
        put32(&b, bucket, i == MENU_BUCKET ? MENU_KEY : i == OTHER_BUCKET ? OTHER_KEY_BINDING : FILLER_KEY + i);
        put32(&b, bucket + BUCKET_COUNT_AT, i == MENU_BUCKET ? 3u : i == OTHER_BUCKET ? 1u : 0u);
    }
    for (int r = 0; r < 3; r++) put(&b, syn_binding_record(MENU_BUCKET, r), SYN_MENU_RECORDS[r], RECORD_SIZE);
    put(&b, syn_binding_record(OTHER_BUCKET, 0), SYN_OTHER_RECORD, RECORD_SIZE);
    put8(&b, syn_local_actions() + MENU_DOWN, 0);
    put32(&b, syn_local_actions() + ACTION_TRIGGER, TRIGGER_HOLD);
    put32(&b, syn_local_weapon(), LOCAL_KEY);
    put32(&b, syn_local_weapon() + WEAPON_SLOT, START_SLOT);

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
        || syn_code_array(TABLE_ENTRIES - 1u) + 4u * SYN_CODE_MAX > AT_SETTINGS + ALTERNATE_AT
        || ALTERNATE_AT + 400u + 4u * SYN_CODE_MAX > SETTINGS_SIZE)
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
    return syn_move_table((int32_t)rva);
}

/* HellForge's StratagemBlock and StratagemMove (HF stratagems.c:372-388, 427-437): the vanilla list copied into the
 * block's first 150 slots (the other 48 zero, as VirtualAlloc gives them), then the instruction's disp32 pointed at it. */
bool syn_move_table(int32_t displacement)
{
    uint8_t table[HF_SLOTS * 8u];
    uintptr_t block = SYN_GAME_BASE + (uintptr_t)(int64_t)displacement;
    memset(table, 0, sizeof table);
    if (!g_built || syn_read(SYN_GAME_BASE + RVA_TABLE, table, TABLE_ENTRIES * 8u) != 0) return false;
    if (!syn_poke(block, table, sizeof table) || !syn_poke_u32(SYN_GAME_BASE + RVA_DISPLACEMENT, (uint32_t)displacement))
        return false;
    g_block = block;
    memset(g_mod_row, 0, sizeof g_mod_row);
    memset(g_mod_tomb, 0, sizeof g_mod_tomb);
    return true;
}

uintptr_t syn_table(void)
{
    uint32_t rva = 0;
    if (!g_built || syn_read(SYN_GAME_BASE + RVA_DISPLACEMENT, &rva, sizeof rva) != 0) return 0;
    return table_at(rva);
}

uintptr_t syn_mod_code(uint32_t kind)
{
    return SYN_LOADER_BASE + LOADER_MOD_CODES + (uintptr_t)(kind - SYN_MOD_FIRST) * LOADER_ARRAY;
}

uintptr_t syn_loader_spare(int slot)
{
    if (slot < 0 || slot >= LOADER_SPARE_COUNT) return 0;
    return SYN_LOADER_BASE + LOADER_SPARES + (uintptr_t)slot * LOADER_ARRAY;
}

bool syn_set_code(uintptr_t definition, uintptr_t array, int n, const uint8_t* code)
{
    bool ok = g_built && n >= 0 && n <= SYN_CODE_MAX && syn_poke_u64(definition + DEF_CODE, array)
        && syn_poke_u32(definition + DEF_COUNT, (uint32_t)n);
    for (int i = 0; ok && code && i < n; i++) ok = syn_poke_u32(array + (uintptr_t)i * 4u, code[i]);
    return ok;
}

/* HellForge's StratagemRow (HF stratagems.c:390-424): the row names the new type at +0, its code at +0x40 is the loader's
 * array (home->code) and +0x48 its length; the row goes into the table's slot for the type (stratagems.c:504). */
uintptr_t syn_add_mod_stratagem(uint32_t kind, int n, const uint8_t* code)
{
    uintptr_t row;
    if (!g_built || g_block == 0 || kind < SYN_MOD_FIRST || kind > SYN_MOD_LAST || n < 0 || n > SYN_CODE_MAX
        || (n > 0 && !code))
        return 0;
    row = g_block + HF_ROWS_AT + (uintptr_t)(kind - SYN_MOD_FIRST) * HF_ROW;
    if (!syn_poke_u32(row, kind) || !syn_set_code(row, syn_mod_code(kind), n, code)
        || !syn_poke_u64(g_block + (uintptr_t)kind * 8u, row))
        return 0;
    g_mod_row[kind - SYN_MOD_FIRST] = row;
    g_mod_tomb[kind - SYN_MOD_FIRST] = false;
    return row;
}

uintptr_t syn_stratagem_row(uint32_t type)
{
    if (!g_built || type < SYN_MOD_FIRST || type > SYN_MOD_LAST || g_mod_tomb[type - SYN_MOD_FIRST]) return 0;
    return g_mod_row[type - SYN_MOD_FIRST];
}

bool syn_tombstone(uint32_t kind)
{
    if (!g_built || kind < SYN_MOD_FIRST || kind > SYN_MOD_LAST || g_mod_row[kind - SYN_MOD_FIRST] == 0) return false;
    g_mod_tomb[kind - SYN_MOD_FIRST] = true;
    return true;
}

/* --- the fake input component (R46 input.lua:240-282) ---------------------------------------------------------- */

/* input.lua:263-264, "Native actions: left=1 right=2 up=3 down=4" and action = ({3,2,4,1})[direction]: the action of
 * code direction d (1 up, 2 right, 3 down, 4 left). Written out here, not taken from DBF_VAL_DIRECTION_n_ACTION. */
static const uint8_t ACTION_OF_DIRECTION[5] = { 0, 3, 2, 4, 1 };

static struct {
    int calls;
    int action[SYN_INPUT_CALLS];
    bool ignore;
    uint32_t kind;
    uint8_t code[INPUT_CODE_MAX];
    int n;
    void (*hook)(int call);
} g_input;

void syn_input_reset(void)
{
    memset(&g_input, 0, sizeof g_input);
}

void syn_input_expect(uint32_t kind, const uint8_t* code, int n)
{
    g_input.kind = kind;
    g_input.n = code && n > 0 && n <= (int)INPUT_CODE_MAX ? n : 0;
    memset(g_input.code, 0, sizeof g_input.code);
    if (g_input.n > 0) memcpy(g_input.code, code, (size_t)g_input.n);
}

void syn_input_ignore(bool ignore) { g_input.ignore = ignore; }
void syn_input_on_call(void (*hook)(int call)) { g_input.hook = hook; }
int syn_input_calls(void) { return g_input.calls; }

int syn_input_action(int call)
{
    return call >= 0 && call < g_input.calls && call < SYN_INPUT_CALLS ? g_input.action[call] : 0;
}

/* The one action byte of the local player's that is pressed (1, R46's pulse_byte(address, 1), input.lua:267) while the
 * others are released (0): 1 to 4; 0 none; -1 several, a byte that is neither 0 nor 1, or unreadable. */
static int pressed_action(void)
{
    int pressed = 0;
    for (uint32_t a = ACTION_LEFT; a <= ACTION_DOWN; a++) {
        uint8_t byte;
        if (syn_read(syn_local_actions() + ACTION_STRIDE * a, &byte, 1) != 0 || byte > ACTION_PRESSED) return -1;
        if (byte == 0) continue;
        if (pressed != 0) return -1;
        pressed = (int)a;
    }
    return pressed;
}

void syn_input_handler(uintptr_t component)
{
    int call = g_input.calls++, pressed = component == syn_local_component() ? pressed_action() : -1;
    uint32_t n = 0;
    if (call < SYN_INPUT_CALLS) g_input.action[call] = pressed;
    if (!g_input.ignore && pressed > 0 && syn_read(component + COMPONENT_COUNT, &n, sizeof n) == 0 && n < INPUT_CODE_MAX) {
        uint8_t direction = 0, seen[INPUT_CODE_MAX];
        for (uint8_t d = 1; d <= 4; d++)
            if (ACTION_OF_DIRECTION[d] == (uint8_t)pressed) direction = d;
        n++;
        syn_poke_u8(component + COMPONENT_DIRECTIONS + n, direction);
        syn_poke_u32(component + COMPONENT_COUNT, n);
        if (g_input.n == (int)n && syn_read(component + COMPONENT_DIRECTIONS + 1u, seen, n) == 0
            && memcmp(seen, g_input.code, n) == 0)
            syn_poke_u32(component + COMPONENT_MATCHED, g_input.kind);
    }
    if (g_input.hook) g_input.hook(call);
}

/* --- the fake menu calls (R46 native.lua:300-306, input.lua:319-339) ------------------------------------------- */

static struct {
    int open_calls, close_calls, request_calls, stray;
    bool open_fails_to_open, request_ignored;
    uint8_t open_result;
    uint32_t requested;
    void (*open_hook)(void);
} g_menu = { 0, 0, 0, 0, false, false, 1, 0, NULL };

void syn_menu_reset(void)
{
    memset(&g_menu, 0, sizeof g_menu);
    g_menu.open_result = 1;
}

void syn_open_answers(uint8_t result, bool opens)
{
    g_menu.open_result = result;
    g_menu.open_fails_to_open = !opens;
}

void syn_request_ignored(bool ignored) { g_menu.request_ignored = ignored; }
void syn_open_on_call(void (*hook)(void)) { g_menu.open_hook = hook; }
int syn_open_calls(void) { return g_menu.open_calls; }
int syn_close_calls(void) { return g_menu.close_calls; }
int syn_request_calls(void) { return g_menu.request_calls; }
uint32_t syn_requested_slot(void) { return g_menu.requested; }
int syn_menu_stray_calls(void) { return g_menu.stray; }

/* The menu-open byte of the panel and the menu-active bit of the local avatar, both set or both cleared. */
static void set_menu(bool open)
{
    uint32_t word = 0;
    syn_poke_u8(syn_panel() + PANEL_OPEN, open ? 1 : 0);
    syn_read(syn_local_avatar() + AVATAR_MENU, &word, sizeof word);
    syn_poke_u32(syn_local_avatar() + AVATAR_MENU, open ? word | MENU_ACTIVE_BIT : word & ~MENU_ACTIVE_BIT);
}

uint8_t syn_open_input(uintptr_t component)
{
    if (component != syn_local_component()) {
        g_menu.stray++;
        return 0;
    }
    g_menu.open_calls++;
    if (g_menu.open_result != 0 && !g_menu.open_fails_to_open) set_menu(true);
    if (g_menu.open_hook) g_menu.open_hook();
    return g_menu.open_result;
}

void syn_close_input(uintptr_t component)
{
    if (component != syn_local_component()) {
        g_menu.stray++;
        return;
    }
    g_menu.close_calls++;
    set_menu(false);
}

void syn_request_slot(uintptr_t weapon, uint32_t slot)
{
    if (weapon != syn_local_weapon()) {
        g_menu.stray++;
        return;
    }
    g_menu.request_calls++;
    g_menu.requested = slot;
    if (!g_menu.request_ignored) syn_poke_u32(weapon + WEAPON_SLOT, slot);
}

uintptr_t syn_positions(void) { return AT_POSITIONS; }
uintptr_t syn_position(uint32_t index) { return AT_POSITION_ENTRIES + (uintptr_t)index * POSITION_STRIDE + POSITION_AT; }
uint32_t syn_local_position_index(void) { return LOCAL_POSITION; }

uintptr_t syn_alternate_definition(uint32_t kind, int n, const uint8_t* code)
{
    uintptr_t info = AT_SETTINGS + ALTERNATE_AT, data = info + 400u;
    bool ok = g_built && n >= 0 && n <= SYN_CODE_MAX && (n == 0 || code) && syn_poke_u32(info, kind)
        && syn_poke_u64(info + DEF_CODE, data) && syn_poke_u32(info + DEF_COUNT, (uint32_t)n);
    for (int i = 0; ok && i < n; i++) ok = syn_poke_u32(data + (uintptr_t)i * 4u, code[i]);
    return ok ? info : 0;
}

bool syn_change_peer(uint64_t peer)
{
    if (!g_built) return false;
    g_scene.peer = peer;
    return syn_poke_u64(AT_SESSION + SESSION_PEER, peer)
        && syn_poke_u64(AT_PLAYERS + PLAYERS_PEER + PLAYERS_PEER_STRIDE * LOCAL_PLAYER, peer)
        && syn_poke_u64(AT_MISSION + (uintptr_t)g_scene.local_entry * MISSION_STRIDE, peer);
}

bool syn_registry_probe(uint32_t capacity, int position, int empty_at)
{
    const uint32_t seed = 0x9e3779b1u, empty = 0xffffffffu, hash = LOCAL_NETWORK * seed;
    uintptr_t data = AT_LOOKUPS + PROBE_AT;
    bool ok;
    if (!g_built || capacity == 0 || capacity > PROBE_MAX || (capacity & (capacity - 1u)) != 0
        || position >= (int)capacity || empty_at >= (int)capacity || (position >= 0 && position == empty_at))
        return false;
    ok = syn_poke_u64(AT_REGISTRY + REGISTRY_LOOKUP, data)
        && syn_poke_u32(AT_REGISTRY + REGISTRY_LOOKUP + LOOKUP_CAPACITY, capacity)
        && syn_poke_u32(AT_REGISTRY + REGISTRY_LOOKUP + LOOKUP_EMPTY, empty)
        && syn_poke_u32(AT_REGISTRY + REGISTRY_LOOKUP + LOOKUP_SEED, seed);
    for (uint32_t probe = 0; ok && probe < capacity; probe++) {
        uintptr_t slot = data + (uintptr_t)((hash + probe) % capacity) * SLOT_SIZE;
        uint32_t key = (int)probe == position ? LOCAL_NETWORK : (int)probe == empty_at ? empty : PROBE_FILLER + probe;
        ok = syn_poke_u32(slot, key) && syn_poke_u32(slot + 4u, (int)probe == position ? LOCAL_REGISTRY_INDEX : 0u);
    }
    return ok;
}
