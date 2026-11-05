/* Tests for src/codes.c: the definition table (vanilla, or HellForge's moved copy above or below game.dll), HellForge mod
 * stratagems, code arrays in the settings block or in hellforge_modloader.dll's image, the double read, shared arrays
 * and the scramble remap; and game_read's use of them. They run against the synthetic 25480438 image of
 * tests/synthetic.c with the generated witness table (every feature admitted; a test refuses one by changing a byte of
 * a witness), its fake HellForge block, loader image and stratagem_row, and a fake native port whose scramble query
 * answers what the test says. The memory port wraps the synthetic one so a test can have the game change a value right
 * after DBF's first read of it. The numbers R46 and HellForge use are spelled out here, not taken from the generated
 * header, so the tests check the address table too. codes.c, game.c and native.c keep state in statics: every test
 * starts with start(). */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "codes.h"
#include "game.h"
#include "memory.h"
#include "native.h"
#include "synthetic.h"
#include "test.h"

#define GRACE_OVER 30000u
#define VANILLA_TABLE 0x37cb600u   /* R46 native.lua:52 */
#define DISPLACEMENT 0x66d550u     /* R46 native.lua:51 */
#define RVA_EFFECTS 0x33264b0u     /* R46 input.lua:153 */
#define RVA_POSITIONS 0x3326508u   /* R46 input.lua:150 */
#define DEF_CODE 0x40u             /* R46 input.lua:165 */
#define DEF_COUNT 0x48u            /* R46 input.lua:165 */
#define AVATAR_SEED 0x11b8u        /* R46 input.lua:157 */
#define GAME_MODE 0xac21cu         /* R46 native.lua:82: the game state's mode, 4 in gameplay */
#define AT_EFFECTS ((uintptr_t)0x2d000000000ull)
#define AT_ELSEWHERE ((uintptr_t)0x30000001000ull) /* neither the settings block nor the loader image */
#define ABOVE ((int32_t)(SYN_IMAGE_SIZE + 0x10000u))
#define BELOW ((int32_t)-0x10000000)
#define TABLE_BYTES (198u * 8u)    /* HellForge's 150 + 48 slots (HF stratagems.c:42-44) */

/* --- the ports ------------------------------------------------------------------------------------------------- */

/* The memory port: synthetic reads, and one watched value that the game changes right after DBF first reads it. */
static uintptr_t g_watch;     /* 0: nothing watched */
static size_t g_watch_size;   /* 4 or 8 */
static uint64_t g_watch_value;
static int g_watch_reads;

static int read_watching(uintptr_t address, void* out, size_t size)
{
    int result = syn_read(address, out, size);
    if (g_watch != 0 && result == 0 && address <= g_watch && g_watch + g_watch_size <= address + size
        && ++g_watch_reads == 1)
        syn_poke(g_watch, &g_watch_value, g_watch_size);
    return result;
}

static const MemPort MEM = { read_watching, syn_write };

static void watch(uintptr_t address, size_t size, uint64_t value)
{
    g_watch = address;
    g_watch_size = size;
    g_watch_value = value;
    g_watch_reads = 0;
}

/* The native port: the scramble query only, answering g_answer (or writing nothing). */
static uint32_t g_answer;
static bool g_answers;
static int g_queries;
static uint32_t g_query_key, g_query_kind;

static uintptr_t fake_scramble_query(uintptr_t effects, uint32_t* out, uint32_t key, uint32_t kind, uintptr_t a5, uintptr_t a6)
{
    g_queries++;
    g_query_key = key;
    g_query_kind = kind;
    if (g_answers) *out = g_answer;
    return 0;
}

static const NativePort NATIVE = { NULL, NULL, NULL, NULL, NULL, fake_scramble_query, NULL };

/* The codes port's log. */
#define MAX_LINES 8
static char g_lines[MAX_LINES][200];
static int g_line_count;

static void fake_log(const char* line)
{
    if (g_line_count < MAX_LINES) snprintf(g_lines[g_line_count], sizeof g_lines[0], "%s", line);
    g_line_count++;
}

static const CodePort CODES = { syn_stratagem_row, SYN_LOADER_BASE, SYN_LOADER_SIZE, fake_log };

/* --- helpers --------------------------------------------------------------------------------------------------- */

static GameView g_view;

static bool start_with(const SynScene* s, const CodePort* port)
{
    bool built = syn_build(s);
    mem_init(&MEM);
    adm_init(syn_adm_port(), 0);
    built = built && syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, AT_EFFECTS);
    native_init(&NATIVE);
    native_set_base(SYN_GAME_BASE);
    codes_init(port);
    game_init(SYN_GAME_BASE, SYN_IMAGE_SIZE);
    g_watch = 0;
    g_answer = 0xffffffffu;
    g_answers = true;
    g_queries = 0;
    g_query_key = g_query_kind = 0;
    g_line_count = 0;
    return built;
}

static bool start(SynScene* s)
{
    syn_default(s);
    return start_with(s, &CODES);
}

static const DbfWitness* witness(const char* name)
{
    for (int i = 0; i < dbf_witness_count; i++)
        if (strcmp(dbf_witnesses[i].name, name) == 0) return &dbf_witnesses[i];
    return NULL;
}

/* Changes a byte of the witness and lets the grace run out: its features are refused. */
static void refuse_witness(const char* name)
{
    const DbfWitness* w = witness(name);
    if (!w) return;
    syn_poke_u8(SYN_GAME_BASE + w->rva, (uint8_t)(w->bytes[0] ^ 0x55u));
    adm_init(syn_adm_port(), 0);
    adm_tick(GRACE_OVER);
}

static char g_reason[96];

static bool table(uint32_t want_max)
{
    uint32_t max = 0xdead;
    bool ok = codes_table(&max, g_reason, sizeof g_reason);
    if (ok && max == want_max && g_reason[0] == '\0') return true;
    printf("  codes_table: %d, max %u, reason \"%s\"\n", ok, (unsigned)max, g_reason);
    return false;
}

static bool table_refused(const char* reason)
{
    uint32_t max = 0xdead;
    bool ok = codes_table(&max, g_reason, sizeof g_reason);
    if (!ok && max == 0 && strcmp(g_reason, reason) == 0 && codes_table_at() == 0) return true;
    printf("  codes_table: %d, max %u, reason \"%s\", expected \"%s\"\n", ok, (unsigned)max, g_reason, reason);
    return false;
}

static DbfCode g_code;

/* codes_read(kind) gives `n` directions `code`, from kind `used`, scrambled or not. */
static bool reads(uint32_t kind, const GameLocal* local, const uint8_t* code, int n, uint32_t used, bool scrambled)
{
    bool ok;
    memset(&g_code, 0xa5, sizeof g_code);
    ok = codes_read(kind, local, &g_code, g_reason, sizeof g_reason);
    if (ok && g_reason[0] == '\0' && g_code.len == n && memcmp(g_code.dir, code, (size_t)n) == 0
        && g_code.kind_used == used && g_code.scrambled == scrambled)
        return true;
    printf("  codes_read(%u): %d, reason \"%s\", len %u, kind_used %u, scrambled %d\n", (unsigned)kind, ok, g_reason,
           (unsigned)g_code.len, (unsigned)g_code.kind_used, g_code.scrambled);
    return false;
}

/* codes_read(kind) refuses with `reason` and leaves *out zero. */
static bool refused(uint32_t kind, const GameLocal* local, const char* reason)
{
    static const DbfCode ZERO;
    bool ok;
    memset(&g_code, 0xa5, sizeof g_code);
    ok = codes_read(kind, local, &g_code, g_reason, sizeof g_reason);
    if (!ok && strcmp(g_reason, reason) == 0 && memcmp(&g_code, &ZERO, sizeof ZERO) == 0) return true;
    printf("  codes_read(%u): %d, reason \"%s\", expected \"%s\"\n", (unsigned)kind, ok, g_reason, reason);
    return false;
}

/* The made-up code syn_build gives a vanilla kind that is not in the scene. */
static void made_up(uint32_t kind, uint8_t out[3])
{
    out[0] = (uint8_t)(1u + kind % 4u);
    out[1] = (uint8_t)(1u + (kind + 1u) % 4u);
    out[2] = (uint8_t)(1u + (kind + 2u) % 4u);
}

static bool reads_made_up(uint32_t kind, const GameLocal* local, uint32_t used, bool scrambled)
{
    uint8_t code[3];
    made_up(used, code);
    return reads(kind, local, code, 3, used, scrambled);
}

static const SynStratagem* scene_kind(const SynScene* s, uint32_t kind)
{
    for (int i = 0; i < s->stratagem_count; i++)
        if (s->stratagems[i].kind == kind) return &s->stratagems[i];
    return NULL;
}

/* The local player's code-entry context, as game_read finds it; what that read asked and logged is forgotten. */
static GameLocal local_context(void)
{
    GameView v;
    game_read(&v);
    g_queries = 0;
    g_query_key = g_query_kind = 0;
    g_line_count = 0;
    return v.local;
}

static const GameView* read_view(void)
{
    memset(&g_view, 0xa5, sizeof g_view);
    game_read(&g_view);
    return &g_view;
}

static bool reason_is(const GameView* v, const char* text)
{
    if (strcmp(v->reason, text) == 0) return true;
    printf("  reason was \"%s\", expected \"%s\"\n", v->reason, text);
    return false;
}

static bool row_code_is(const DbfRow* r, uint32_t kind, const uint8_t* code, int n)
{
    if (r->kind == kind && r->code_len == n && memcmp(r->code, code, (size_t)n) == 0) return true;
    printf("  row kind %u, code_len %u (expected kind %u, %d directions)\n", (unsigned)r->kind, (unsigned)r->code_len,
           (unsigned)kind, n);
    return false;
}

static bool line_is(int index, const char* text)
{
    if (index < g_line_count && index < MAX_LINES && strcmp(g_lines[index], text) == 0) return true;
    printf("  log line %d was \"%s\", expected \"%s\"\n", index,
           index < g_line_count && index < MAX_LINES ? g_lines[index] : "(none)", text);
    return false;
}

static const uint8_t MOD_CODE[4] = { 3, 3, 1, 2 };
static const uint8_t MOD_CODE_B[5] = { 4, 4, 4, 1, 2 };
static const uint8_t LUA_CODE[9] = { 1, 2, 3, 4, 4, 3, 2, 1, 1 };

/* --- the definition table -------------------------------------------------------------------------------------- */

static void test_vanilla_table(void)
{
    SynScene s;
    bool all = true;
    CHECK(start(&s), "the default scene builds");
    CHECK(table(149) && codes_table_at() == SYN_GAME_BASE + VANILLA_TABLE,
          "vanilla table at 0x37cb600: accepted, kinds 1..149");
    for (uint32_t kind = 1; kind <= 149; kind++) {
        const SynStratagem* st = scene_kind(&s, kind);
        bool ok = st ? reads(kind, NULL, st->code, st->code_len, kind, false) : reads_made_up(kind, NULL, kind, false);
        if (!ok) all = false;
    }
    CHECK(all, "every kind 1..149 reads its own code");
    CHECK(refused(150, NULL, "unknown stratagem kind"), "kind 150 with the vanilla table: refused");
    CHECK(refused(0, NULL, "unknown stratagem kind"), "kind 0: refused");
    CHECK(!codes_read(4, NULL, NULL, g_reason, sizeof g_reason), "a NULL output: false");
    CHECK(syn_unmap(SYN_GAME_BASE + DISPLACEMENT) && table_refused("definition table unreadable"),
          "the displacement cannot be read: \"definition table unreadable\"");
    CHECK(refused(4, NULL, "no definition table"), "after a refused table, codes_read refuses");
}

static void test_moved_table(void)
{
    SynScene s;
    uint8_t made[3];
    start(&s);
    CHECK(syn_move_table(ABOVE) && table(197) && codes_table_at() == SYN_GAME_BASE + SYN_IMAGE_SIZE + 0x10000u,
          "HellForge's block above the image (image_size + 0x10000): accepted, kinds 1..197");
    /* The vanilla table loses kind 4: a read through the moved copy still finds it. */
    syn_poke_u64(SYN_GAME_BASE + VANILLA_TABLE + 4u * 8u, 0);
    CHECK(reads(4, NULL, s.stratagems[1].code, s.stratagems[1].code_len, 4, false),
          "codes come through the moved copy, not the vanilla table");
    CHECK(refused(198, NULL, "unknown stratagem kind"), "kind 198: past HellForge's 197");

    start(&s);
    CHECK(syn_move_table(BELOW) && table(197) && codes_table_at() == SYN_GAME_BASE - 0x10000000u,
          "HellForge's block below the image (displacement -0x10000000, sign-extended): accepted");
    made_up(7, made);
    CHECK(reads(7, NULL, made, 3, 7, false), "codes come through the block below the image");

    struct { int32_t displacement; bool ok; const char* text; } cases[] = {
        { (int32_t)SYN_IMAGE_SIZE, true, "a block starting right at the image's end" },
        { -(int32_t)TABLE_BYTES, true, "a block ending right at game.dll's base" },
        { 0x7ffffff8, true, "a block 2^31 - 8 above game.dll" },
        { -0x7ffffff8, true, "a block 2^31 - 8 below game.dll" },
        { -(int32_t)TABLE_BYTES + 8, false, "a block whose last slot overlaps the image's start" },
        { (int32_t)SYN_IMAGE_SIZE - 8, false, "a block starting inside the image" },
        { 0x1000, false, "a displacement inside the image" },
        { (int32_t)(VANILLA_TABLE + 8u), false, "0x37cb608: inside the image, not the vanilla table" },
        { ABOVE + 4, false, "a block that is not 8-aligned" },
        { INT32_MIN, false, "a block exactly 2^31 below game.dll: not within 2 GiB" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        char text[160];
        start(&s);
        if (cases[i].ok) {
            snprintf(text, sizeof text, "%s: accepted, kinds 1..197", cases[i].text);
            CHECK(syn_move_table(cases[i].displacement) && table(197)
                      && codes_table_at() == SYN_GAME_BASE + (uintptr_t)(int64_t)cases[i].displacement,
                  text);
        } else {
            snprintf(text, sizeof text, "%s: \"definition table unrecognised\"", cases[i].text);
            CHECK(syn_poke_u32(SYN_GAME_BASE + DISPLACEMENT, (uint32_t)cases[i].displacement)
                      && table_refused("definition table unrecognised"),
                  text);
        }
    }

    start(&s);
    syn_poke_u32(SYN_GAME_BASE + DISPLACEMENT, (uint32_t)(SYN_IMAGE_SIZE + 0x200000u));
    CHECK(table_refused("definition table unreadable"), "an acceptable place with nothing there: unreadable");
    /* Slots 0..149 on one page, 150..197 on the next. */
    CHECK(syn_move_table(ABOVE + 0x1000 - 150 * 8) && table(197), "moved again, slot 150 starting a page: accepted");
    CHECK(syn_unmap(SYN_GAME_BASE + (uintptr_t)(ABOVE + 0x1000)) && table_refused("definition table unreadable"),
          "slots 150..197 cannot be read: unreadable (slots 1..197 must be)");
    CHECK(refused(4, NULL, "no definition table"), "and codes_read refuses");
}

/* --- HellForge mod stratagems ---------------------------------------------------------------------------------- */

static void test_mod_stratagems(void)
{
    SynScene s;
    CodePort port;
    uintptr_t row;
    start(&s);
    CHECK(syn_move_table(ABOVE), "table moved");
    row = syn_add_mod_stratagem(151, 4, MOD_CODE);
    CHECK(row != 0 && syn_stratagem_row(151) == row, "mod stratagem 151 added, its row in HellForge's block");
    CHECK(table(197) && reads(151, NULL, MOD_CODE, 4, 151, false),
          "kind 151: its definition is stratagem_row(151), its code in the loader image");
    CHECK(refused(152, NULL, "mod stratagem not loaded"), "kind 152, not added (stratagem_row 0): no code");

    start(&s);
    syn_move_table(ABOVE);
    syn_add_mod_stratagem(150, 3, MOD_CODE);
    syn_add_mod_stratagem(151, 5, MOD_CODE_B);
    CHECK(syn_tombstone(150) && syn_stratagem_row(150) == 0, "kind 150 tombstoned: stratagem_row(150) is 0");
    CHECK(table(197) && refused(150, NULL, "mod stratagem not loaded"), "tombstoned 150: no code, though its slot stays");
    CHECK(reads(151, NULL, MOD_CODE_B, 5, 151, false), "kind 151 is still read after the tombstoned 150");
    CHECK(refused(197, NULL, "mod stratagem not loaded"), "kind 197, never added: no code");

    start(&s);
    syn_move_table(BELOW);
    row = syn_add_mod_stratagem(160, 2, MOD_CODE);
    CHECK(row != 0 && table(197) && reads(160, NULL, MOD_CODE, 2, 160, false), "a mod stratagem in a block below the image");
    syn_poke_u32(row, 161);
    CHECK(refused(160, NULL, "invalid definition"), "its row naming another kind: invalid definition");
    syn_poke_u32(row, 160);
    syn_poke_u64(syn_table() + 160u * 8u, row + 8u);
    syn_poke_u32(row + 8u, 160);
    CHECK(refused(160, NULL, "invalid definition"), "the table's slot not stratagem_row(160): invalid definition");
    syn_poke_u64(syn_table() + 160u * 8u, row);
    CHECK(reads(160, NULL, MOD_CODE, 2, 160, false), "the slot back on the row: read again");

    port = CODES;
    port.stratagem_row = NULL;
    start_with(&s, &port);
    syn_move_table(ABOVE);
    syn_add_mod_stratagem(151, 4, MOD_CODE);
    CHECK(table(197) && refused(151, NULL, "mod stratagems unavailable"), "no stratagem_row in the port: kinds 150+ refused");
    CHECK(reads_made_up(7, NULL, 7, false), "  vanilla kinds still read");

    port = CODES;
    port.loader_base = 0;
    port.loader_size = 0;
    start_with(&s, &port);
    syn_move_table(ABOVE);
    syn_add_mod_stratagem(151, 4, MOD_CODE);
    CHECK(table(197) && refused(151, NULL, "code outside the game and HellForge"),
          "no loader image in the port: its arrays are refused");
}

/* --- where a code array may be --------------------------------------------------------------------------------- */

static void test_array_places(void)
{
    SynScene s;
    CodePort quiet;
    uintptr_t row;
    start(&s);
    table(149);
    CHECK(syn_set_code(syn_definition(7), syn_loader_spare(0), 9, LUA_CODE) && reads(7, NULL, LUA_CODE, 9, 7, false),
          "a vanilla kind recoded by a Lua mod into the loader image (9 directions): read");
    CHECK(syn_set_code(syn_definition(7), syn_loader_spare(1), 10, NULL) && refused(7, NULL, "invalid code array"),
          "10 directions in the loader image (HellForge allows 9): invalid code array");
    CHECK(syn_set_code(syn_definition(7), SYN_LOADER_BASE + SYN_LOADER_SIZE - 8u, 3, NULL)
              && refused(7, NULL, "code outside the game and HellForge"),
          "an array running past the loader image's end: outside");
    CHECK(line_is(0, "kind 7: code outside the game and HellForge (array 0x7ffb1237fff8, 3 directions)") && g_line_count == 1,
          "  logged once, naming the kind and the array");
    CHECK(refused(7, NULL, "code outside the game and HellForge") && g_line_count == 1, "  the same kind again: no new line");
    CHECK(syn_set_code(syn_definition(9), AT_ELSEWHERE, 4, MOD_CODE) && refused(9, NULL, "code outside the game and HellForge"),
          "an array in neither the settings block nor the loader image: outside");
    CHECK(g_line_count == 2 && line_is(1, "kind 9: code outside the game and HellForge (array 0x30000001000, 4 directions)"),
          "  another kind: its own line");
    CHECK(syn_set_code(syn_definition(9), SYN_LOADER_BASE - 4u, 2, NULL) && refused(9, NULL, "code outside the game and HellForge"),
          "an array starting 4 bytes below the loader image: outside");
    codes_init(&CODES);
    table(149);
    CHECK(refused(7, NULL, "code outside the game and HellForge") && g_line_count == 3, "a new session (codes_init) logs again");
    quiet = CODES;
    quiet.log = NULL;
    codes_init(&quiet);
    table(149);
    CHECK(refused(9, NULL, "code outside the game and HellForge") && g_line_count == 3, "a port without log: nothing logged");

    start(&s);
    table(149);
    CHECK(syn_set_code(syn_definition(7), syn_loader_spare(2) + 2u, 3, NULL) && refused(7, NULL, "invalid code array"),
          "an array pointer 2 mod 4: invalid code array");
    CHECK(syn_set_code(syn_definition(7), syn_loader_spare(2) + 4u, 3, MOD_CODE) && reads(7, NULL, MOD_CODE, 3, 7, false),
          "an array pointer 4 mod 8 in the loader image: read");
    CHECK(syn_set_code(syn_definition(7), syn_loader_spare(3), 0, NULL) && refused(7, NULL, "invalid code array"),
          "0 directions: invalid code array");
    CHECK(syn_set_code(syn_definition(7), SYN_LOADER_BASE + 0x20000u, 3, NULL) && refused(7, NULL, "code array unreadable"),
          "an array in the loader image that cannot be read: unreadable");
    CHECK(syn_set_code(syn_definition(7), syn_loader_spare(4), 3, (const uint8_t[]){ 1, 5, 2 })
              && refused(7, NULL, "invalid direction"),
          "a direction of 5 in a loader-image array: invalid direction");

    start(&s);
    syn_move_table(ABOVE);
    row = syn_add_mod_stratagem(151, 9, LUA_CODE);
    CHECK(row != 0 && table(197) && reads(151, NULL, LUA_CODE, 9, 151, false), "a mod stratagem with 9 directions: read");
    CHECK(syn_set_code(row, syn_mod_code(151), 10, NULL) && refused(151, NULL, "invalid code array"),
          "a mod stratagem with 10 directions in the loader image: invalid code array");
    CHECK(syn_set_code(row, syn_code_array(4), 5, NULL) && reads(151, NULL, s.stratagems[1].code, 5, 151, false),
          "a mod stratagem keeping its base's code (in the settings block): read");
}

/* --- the double read ------------------------------------------------------------------------------------------- */

static void test_double_read(void)
{
    SynScene s;
    uintptr_t row;
    start(&s);
    table(149);
    watch(syn_code_array(63) + 2u * 4u, 4, 2); /* the third direction, 3 -> 2, after the first read */
    CHECK(refused(63, NULL, "code changed while reading"), "a direction changed between the two reads: refused");
    CHECK(g_watch_reads == 2, "  both reads saw the array");
    g_watch = 0;
    CHECK(reads(63, NULL, (const uint8_t[]){ 3, 4, 2, 1, 4 }, 5, 63, false), "the next read takes the new code");

    start(&s);
    table(149);
    watch(syn_definition(118) + DEF_COUNT, 4, 2);
    CHECK(refused(118, NULL, "code changed while reading"), "the count changed between the two reads: refused");
    start(&s);
    table(149);
    watch(syn_definition(118) + DEF_CODE, 8, syn_code_array(117));
    CHECK(refused(118, NULL, "code changed while reading"), "the pointer changed between the two reads: refused");

    start(&s);
    syn_move_table(ABOVE);
    row = syn_add_mod_stratagem(151, 4, MOD_CODE);
    table(197);
    watch(syn_mod_code(151), 4, 4);
    CHECK(row != 0 && refused(151, NULL, "code changed while reading"),
          "a mod stratagem's loader-image direction changed between the reads: refused");
}

/* --- shared arrays (Review Focus 5) ---------------------------------------------------------------------------- */

static void test_shared_arrays(void)
{
    SynScene s;
    const GameView* v;
    uintptr_t row152;
    uint8_t made[3];
    start(&s);
    syn_move_table(ABOVE);
    syn_add_mod_stratagem(151, 4, MOD_CODE);
    row152 = syn_add_mod_stratagem(152, 5, MOD_CODE_B);
    CHECK(table(197) && reads(151, NULL, MOD_CODE, 4, 151, false) && reads(152, NULL, MOD_CODE_B, 5, 152, false)
              && !codes_shared(151) && !codes_shared(152),
          "two mod stratagems with arrays of their own: both read");
    CHECK(reads(151, NULL, MOD_CODE, 4, 151, false), "a kind read twice in one pass is not shared with itself");
    /* HellForge's restore bug (HF lua_bridge.c:383): 152's row ends up on 151's array. */
    CHECK(syn_set_code(row152, syn_mod_code(151), 4, NULL), "kind 152 pointed at kind 151's array");
    CHECK(table(197) && reads(151, NULL, MOD_CODE, 4, 151, false), "a new pass: 151, read first, has its code");
    CHECK(refused(152, NULL, "shared code array"), "152 on the same loader array: refused");
    CHECK(refused(151, NULL, "shared code array"), "and 151 is refused for the rest of the pass");
    CHECK(codes_shared(151) && codes_shared(152) && !codes_shared(4), "codes_shared names both kinds, no other");
    CHECK(table(197) && !codes_shared(151) && reads(152, NULL, MOD_CODE, 4, 152, false) && refused(151, NULL, "shared code array"),
          "the next pass starts afresh: whichever kind comes second finds the share");

    start(&s);
    table(149);
    syn_set_code(syn_definition(7), syn_loader_spare(5), 3, MOD_CODE);
    syn_set_code(syn_definition(9), syn_loader_spare(5), 3, NULL);
    CHECK(reads(7, NULL, MOD_CODE, 3, 7, false) && refused(9, NULL, "shared code array") && refused(7, NULL, "shared code array"),
          "two vanilla kinds a Lua mod left on one loader array: both refused");
    syn_set_code(syn_definition(7), syn_code_array(7), 3, NULL);
    syn_set_code(syn_definition(9), syn_code_array(7), 3, NULL);
    made_up(7, made);
    CHECK(table(149) && reads(7, NULL, made, 3, 7, false) && reads(9, NULL, made, 3, 9, false),
          "two kinds on one settings-block array are not HellForge's: both read");

    /* game_read: both rows lose their code, whichever row comes first. */
    syn_default(&s);
    s.stratagems[0].kind = 151;
    s.stratagems[2].kind = 152;
    s.table_rva = (uint32_t)ABOVE;
    start_with(&s, &CODES);
    syn_add_mod_stratagem(151, 4, MOD_CODE);
    row152 = syn_add_mod_stratagem(152, 5, MOD_CODE_B);
    v = read_view();
    CHECK(v->row_count == 4 && row_code_is(&v->rows[0], 151, MOD_CODE, 4) && row_code_is(&v->rows[2], 152, MOD_CODE_B, 5)
              && reason_is(v, ""),
          "game_read: rows of mod kinds 151 and 152 with their codes");
    syn_set_code(row152, syn_mod_code(151), 4, NULL);
    v = read_view();
    CHECK(v->row_count == 4 && v->rows[0].kind == 151 && v->rows[0].code_len == 0 && v->rows[2].kind == 152
              && v->rows[2].code_len == 0 && reason_is(v, "shared code array"),
          "game_read: 152 on 151's array: neither row has a code, \"shared code array\"");
    CHECK(row_code_is(&v->rows[1], 4, s.stratagems[1].code, s.stratagems[1].code_len)
              && row_code_is(&v->rows[3], 63, s.stratagems[3].code, s.stratagems[3].code_len),
          "  the vanilla rows keep theirs");
}

/* --- scramble -------------------------------------------------------------------------------------------------- */

static void test_scramble(void)
{
    SynScene s;
    GameLocal local;
    const GameView* v;
    uint8_t made[3];
    start(&s);
    local = local_context();
    CHECK(local.key == syn_local_key() && local.avatar == syn_local_avatar(), "the local context is the synthetic player's");
    table(149);
    g_answer = 0xffffffffu;
    CHECK(reads(118, &local, s.stratagems[0].code, 3, 118, false) && g_queries == 1 && g_query_key == syn_local_key()
              && g_query_kind == 118 && codes_scramble_asked(),
          "the query answers 0xffffffff: the kind's own code; it was asked with the local key and the kind");

    g_answer = 3;
    syn_poke_u32(syn_local_avatar() + AVATAR_SEED, 0xfffffff0u);
    CHECK(reads_made_up(118, &local, 103, true), "scrambled, seed 0xfffffff0: kind 118 -> ((118 + seed) mod 2^32) mod 149 + 1 = 103");
    syn_poke_u32(syn_local_avatar() + AVATAR_SEED, 200);
    CHECK(reads_made_up(4, &local, 56, true), "seed 200: kind 4 -> 204 mod 149 + 1 = 56");
    syn_poke_u32(syn_local_avatar() + AVATAR_SEED, 0);
    CHECK(reads_made_up(149, &local, 1, true), "seed 0: kind 149 -> 149 mod 149 + 1 = 1");
    syn_set_code(syn_definition(56), AT_ELSEWHERE, 3, NULL);
    syn_poke_u32(syn_local_avatar() + AVATAR_SEED, 200);
    CHECK(refused(4, &local, "code outside the game and HellForge"), "the remapped kind's code is read by the same rules");
    CHECK(g_line_count == 1 && line_is(0, "kind 56: code outside the game and HellForge (array 0x30000001000, 3 directions)"),
          "  and logged under the remapped kind");

    start(&s);
    local = local_context();
    table(149);
    CHECK(reads(118, NULL, s.stratagems[0].code, 3, 118, false) && g_queries == 0 && !codes_scramble_asked(),
          "no local context: no query, the kind's own code");
    {
        GameLocal far = local;
        far.avatar = (uintptr_t)0x31000000000ull; /* a context whose avatar cannot be read */
        g_answer = 3;
        CHECK(refused(118, &far, "scramble seed unreadable"), "scrambled with the seed unreadable: refused");
    }

    start(&s);
    local = local_context();
    syn_poke_u64(SYN_GAME_BASE + RVA_POSITIONS, 0);
    table(149);
    CHECK(refused(118, &local, "scramble position unavailable") && g_queries == 0,
          "no positions object: refused before the query is asked (R46 input.lua:150-152)");
    start(&s);
    local = local_context();
    syn_unmap(syn_position(syn_local_position_index()));
    table(149);
    CHECK(refused(118, &local, "scramble position unavailable") && g_queries == 0, "the position's 12 bytes unreadable: refused");
    start(&s);
    local = local_context();
    local.key = 0x777u;
    table(149);
    CHECK(refused(118, &local, "scramble position unavailable") && g_queries == 0, "a key not in the positions: refused");

    start(&s);
    local = local_context();
    syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, 0);
    g_answer = 3;
    table(149);
    CHECK(reads(118, &local, s.stratagems[0].code, 3, 118, false) && g_queries == 0 && !codes_scramble_asked(),
          "the query cannot run (no effects pointer): the kind's own code, not asked");

    start(&s);
    local = local_context();
    refuse_witness("scramble_query");
    g_answer = 3;
    table(149);
    CHECK(reads(118, &local, s.stratagems[0].code, 3, 118, false) && g_queries == 0 && !codes_scramble_asked(),
          "SCRAMBLE refused: no query, the kind's own code");
    v = read_view();
    CHECK(v->local_ok && !v->scramble_known && v->row_count == 4 && reason_is(v, "")
              && row_code_is(&v->rows[0], 118, s.stratagems[0].code, 3),
          "SCRAMBLE refused: game_read serves the codes, scramble_known false");
    syn_poke_u64(SYN_GAME_BASE + RVA_POSITIONS, 0);
    table(149);
    CHECK(reads(118, &local, s.stratagems[0].code, 3, 118, false), "SCRAMBLE refused: the positions are not needed either");

    /* HellForge moves the table; the native scramble still selects one of its first 149 kinds. */
    start(&s);
    local = local_context();
    syn_move_table(ABOVE);
    syn_add_mod_stratagem(151, 4, MOD_CODE);
    table(197);
    g_answer = 0xffffffffu;
    CHECK(reads(118, &local, s.stratagems[0].code, 3, 118, false) && reads(151, &local, MOD_CODE, 4, 151, false)
              && g_query_kind == 151,
          "moved table, no scramble effect: own codes, a mod kind asked about too");
    g_answer = 3;
    syn_poke_u32(syn_local_avatar() + AVATAR_SEED, 32);
    CHECK(reads_made_up(118, &local, 2, true), "moved table: a vanilla kind wraps at 149");
    syn_poke_u32(syn_local_avatar() + AVATAR_SEED, 0);
    CHECK(reads_made_up(151, &local, 3, true) && g_query_kind == 151,
          "moved table: query the registered mod kind, read its scrambled vanilla slot");
    syn_poke_u32(syn_local_avatar() + AVATAR_SEED, 0xffffffffu);
    /* Make slot 2 differ between the moved and original tables to catch a stale vanilla-table lookup. */
    uintptr_t moved_target = syn_definition(34);
    CHECK(syn_poke_u64(syn_table() + 2u * 8u, moved_target) && syn_poke_u32(moved_target, 2)
              && syn_set_code(moved_target, syn_loader_spare(0), 4, MOD_CODE), "set a moved-table target override");
    CHECK(reads(151, &local, MOD_CODE, 4, 2, true),
          "moved table: wrapped addition precedes modulo; read the current loader override on the target");
    CHECK(refused(152, &local, "mod stratagem not loaded"), "scrambling cannot admit an unregistered source");
    syn_set_code(moved_target, AT_ELSEWHERE, 4, NULL);
    CHECK(refused(151, &local, "code outside the game and HellForge"), "validate the remapped target array");

    /* game_read follows the scramble. */
    syn_default(&s);
    s.scramble_seed = 1;
    start_with(&s, &CODES);
    g_answer = 3;
    v = read_view();
    made_up(120, made);
    CHECK(v->scramble_known && reason_is(v, "") && v->row_count == 4 && row_code_is(&v->rows[0], 118, made, 3),
          "game_read, scrambled (seed 1): row 118 shows kind 120's code, scramble_known true");
    made_up(65, made);
    CHECK(row_code_is(&v->rows[3], 63, made, 3), "  and row 63 kind 65's");
    g_answer = 0xffffffffu;
    v = read_view();
    CHECK(v->scramble_known && row_code_is(&v->rows[0], 118, s.stratagems[0].code, 3),
          "game_read, no scramble effect: own codes, scramble_known true (the query ran)");
    syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, 0);
    v = read_view();
    CHECK(!v->scramble_known && row_code_is(&v->rows[0], 118, s.stratagems[0].code, 3),
          "game_read, the query cannot run: own codes, scramble_known false");
}

/* game_read forgets the codes pass first thing, before any early return: a codes_read later in the tick (code entry's)
 * never works against an earlier tick's table, claims or scramble flag (Plan 2, Task 6's review). */
static void test_stale_pass_forgotten(void)
{
    SynScene s;
    const GameView* v;
    start(&s);
    v = read_view();
    CHECK(reason_is(v, "") && v->table_rva == VANILLA_TABLE && codes_scramble_asked()
              && reads(118, NULL, s.stratagems[0].code, 3, 118, false),
          "after a full game_read the pass serves codes");
    syn_poke_u32(syn_game_state() + GAME_MODE, 0);
    v = read_view();
    CHECK(reason_is(v, "not in gameplay") && !codes_scramble_asked() && codes_table_at() == 0,
          "a game_read that stops at the game state: the pass is forgotten");
    CHECK(refused(118, NULL, "no definition table"), "  and codes_read refuses: the earlier tick's table is not used");

    syn_poke_u32(syn_game_state() + GAME_MODE, 4);
    v = read_view();
    CHECK(reason_is(v, "") && reads(118, NULL, s.stratagems[0].code, 3, 118, false), "back in gameplay: codes again");
    game_read(NULL);
    CHECK(refused(118, NULL, "no definition table") && codes_table_at() == 0, "game_read(NULL) forgets the pass too");

    v = read_view();
    CHECK(reads(118, NULL, s.stratagems[0].code, 3, 118, false), "a full read again: codes");
    refuse_witness("hud_root");
    v = read_view();
    CHECK(!v->in_gameplay && refused(118, NULL, "no definition table"),
          "a game_read refused by admission (Selection state): the pass is forgotten");
}

/* --- admission and game_read ----------------------------------------------------------------------------------- */

static void test_stratagems_refused(void)
{
    SynScene s;
    char want[96];
    start(&s);
    refuse_witness("wheel_label_definition");
    snprintf(want, sizeof want, "%s: witness wheel_label_definition differs", adm_feature_name(FEAT_STRATAGEMS));
    CHECK(table_refused(want), "Stratagems refused: codes_table refuses with admission's reason");
    CHECK(refused(118, NULL, "no definition table"), "  and codes_read with it");
}

static void test_game_view(void)
{
    SynScene s;
    const GameView* v;
    syn_default(&s);
    s.stratagems[1].kind = 151;
    s.table_rva = (uint32_t)BELOW;
    start_with(&s, &CODES);
    syn_add_mod_stratagem(151, 4, MOD_CODE);
    v = read_view();
    CHECK(v->table_rva == (uint32_t)BELOW && v->local_ok && reason_is(v, "") && v->row_count == 4,
          "game_read with the table below the image: table_rva is the displacement");
    CHECK(row_code_is(&v->rows[1], 151, MOD_CODE, 4) && row_code_is(&v->rows[0], 118, s.stratagems[0].code, 3),
          "  the mod kind's row has its code, the vanilla rows theirs");
    CHECK(v->scramble_known, "  scramble_known: the query ran");
    syn_tombstone(151);
    v = read_view();
    CHECK(v->rows[1].kind == 151 && v->rows[1].code_len == 0 && reason_is(v, "mod stratagem not loaded")
              && row_code_is(&v->rows[2], 50, s.stratagems[2].code, 6),
          "its mod taken out: the row stays without a code, the reason says why");

    syn_default(&s);
    s.stratagems[1].kind = 151;
    start_with(&s, &CODES);
    v = read_view();
    CHECK(v->table_rva == VANILLA_TABLE && v->rows[1].kind == 151 && v->rows[1].code_len == 0
              && reason_is(v, "unknown stratagem kind"),
          "kind 151 with the vanilla table: no code, \"unknown stratagem kind\"");
}

int main(void)
{
    test_vanilla_table();
    test_moved_table();
    test_mod_stratagems();
    test_array_places();
    test_double_read();
    test_shared_arrays();
    test_scramble();
    test_stratagems_refused();
    test_stale_pass_forgotten();
    test_game_view();
    CHECK(syn_write_count() == 0, "codes asked for no write");
    syn_free();
    TEST_MAIN_END
}
