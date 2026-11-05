/* codes: the definition table and the stratagem codes (see codes.h), ported from R46's code() (input.lua:141-179) and
 * extended for HellForge 0.4.0-beta's loader at commit d8a8b46 (HF). Portable C11: standard headers, memory.h,
 * admission.h, native.h, game.h and the generated address header only. The game's numbers are the generated header's
 * DBF_RVA_* / DBF_OFF_* / DBF_VAL_* names, each with its R46 line there; HellForge's own limits, which no R46 line holds,
 * are the named constants below with the HF lines they come from. The log line is built by hand, without printf-family
 * functions. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "codes.h"
#include "game.h"
#include "memory.h"
#include "native.h"

/* HellForge's limits (not R46's). */
#define HF_MAX_KIND 197u      /* HF stratagems.c:42-44: 150 vanilla + 48 new types, "stratagem types travel in 8 bits";
                                 the moved list has slots 0..197 */
#define HF_TABLE_NEAR 0x80000000ull /* HF damage.c:123-202: the block lies within 2 GiB of game.dll, above or below (the
                                 instruction's disp32 reaches it: stratagems.c:316-319) */
#define HF_CODE_MAX 9u        /* HF stratagems.c:47 (STR_MAX_CODE) and lua_bridge.c:363 (set_code: 1 to 9 directions) */
#define LOG_LINE_MAX 160

_Static_assert(DBF_VAL_CODE_MAX <= DBF_CODE_CAPACITY, "DbfCode.dir holds R46's longest code");
_Static_assert(HF_CODE_MAX <= DBF_VAL_CODE_MAX, "a HellForge code fits the buffer of a settings-block code");
_Static_assert(DBF_OFF_CODE_STRIDE == sizeof(uint32_t), "a code array is read whole as uint32_t directions");
_Static_assert(DBF_VAL_VANILLA_KINDS < HF_MAX_KIND, "HellForge's types follow the vanilla ones");

typedef enum { PLACE_NONE, PLACE_SETTINGS, PLACE_LOADER } Place;

typedef struct PassArray {
    uint32_t kind;
    uintptr_t array; /* the loader-image array the kind was read from */
    bool shared;     /* another kind read in this pass points at it too */
} PassArray;

static CodePort g_port;
static uintptr_t g_base; /* game.dll; 0 until codes_set_image */
static uint32_t g_image_size;
/* The pass: from one codes_table to the next. */
static bool g_table_ok;
static uintptr_t g_table;
static uint32_t g_max_kind;
static bool g_scramble_asked;
static PassArray g_arrays[CODES_PASS_ARRAYS];
static int g_array_count;
/* The session: since codes_init. */
static bool g_outside_logged[HF_MAX_KIND + 1];

/* --- text ------------------------------------------------------------------------------------------------------ */

/* reason = a b, cut to fit; false, for `return refuse(...)`. */
static bool refuse2(char* reason, size_t n, const char* a, const char* b)
{
    size_t at = 0;
    if (!reason || n == 0) return false;
    for (const char* p = a; p && *p && at < n - 1; p++) reason[at++] = *p;
    for (const char* p = b; p && *p && at < n - 1; p++) reason[at++] = *p;
    reason[at] = '\0';
    return false;
}

static bool refuse(char* reason, size_t n, const char* why)
{
    return refuse2(reason, n, why, NULL);
}

/* True when Stratagems (the table, the definitions and their codes) is admitted; else reason = "<feature name>:
 * <admission's reason>", as game_read words it. */
static bool stratagems_admitted(char* reason, size_t n)
{
    const char* why = NULL;
    char name[64];
    if (adm_feature(FEAT_STRATAGEMS, &why) == ADMIT_OK) return true;
    refuse2(name, sizeof name, adm_feature_name(FEAT_STRATAGEMS), ": ");
    return refuse2(reason, n, name, why && *why ? why : "not admitted");
}

static size_t put_text(char* line, size_t at, const char* text)
{
    while (*text && at < LOG_LINE_MAX - 1) line[at++] = *text++;
    return at;
}

/* `value` in decimal, or (hex) as 0x and lowercase digits without leading zeros. */
static size_t put_number(char* line, size_t at, uint64_t value, bool hex)
{
    static const char DIGITS[] = "0123456789abcdef";
    unsigned base = hex ? 16u : 10u;
    char digits[20];
    size_t d = 0;
    if (hex) at = put_text(line, at, "0x");
    do {
        digits[d++] = DIGITS[value % base];
        value /= base;
    } while (value != 0);
    while (d > 0 && at < LOG_LINE_MAX - 1) line[at++] = digits[--d];
    return at;
}

/* "kind <k>: code outside the game and HellForge (array 0x<address>, <n> directions)", once per kind per session. */
static void log_outside(uint32_t kind, uintptr_t array, uint32_t count)
{
    char line[LOG_LINE_MAX];
    size_t at;
    if (!g_port.log || kind > HF_MAX_KIND || g_outside_logged[kind]) return;
    g_outside_logged[kind] = true;
    at = put_text(line, 0, "kind ");
    at = put_number(line, at, kind, false);
    at = put_text(line, at, ": code outside the game and HellForge (array ");
    at = put_number(line, at, array, true);
    at = put_text(line, at, ", ");
    at = put_number(line, at, count, false);
    at = put_text(line, at, " directions)");
    line[at] = '\0';
    g_port.log(line);
}

/* --- session and pass ------------------------------------------------------------------------------------------ */

static void forget_pass(void)
{
    g_table_ok = false;
    g_table = 0;
    g_max_kind = 0;
    g_scramble_asked = false;
    g_array_count = 0;
}

void codes_init(const CodePort* port)
{
    if (port)
        g_port = *port;
    else
        memset(&g_port, 0, sizeof g_port);
    memset(g_outside_logged, 0, sizeof g_outside_logged);
    forget_pass();
}

void codes_set_image(uintptr_t game_dll, uint32_t image_size)
{
    g_base = image_size != 0 ? game_dll : 0;
    g_image_size = g_base != 0 ? image_size : 0;
    forget_pass();
}

uintptr_t codes_table_at(void)
{
    return g_table_ok ? g_table : 0;
}

bool codes_scramble_asked(void)
{
    return g_scramble_asked;
}

bool codes_shared(uint32_t kind)
{
    for (int i = 0; i < g_array_count; i++)
        if (g_arrays[i].kind == kind && g_arrays[i].shared) return true;
    return false;
}

/* --- the definition table -------------------------------------------------------------------------------------- */

/* HellForge's moved block (HF stratagems.c:372-388, 427-437; damage.c:123-202): all of its HF_MAX_KIND + 1 slots outside
 * game.dll's image, its start less than 2^31 bytes from game.dll, 8-aligned. `offset` is the sign-extended disp32. */
static bool moved_table_ok(int64_t offset, uintptr_t table)
{
    const int64_t extent = (int64_t)(HF_MAX_KIND + 1u) * DBF_OFF_DEFINITION_STRIDE;
    if (offset <= -(int64_t)HF_TABLE_NEAR || offset >= (int64_t)HF_TABLE_NEAR) return false;
    if (table % DBF_VAL_DEFINITION_TABLE_ALIGN != 0) return false;
    if (offset < 0) return (uint64_t)-offset <= (uint64_t)g_base && offset + extent <= 0; /* below, ending at game.dll */
    return offset >= (int64_t)g_image_size;                                              /* above, past the image */
}

bool codes_table(uint32_t* max_kind, char* reason, size_t n)
{
    uint8_t slots[HF_MAX_KIND * DBF_OFF_DEFINITION_STRIDE];
    uint32_t displacement, max;
    int64_t offset;
    uintptr_t table;
    forget_pass();
    if (max_kind) *max_kind = 0;
    if (reason && n > 0) reason[0] = '\0';
    if (g_base == 0) return refuse(reason, n, "not initialised");
    if (!stratagems_admitted(reason, n)) return false;
    if (!mem_u32(g_base + DBF_RVA_DEFINITION_DISPLACEMENT, &displacement))
        return refuse(reason, n, "definition table unreadable");
    /* The CPU sign-extends the disp32 of mov rax, [r13 + r15*8 + disp32] (HF stratagem_sites.h:27). */
    offset = (int64_t)(int32_t)displacement;
    table = g_base + (uintptr_t)offset;
    if (offset == (int64_t)DBF_RVA_DEFINITION_TABLE_VANILLA)
        max = DBF_VAL_VANILLA_KINDS; /* nothing moved: no HellForge mod stratagems (HF stratagems.c:486) */
    else if (moved_table_ok(offset, table))
        max = HF_MAX_KIND;
    else
        return refuse(reason, n, "definition table unrecognised");
    if (!mem_read(table + DBF_OFF_DEFINITION_STRIDE, slots, (size_t)max * DBF_OFF_DEFINITION_STRIDE))
        return refuse(reason, n, "definition table unreadable");
    g_table_ok = true;
    g_table = table;
    g_max_kind = max;
    if (max_kind) *max_kind = max;
    return true;
}

/* --- a kind's code --------------------------------------------------------------------------------------------- */

/* Rule 1: the kind's definition, a 4-aligned row naming it; a vanilla kind's inside the settings block (R46
 * input.lua:160-164), a HellForge type's the port's stratagem_row (HF stratagems.c:309-314). */
static const char* definition(uint32_t kind, uintptr_t settings, uintptr_t* def)
{
    uint32_t named;
    if (kind > DBF_VAL_VANILLA_KINDS) {
        uintptr_t row;
        if (!g_port.stratagem_row) return "mod stratagems unavailable";
        row = g_port.stratagem_row(kind);
        if (row == 0) return "mod stratagem not loaded";
        if (!mem_ptr_aligned(g_table + (uintptr_t)kind * DBF_OFF_DEFINITION_STRIDE, def, DBF_VAL_DEFINITION_ALIGN)
            || *def != row)
            return "invalid definition";
    } else if (!mem_ptr_aligned(g_table + (uintptr_t)kind * DBF_OFF_DEFINITION_STRIDE, def, DBF_VAL_DEFINITION_ALIGN)
               || *def < settings || *def + DBF_OFF_DEFINITION_SIZE > settings + DBF_OFF_SETTINGS_SIZE) {
        return "invalid definition";
    }
    if (!mem_u32(*def, &named) || named != kind) return "invalid definition";
    return NULL;
}

/* [array, array + 4 * count) inside [from, from + size); nothing is inside a range starting at 0 or of size 0 (a port
 * without the loader image). */
static bool inside(uintptr_t array, uint32_t count, uintptr_t from, uint64_t size)
{
    return from != 0 && size != 0 && array >= from
        && (uint64_t)(array - from) + (uint64_t)count * DBF_OFF_CODE_STRIDE <= size;
}

/* Rule 2's places: the settings block (R46 input.lua:166-168), or hellforge_modloader.dll's image with at most
 * HF_CODE_MAX directions. NULL with *place set, or why not. */
static const char* place_of(uintptr_t array, uint32_t count, uintptr_t settings, Place* place)
{
    *place = PLACE_NONE;
    if (inside(array, count, settings, DBF_OFF_SETTINGS_SIZE)) {
        *place = PLACE_SETTINGS;
    } else if (inside(array, count, g_port.loader_base, g_port.loader_size)) {
        if (count > HF_CODE_MAX) return "invalid code array";
        *place = PLACE_LOADER;
    }
    return NULL;
}

/* Rule 3: a loader-image array is the kind's alone in this pass. A share marks both kinds' entries. */
static const char* claim(uint32_t kind, uintptr_t array)
{
    PassArray* mine = NULL;
    bool shared = false;
    for (int i = 0; i < g_array_count; i++) {
        if (g_arrays[i].kind == kind) {
            mine = &g_arrays[i];
        } else if (g_arrays[i].array == array) {
            g_arrays[i].shared = true;
            shared = true;
        }
    }
    if (!mine) {
        if (g_array_count == CODES_PASS_ARRAYS) return "too many HellForge code arrays";
        mine = &g_arrays[g_array_count++];
        mine->kind = kind;
        mine->shared = false;
    }
    mine->array = array;
    if (shared) mine->shared = true;
    return mine->shared ? "shared code array" : NULL;
}

/* Rules 2 and 3 for `kind`'s definition `def`: the count, the pointer and the directions, read twice. */
static const char* read_code(uint32_t kind, uintptr_t def, uintptr_t settings, DbfCode* code)
{
    uint32_t count, count2, dirs[DBF_VAL_CODE_MAX], dirs2[DBF_VAL_CODE_MAX];
    uintptr_t array, array2;
    Place place;
    const char* why;
    if (!mem_u32(def + DBF_OFF_DEFINITION_CODE_COUNT_OFFSET, &count)
        || !mem_ptr_aligned(def + DBF_OFF_DEFINITION_CODE_OFFSET, &array, DBF_VAL_CODE_ALIGN) || count < DBF_VAL_CODE_MIN
        || count > DBF_VAL_CODE_MAX)
        return "invalid code array";
    if ((why = place_of(array, count, settings, &place)) != NULL) return why;
    if (place == PLACE_NONE) {
        log_outside(kind, array, count);
        return "code outside the game and HellForge";
    }
    if (!mem_read(array, dirs, (size_t)count * DBF_OFF_CODE_STRIDE)) return "code array unreadable";
    /* The second read: a code being changed (a Lua mod's set_code moves the pointer before the count grows onto it, HF
     * lua_bridge.c:350-353) must not be taken half-written. */
    if (!mem_u32(def + DBF_OFF_DEFINITION_CODE_COUNT_OFFSET, &count2)
        || !mem_ptr_aligned(def + DBF_OFF_DEFINITION_CODE_OFFSET, &array2, DBF_VAL_CODE_ALIGN) || count2 != count
        || array2 != array || !mem_read(array, dirs2, (size_t)count * DBF_OFF_CODE_STRIDE)
        || memcmp(dirs, dirs2, (size_t)count * DBF_OFF_CODE_STRIDE) != 0)
        return "code changed while reading";
    for (uint32_t i = 0; i < count; i++)
        if (dirs[i] < DBF_VAL_DIRECTION_MIN || dirs[i] > DBF_VAL_DIRECTION_MAX) return "invalid direction";
    if (place == PLACE_LOADER && (why = claim(kind, array)) != NULL) return why;
    for (uint32_t i = 0; i < count; i++) code->dir[i] = (uint8_t)dirs[i];
    code->len = (uint8_t)count;
    return NULL;
}

/* R46 input.lua:150-152: the scramble query reads the player's position, so its entry must be there first. */
static bool position_ready(const GameLocal* local)
{
    uintptr_t positions, entries;
    uint32_t index;
    uint8_t position[DBF_OFF_POSITION_SIZE];
    return mem_ptr(g_base + DBF_RVA_POSITIONS, &positions)
        && game_lookup(positions, DBF_OFF_POSITIONS_LOOKUP_OFFSET, local->key, DBF_VAL_POSITIONS_INDEX_LIMIT, &index)
        && mem_ptr(positions + DBF_OFF_POSITIONS_ENTRIES_OFFSET, &entries)
        && mem_read(entries + (uintptr_t)index * DBF_OFF_POSITIONS_ENTRY_STRIDE + DBF_OFF_POSITION_OFFSET, position,
                    sizeof position);
}

bool codes_read(uint32_t kind, const GameLocal* local, DbfCode* out, char* reason, size_t n)
{
    DbfCode code;
    uintptr_t settings, def;
    const char* why = NULL;
    if (out) memset(out, 0, sizeof *out);
    if (reason && n > 0) reason[0] = '\0';
    if (!out) return false;
    if (!g_table_ok) return refuse(reason, n, "no definition table");
    if (!stratagems_admitted(reason, n)) return false;
    if (kind == 0 || kind > g_max_kind) return refuse(reason, n, "unknown stratagem kind");
    if (!mem_ptr(g_base + DBF_RVA_SETTINGS, &settings)) return refuse(reason, n, "settings unreadable");
    /* The kind's own definition first: the scramble query reads it (R46 input.lua:145-149). */
    if ((why = definition(kind, settings, &def)) != NULL) return refuse(reason, n, why);
    memset(&code, 0, sizeof code);
    code.kind_used = kind;
    if (local && adm_feature(FEAT_SCRAMBLE, NULL) == ADMIT_OK) {
        uint32_t answer, seed;
        if (!position_ready(local)) return refuse(reason, n, "scramble position unavailable");
        if (nat_scramble_query(local->key, kind, &answer)) {
            g_scramble_asked = true;
            if (answer != DBF_VAL_SCRAMBLE_NONE) {
                /* R46 input.lua:156-157 remaps modulo the 149 vanilla kinds; HellForge raises the game's bounds by its
                 * new types (HF stratagems.c:448-461), so with its table the game's modulus may differ. */
                if (g_max_kind > DBF_VAL_VANILLA_KINDS)
                    return refuse(reason, n, "scrambled codes with mod stratagems are not supported yet");
                if (!mem_u32(local->avatar + DBF_OFF_AVATAR_SCRAMBLE_SEED_OFFSET, &seed))
                    return refuse(reason, n, "scramble seed unreadable");
                code.kind_used = (uint32_t)(kind + seed) % DBF_VAL_VANILLA_KINDS + 1u; /* the sum wraps mod 2^32 */
                code.scrambled = true;
                if ((why = definition(code.kind_used, settings, &def)) != NULL) return refuse(reason, n, why);
            }
        }
    }
    if ((why = read_code(code.kind_used, def, settings, &code)) != NULL) return refuse(reason, n, why);
    *out = code;
    return true;
}
