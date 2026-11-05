/* admission: per-feature checks of the live game against build 25480438 (see admission.h). Portable C11: standard headers
 * and the generated address header only. It builds its reason strings itself rather than with snprintf, so the DLL needs
 * no C runtime import for them. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "admission.h"

/* This is the one translation unit that defines the generated witness table. A test replaces it with a small table of its
 * own (it defines DBF_TEST_WITNESSES; tests/test_witnesses.h then defines dbf_witnesses and dbf_witness_count, and the
 * generated header is included only for its types and DBF_FEATURE_* numbers). */
#ifdef DBF_TEST_WITNESSES
#include "addresses_25480438.h"
#include "test_witnesses.h"
#else
#define DBF_ADDRESSES_DEFINE
#include "addresses_25480438.h"
#endif

/* Feature is the generated numbering: a witness' mask is (1u << DBF_FEATURE_*). */
#define TIE(name) _Static_assert((int)FEAT_##name == DBF_FEATURE_##name, "Feature and DBF_FEATURE_" #name " differ")
TIE(STATE);
TIE(STRATAGEMS);
TIE(HUD_READ);
TIE(LIST_OPACITY);
TIE(ENTRY);
TIE(SCRAMBLE);
TIE(POINTING);
TIE(CAMERA);
TIE(LATCH);
TIE(SOUND);
TIE(DOCK);
TIE(WEAPON);
TIE(TERMINAL);
_Static_assert((int)FEAT_COUNT == DBF_FEATURE_COUNT, "Feature and DBF_FEATURE_COUNT differ");
_Static_assert(DBF_FEATURE_COUNT <= 32, "a witness' feature mask is a uint32_t");

#define GAME_MODULE "game.dll"
#define GAME_STAMP 0x6AB3B43Fu /* TimeDateStamp of build 25480438 */
#define EXE_MODULE "helldivers2.exe"
#define EXE_STAMP 0x6AB382E4u

#define RETRY_MS 1000u  /* pending things are retried this often */
#define GRACE_MS 30000u /* a witness that differs may still be patched or unpacked this long after adm_init */
#define CHUNK 64u       /* a witness is read and compared this many bytes at a time */
#define REASON_MAX 96
#define LOG_MAX 160      /* a log line: "witness <name>: <n> of <size> bytes rewritten by HellForge" */
#define LOG_NAME_MAX 64  /* a longer witness name is cut, so the counts after it always fit */
#define MAX_WITNESSES 128
#define WITNESS_COUNT (sizeof dbf_witnesses / sizeof dbf_witnesses[0])
_Static_assert(WITNESS_COUNT <= MAX_WITNESSES, "raise MAX_WITNESSES");

typedef enum {
    W_UNREADABLE, /* pending: the bytes could not be read (also the state before the first look) */
    W_DIFFERS,    /* pending: the bytes differ, still within the grace period */
    W_MATCHED,    /* final */
    W_REFUSED     /* final: differed when the grace period was over */
} WitnessState;

typedef struct {
    Admit admit;
    char reason[REASON_MAX];
} FeatureStatus;

static const char* const NOT_STARTED = "not started";
static const char* const UNKNOWN_FEATURE = "unknown feature";
static const char* const NOT_MAPPED = "not mapped yet";

static const char* const NAMES[FEAT_COUNT] = {
    [FEAT_STATE] = "Selection state",
    [FEAT_STRATAGEMS] = "Stratagems",
    [FEAT_HUD_READ] = "HUD reads",
    [FEAT_LIST_OPACITY] = "List fade",
    [FEAT_ENTRY] = "Code entry",
    [FEAT_SCRAMBLE] = "Scrambled codes",
    [FEAT_POINTING] = "Wheel pointing",
    [FEAT_CAMERA] = "Camera hold",
    [FEAT_LATCH] = "Select on Release",
    [FEAT_SOUND] = "Sounds",
    [FEAT_DOCK] = "Cooldown display",
    [FEAT_WEAPON] = "Weapon strip",
    [FEAT_TERMINAL] = "Terminals",
};

static AdmPort g_port;
static bool g_started;
static uint64_t g_start_ms;
static uint64_t g_last_ms; /* the last time pending things were looked at */

static Admit g_build; /* PENDING until both modules' stamps were read; then OK, or REFUSED for good */
static char g_build_reason[REASON_MAX];
static bool g_game_ok, g_exe_ok; /* stamp verified: never read again */
static uintptr_t g_game_base;

static WitnessState g_witness[MAX_WITNESSES];
static bool g_mask_logged[MAX_WITNESSES]; /* the witness' masked-byte count was logged since adm_init */
static FeatureStatus g_feature[FEAT_COUNT];

/* dst = a b c, cut to fit. */
static void join(char* dst, const char* a, const char* b, const char* c)
{
    size_t n = 0;
    const char* parts[3] = { a, b, c };
    for (int i = 0; i < 3; i++)
        for (const char* p = parts[i]; *p && n < REASON_MAX - 1; p++) dst[n++] = *p;
    dst[n] = '\0';
}

static void hex8(char out[9], uint32_t v)
{
    static const char DIGITS[] = "0123456789abcdef";
    for (int i = 0; i < 8; i++) out[i] = DIGITS[(v >> (28 - 4 * i)) & 15u];
    out[8] = '\0';
}

static uint32_t le32(const uint8_t* p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

/* Reads the TimeDateStamp of a module's PE header: MZ, e_lfanew at +0x3c, "PE\0\0", the stamp at +8 of that header. OK
 * when it equals `want` (and the module's base is stored); REFUSED for a wrong stamp or an image that is not a PE file;
 * PENDING when the module is not loaded or its header cannot be read yet. g_build_reason says why when it is not OK. */
static Admit check_module(const char* module, uint32_t want, uintptr_t* base_out)
{
    size_t image = 0;
    uint8_t dos[0x40], nt[12];
    uint32_t lfanew, stamp;
    uintptr_t base = g_port.module_base(module, &image);
    if (base == 0) {
        join(g_build_reason, module, " is not loaded yet", "");
        return ADMIT_PENDING;
    }
    if (g_port.read_code(base, dos, sizeof dos) != 0) {
        join(g_build_reason, module, " header not readable yet", "");
        return ADMIT_PENDING;
    }
    lfanew = le32(dos + 0x3c);
    if (dos[0] != 'M' || dos[1] != 'Z' || lfanew < sizeof dos || (image != 0 && (uint64_t)lfanew + sizeof nt > image)) {
        join(g_build_reason, module, " is not a valid image", "");
        return ADMIT_REFUSED;
    }
    if (g_port.read_code(base + lfanew, nt, sizeof nt) != 0) {
        join(g_build_reason, module, " header not readable yet", "");
        return ADMIT_PENDING;
    }
    if (memcmp(nt, "PE\0\0", 4) != 0) {
        join(g_build_reason, module, " is not a valid image", "");
        return ADMIT_REFUSED;
    }
    stamp = le32(nt + 8);
    if (stamp != want) {
        char hex[9];
        hex8(hex, stamp);
        join(g_build_reason, "build ", hex, " is not 25480438");
        return ADMIT_REFUSED;
    }
    *base_out = base;
    return ADMIT_OK;
}

static void check_build(void)
{
    uintptr_t exe_base = 0;
    Admit a;
    if (!g_game_ok) {
        a = check_module(GAME_MODULE, GAME_STAMP, &g_game_base);
        if (a != ADMIT_OK) {
            g_build = a;
            return;
        }
        g_game_ok = true;
    }
    if (!g_exe_ok) {
        a = check_module(EXE_MODULE, EXE_STAMP, &exe_base);
        if (a != ADMIT_OK) {
            g_build = a;
            return;
        }
        g_exe_ok = true;
    }
    g_build = ADMIT_OK;
    g_build_reason[0] = '\0';
}

typedef enum { CMP_MATCH, CMP_DIFFERS, CMP_UNREADABLE } Compare;

static size_t put_text(char* dst, size_t at, const char* text, size_t limit)
{
    for (size_t i = 0; text[i] != '\0' && i < limit && at < LOG_MAX - 1; i++) dst[at++] = text[i];
    return at;
}

static size_t put_uint(char* dst, size_t at, uint32_t value)
{
    char digits[10];
    int n = 0;
    do {
        digits[n++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value != 0);
    while (n > 0 && at < LOG_MAX - 1) dst[at++] = digits[--n];
    return at;
}

/* "witness <name>: <masked> of <size> bytes rewritten by HellForge". */
static void log_masked(const DbfWitness* w, uint32_t masked)
{
    char line[LOG_MAX];
    size_t at = put_text(line, 0, "witness ", LOG_MAX);
    at = put_text(line, at, w->name, LOG_NAME_MAX);
    at = put_text(line, at, ": ", LOG_MAX);
    at = put_uint(line, at, masked);
    at = put_text(line, at, " of ", LOG_MAX);
    at = put_uint(line, at, w->size);
    at = put_text(line, at, " bytes rewritten by HellForge", LOG_MAX);
    line[at] = '\0';
    g_port.log(line);
}

/* Reads the witness' span of game.dll and compares it with the table's bytes. A byte that HellForge may rewrite (the
 * port's `rewrites`) is left out of the comparison. An unreadable chunk makes the whole witness unreadable, whatever the
 * other chunks hold. When the port can log and this witness was not logged yet, `rewrites` is asked about every byte, so
 * that the count of masked bytes is the witness' whole count, matching or not; the count is logged once the whole witness
 * was read. Otherwise it is asked only about the bytes that differ. */
static Compare compare_witness(size_t index)
{
    const DbfWitness* w = &dbf_witnesses[index];
    uint8_t buf[CHUNK];
    bool differs = false;
    bool counting = g_port.rewrites && g_port.log && !g_mask_logged[index];
    uint32_t masked = 0;
    if (w->size > 0 && w->bytes == NULL) return CMP_DIFFERS;
    for (uint32_t off = 0; off < w->size; off += CHUNK) {
        uint32_t n = w->size - off < CHUNK ? w->size - off : CHUNK;
        if (g_port.read_code(g_game_base + w->rva + off, buf, n) != 0) return CMP_UNREADABLE;
        for (uint32_t i = 0; i < n; i++) {
            bool same = buf[i] == w->bytes[off + i];
            bool rewritten = false;
            if (counting || (!same && g_port.rewrites)) rewritten = g_port.rewrites(w->rva + off + i, 1) != 0;
            if (rewritten) masked++;
            if (!same && !rewritten) differs = true;
        }
    }
    if (counting && masked > 0) {
        g_mask_logged[index] = true;
        log_masked(w, masked);
    }
    return differs ? CMP_DIFFERS : CMP_MATCH;
}

static void check_witnesses(uint64_t now_ms)
{
    bool grace_over = now_ms >= g_start_ms && now_ms - g_start_ms >= GRACE_MS;
    for (size_t i = 0; i < WITNESS_COUNT; i++) {
        if (g_witness[i] == W_MATCHED || g_witness[i] == W_REFUSED) continue;
        switch (compare_witness(i)) {
        case CMP_MATCH: g_witness[i] = W_MATCHED; break;
        case CMP_UNREADABLE: g_witness[i] = W_UNREADABLE; break;
        case CMP_DIFFERS: g_witness[i] = grace_over ? W_REFUSED : W_DIFFERS; break;
        }
    }
}

static void witness_reason(char* dst, size_t index)
{
    const char* name = dbf_witnesses[index].name;
    switch (g_witness[index]) {
    case W_UNREADABLE: join(dst, "witness ", name, " not readable yet"); break;
    case W_DIFFERS: join(dst, "witness ", name, " differs (retrying)"); break;
    case W_REFUSED: join(dst, "witness ", name, " differs"); break;
    case W_MATCHED: dst[0] = '\0'; break;
    }
}

/* A feature is refused when its build is wrong or any witness in its mask is refused, else pending when any is pending,
 * else ok; a feature that no witness mentions is refused as not mapped. The reason is the first refused witness', or else
 * the first pending one's. Until the build is verified the build's own status and reason stand for every feature. */
static void recompute(void)
{
    for (int f = 0; f < FEAT_COUNT; f++) {
        FeatureStatus* s = &g_feature[f];
        uint32_t bit = 1u << f;
        bool mapped = false;
        size_t first_refused = WITNESS_COUNT, first_pending = WITNESS_COUNT;
        if (g_build != ADMIT_OK) {
            s->admit = g_build;
            join(s->reason, g_build_reason, "", "");
            continue;
        }
        for (size_t i = 0; i < WITNESS_COUNT; i++) {
            if (!(dbf_witnesses[i].features & bit)) continue;
            mapped = true;
            if (g_witness[i] == W_REFUSED && first_refused == WITNESS_COUNT) first_refused = i;
            if ((g_witness[i] == W_UNREADABLE || g_witness[i] == W_DIFFERS) && first_pending == WITNESS_COUNT) first_pending = i;
        }
        if (first_refused != WITNESS_COUNT) {
            s->admit = ADMIT_REFUSED;
            witness_reason(s->reason, first_refused);
        } else if (first_pending != WITNESS_COUNT) {
            s->admit = ADMIT_PENDING;
            witness_reason(s->reason, first_pending);
        } else if (!mapped) {
            s->admit = ADMIT_REFUSED;
            join(s->reason, NOT_MAPPED, "", "");
        } else {
            s->admit = ADMIT_OK;
            s->reason[0] = '\0';
        }
    }
}

static void run_checks(uint64_t now_ms)
{
    if (g_build != ADMIT_REFUSED) { /* a refused build is final */
        if (g_build != ADMIT_OK) check_build();
        if (g_build == ADMIT_OK) check_witnesses(now_ms);
    }
    recompute();
}

void adm_init(const AdmPort* port, uint64_t now_ms)
{
    memset(&g_port, 0, sizeof g_port);
    memset(g_witness, 0, sizeof g_witness); /* W_UNREADABLE */
    memset(g_mask_logged, 0, sizeof g_mask_logged);
    memset(g_feature, 0, sizeof g_feature);
    g_game_ok = g_exe_ok = false;
    g_game_base = 0;
    g_build = ADMIT_PENDING;
    g_build_reason[0] = '\0';
    g_start_ms = g_last_ms = now_ms;
    g_started = true;
    if (port) g_port = *port;
    if (!g_port.module_base || !g_port.read_code) {
        g_build = ADMIT_REFUSED;
        join(g_build_reason, "no code access", "", "");
    }
    run_checks(now_ms);
}

void adm_tick(uint64_t now_ms)
{
    if (!g_started) return;
    if (now_ms < g_last_ms) { /* the clock went back: count from here */
        g_last_ms = now_ms;
        return;
    }
    if (now_ms - g_last_ms < RETRY_MS) return;
    g_last_ms = now_ms;
    run_checks(now_ms);
}

bool adm_build_ok(const char** reason)
{
    if (!g_started) {
        if (reason) *reason = NOT_STARTED;
        return false;
    }
    if (reason) *reason = g_build_reason;
    return g_build == ADMIT_OK;
}

Admit adm_feature(Feature f, const char** reason)
{
    if (!g_started) {
        if (reason) *reason = NOT_STARTED;
        return ADMIT_PENDING;
    }
    if ((unsigned)f >= (unsigned)FEAT_COUNT) {
        if (reason) *reason = UNKNOWN_FEATURE;
        return ADMIT_REFUSED;
    }
    if (reason) *reason = g_feature[f].reason;
    return g_feature[f].admit;
}

const char* adm_feature_name(Feature f)
{
    if ((unsigned)f >= (unsigned)FEAT_COUNT) return "Unknown";
    return NAMES[f];
}
