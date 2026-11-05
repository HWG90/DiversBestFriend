/* flags: -DDBF_TEST_WITNESSES */
/* Tests for src/admission.c against a fake port over a synthetic game image: a buffer with a PE header carrying the build
 * stamp and the witness bytes of tests/test_witnesses.h (admission.c uses that small table under -DDBF_TEST_WITNESSES; the
 * generated table is covered by test_admission_table.c). Admission keeps its state in statics, so every test starts with
 * start(), which calls adm_init again; test_before_init must run first, while nothing has been started. */
#include <stdint.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "test.h"

#define GAME_BASE ((uintptr_t)0x10000000u)
#define GAME_SIZE 0x1000u
#define EXE_BASE ((uintptr_t)0x30000000u)
#define EXE_SIZE 0x200u
#define LFANEW 0x80u
#define HEADER_SIZE 0x100u /* the witnesses start above this */
#define GAME_STAMP 0x6AB3B43Fu
#define EXE_STAMP 0x6AB382E4u

static uint8_t g_game[GAME_SIZE];
static uint8_t g_exe[EXE_SIZE];
static int g_game_loaded, g_exe_loaded; /* module_base reports 0 for a module that is not loaded */
static uint64_t g_now;                  /* the clock the fake port's failures follow */
static uint32_t g_blind_lo, g_blind_hi; /* game.dll RVAs [lo, hi) that read_code cannot read before g_blind_until */
static uint64_t g_blind_until;
static uint32_t g_rw_lo, g_rw_hi; /* game.dll RVAs [lo, hi) that the fake HellForge may rewrite */
static int g_reads;               /* read_code calls */
static int g_witness_reads;       /* read_code calls above the header of game.dll */
static int g_rw_calls, g_rw_misuse;

static void put32(uint8_t* p, uint32_t v)
{
    for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * i));
}

static uintptr_t fake_module_base(const char* module, size_t* size)
{
    if (!strcmp(module, "game.dll") && g_game_loaded) {
        if (size) *size = GAME_SIZE;
        return GAME_BASE;
    }
    if (!strcmp(module, "helldivers2.exe") && g_exe_loaded) {
        if (size) *size = EXE_SIZE;
        return EXE_BASE;
    }
    return 0;
}

static int fake_read_code(uintptr_t address, void* out, size_t size)
{
    const uint8_t* image;
    uintptr_t offset;
    size_t length;
    g_reads++;
    if (address >= GAME_BASE && address - GAME_BASE < GAME_SIZE) {
        image = g_game;
        offset = address - GAME_BASE;
        length = GAME_SIZE;
        if (offset >= HEADER_SIZE) g_witness_reads++;
        if (g_now < g_blind_until && offset < g_blind_hi && offset + size > g_blind_lo) return -1;
    } else if (address >= EXE_BASE && address - EXE_BASE < EXE_SIZE) {
        image = g_exe;
        offset = address - EXE_BASE;
        length = EXE_SIZE;
    } else {
        return -1;
    }
    if (size > length - offset) return -1;
    memcpy(out, image + offset, size);
    return 0;
}

static int fake_rewrites(uint32_t rva, uint32_t size)
{
    g_rw_calls++;
    if (size != 1) g_rw_misuse++;
    return rva < g_rw_hi && rva + size > g_rw_lo;
}

static const AdmPort PORT = { fake_module_base, fake_read_code, fake_rewrites };
static const AdmPort PORT_NO_REWRITES = { fake_module_base, fake_read_code, NULL };

static const DbfWitness* wit(const char* name)
{
    for (int i = 0; i < dbf_witness_count; i++)
        if (!strcmp(dbf_witnesses[i].name, name)) return &dbf_witnesses[i];
    return NULL;
}

static void put_header(uint8_t* image, uint32_t stamp)
{
    image[0] = 'M';
    image[1] = 'Z';
    put32(image + 0x3c, LFANEW);
    memcpy(image + LFANEW, "PE\0\0", 4);
    put32(image + LFANEW + 8, stamp);
}

/* A fresh game: both modules loaded with the right stamps, every witness' bytes in place, nothing failing. */
static void reset(void)
{
    memset(g_game, 0xcc, sizeof g_game);
    memset(g_exe, 0xcc, sizeof g_exe);
    put_header(g_game, GAME_STAMP);
    put_header(g_exe, EXE_STAMP);
    for (int i = 0; i < dbf_witness_count; i++)
        memcpy(g_game + dbf_witnesses[i].rva, dbf_witnesses[i].bytes, dbf_witnesses[i].size);
    g_game_loaded = g_exe_loaded = 1;
    g_now = 0;
    g_blind_lo = g_blind_hi = 0;
    g_blind_until = 0;
    g_rw_lo = g_rw_hi = 0;
    g_reads = g_witness_reads = g_rw_calls = g_rw_misuse = 0;
}

static void start(uint64_t ms)
{
    g_now = ms;
    adm_init(&PORT, ms);
}

static void tick(uint64_t ms)
{
    g_now = ms;
    adm_tick(ms);
}

/* The reads of the witness `name` fail until the clock reaches `until`. */
static void blind_witness(const char* name, uint64_t until)
{
    g_blind_lo = wit(name)->rva;
    g_blind_hi = g_blind_lo + wit(name)->size;
    g_blind_until = until;
}

static void flip(const char* name, unsigned index)
{
    g_game[wit(name)->rva + index] ^= 0x55;
}

/* True when the feature has exactly this status and reason (a NULL reason is not compared). */
static int is(Feature f, Admit want, const char* reason)
{
    const char* got = NULL;
    Admit admit = adm_feature(f, &got);
    return admit == want && got != NULL && (reason == NULL || strcmp(got, reason) == 0);
}

static int all_are(Admit want, const char* reason)
{
    int ok = 1;
    for (int f = 0; f < FEAT_COUNT; f++) ok &= is((Feature)f, want, reason);
    return ok;
}

static const Feature UNMAPPED[] = { FEAT_LIST_OPACITY, FEAT_ENTRY, FEAT_SCRAMBLE, FEAT_CAMERA,
                                    FEAT_LATCH,        FEAT_DOCK,  FEAT_WEAPON,   FEAT_TERMINAL };

static int unmapped_refused(void)
{
    int ok = 1;
    for (size_t i = 0; i < sizeof UNMAPPED / sizeof UNMAPPED[0]; i++) ok &= is(UNMAPPED[i], ADMIT_REFUSED, "not mapped yet");
    return ok;
}

static void test_before_init(void)
{
    const char* r = NULL;
    reset();
    adm_tick(5000);
    CHECK(g_reads == 0, "adm_tick before adm_init does nothing");
    CHECK(!adm_build_ok(&r) && r != NULL && !strcmp(r, "not started"), "before adm_init the build is not ok: not started");
    CHECK(is(FEAT_STATE, ADMIT_PENDING, "not started"), "before adm_init a feature is pending: not started");
    CHECK(all_are(ADMIT_PENDING, "not started"), "before adm_init every feature is pending: not started");
    CHECK(!adm_build_ok(NULL) && adm_feature(FEAT_STATE, NULL) == ADMIT_PENDING, "a NULL reason is accepted");
}

static void test_table_is_the_test_table(void)
{
    CHECK(dbf_witness_count == 4 && wit("alpha") && wit("bravo") && wit("charlie") && wit("delta"),
          "this test runs against the four-witness test table");
    CHECK(FEAT_COUNT == DBF_FEATURE_COUNT, "the Feature enum counts the generated features");
}

static void test_all_match(void)
{
    const char* r = NULL;
    int reads;
    reset();
    start(0);
    CHECK(adm_build_ok(&r) && r != NULL && r[0] == '\0', "right stamps: the build is ok with an empty reason");
    CHECK(is(FEAT_STATE, ADMIT_OK, ""), "matching bytes: FEAT_STATE is ok with an empty reason");
    CHECK(is(FEAT_STRATAGEMS, ADMIT_OK, "") && is(FEAT_HUD_READ, ADMIT_OK, "") && is(FEAT_POINTING, ADMIT_OK, "") &&
              is(FEAT_SOUND, ADMIT_OK, ""),
          "matching bytes: every feature with witnesses is ok");
    CHECK(is(FEAT_WEAPON, ADMIT_REFUSED, "not mapped yet"), "FEAT_WEAPON has no witness: refused, not mapped yet");
    CHECK(unmapped_refused(), "every feature without a witness is refused: not mapped yet");
    reads = g_reads;
    tick(1000);
    tick(2000);
    tick(90000);
    CHECK(g_reads == reads, "a verified build and matched witnesses are never read again");
    CHECK(is(FEAT_STATE, ADMIT_OK, "") && is(FEAT_POINTING, ADMIT_OK, ""), "and they stay ok");
}

static void test_wrong_build(void)
{
    const char* r = NULL;
    reset();
    put32(g_game + LFANEW + 8, 0x6AE0E5FFu);
    start(0);
    CHECK(!adm_build_ok(&r) && r != NULL && !strcmp(r, "build 6ae0e5ff is not 25480438"),
          "game.dll stamp 0x6AE0E5FF: the build is not ok, build 6ae0e5ff is not 25480438");
    CHECK(all_are(ADMIT_REFUSED, "build 6ae0e5ff is not 25480438"), "a wrong build refuses every feature, FEAT_WEAPON included");
    CHECK(g_witness_reads == 0, "a wrong build reads no witness");
    tick(60000);
    CHECK(all_are(ADMIT_REFUSED, "build 6ae0e5ff is not 25480438") && g_witness_reads == 0, "and stays refused");

    reset();
    put32(g_exe + LFANEW + 8, 0x0012ABCDu);
    start(0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "build 0012abcd is not 25480438"),
          "helldivers2.exe with a wrong stamp: lowercase hex padded to 8 digits");
    CHECK(all_are(ADMIT_REFUSED, "build 0012abcd is not 25480438"), "and every feature is refused");

    reset();
    put32(g_game + LFANEW + 8, 0x6AB3B440u);
    put32(g_exe + LFANEW + 8, 0x6AB382E5u);
    start(0);
    CHECK(!adm_build_ok(NULL) && all_are(ADMIT_REFUSED, "build 6ab3b440 is not 25480438"),
          "stamps off by one are wrong; game.dll is named first");
}

static void test_modules(void)
{
    const char* r = NULL;
    reset();
    g_game_loaded = 0;
    start(0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "game.dll is not loaded yet"), "game.dll missing: the build is not ok and the reason names it");
    CHECK(is(FEAT_STATE, ADMIT_PENDING, "game.dll is not loaded yet") && is(FEAT_WEAPON, ADMIT_PENDING, "game.dll is not loaded yet"),
          "a module that is not loaded yet leaves every feature pending");
    tick(500);
    g_game_loaded = 1;
    tick(1000);
    CHECK(adm_build_ok(&r) && is(FEAT_STATE, ADMIT_OK, "") && is(FEAT_SOUND, ADMIT_OK, ""),
          "game.dll loads later: the next tick admits the features that match, in the same pass");

    reset();
    g_exe_loaded = 0;
    start(0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "helldivers2.exe is not loaded yet"), "helldivers2.exe missing: the reason names it");
    CHECK(all_are(ADMIT_PENDING, "helldivers2.exe is not loaded yet"), "and every feature is pending");
    g_exe_loaded = 1;
    tick(1000);
    CHECK(adm_build_ok(NULL) && is(FEAT_STATE, ADMIT_OK, ""), "helldivers2.exe appears: admitted");

    reset();
    g_blind_lo = 0;
    g_blind_hi = HEADER_SIZE;
    g_blind_until = 4000;
    start(0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "game.dll header not readable yet"), "an unreadable header: the build is not ok, not readable yet");
    CHECK(all_are(ADMIT_PENDING, "game.dll header not readable yet"), "and every feature is pending");
    tick(3000);
    CHECK(!adm_build_ok(NULL), "still unreadable at 3000");
    tick(4000);
    CHECK(adm_build_ok(NULL) && is(FEAT_STATE, ADMIT_OK, ""), "readable at 4000: admitted");

    reset();
    g_game[0] = 'X';
    start(0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "game.dll is not a valid image"), "no MZ: not a valid image");
    CHECK(all_are(ADMIT_REFUSED, "game.dll is not a valid image"), "and every feature is refused");
    reset();
    g_exe[LFANEW] = 'X';
    start(0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "helldivers2.exe is not a valid image"), "no PE signature: not a valid image");
    reset();
    put32(g_game + 0x3c, GAME_SIZE); /* the PE header would lie beyond the image */
    start(0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "game.dll is not a valid image"), "a PE header beyond the image is not a valid image");
}

static void test_one_witness_differs(void)
{
    const char* r = NULL;
    reset();
    flip("alpha", 3);
    start(0);
    CHECK(is(FEAT_STATE, ADMIT_PENDING, "witness alpha differs (retrying)"), "a changed byte: pending while the grace period runs");
    CHECK(adm_build_ok(NULL), "a differing witness does not touch the build");
    tick(31000);
    CHECK(is(FEAT_STATE, ADMIT_REFUSED, "witness alpha differs"), "after the grace period the feature is refused, the reason names the witness");
    CHECK(is(FEAT_HUD_READ, ADMIT_REFUSED, "witness alpha differs"), "every feature in the witness' mask is refused");
    CHECK(is(FEAT_STRATAGEMS, ADMIT_OK, "") && is(FEAT_POINTING, ADMIT_OK, "") && is(FEAT_SOUND, ADMIT_OK, ""),
          "only the features of that witness are refused");
    CHECK(adm_feature(FEAT_STATE, &r) == ADMIT_REFUSED && strstr(r, "alpha") != NULL, "the reason names alpha");
    flip("alpha", 3);
    tick(33000);
    CHECK(is(FEAT_STATE, ADMIT_REFUSED, "witness alpha differs"), "a refused witness stays refused");
}

static void test_grace(void)
{
    reset();
    flip("alpha", 3);
    start(0);
    CHECK(is(FEAT_STATE, ADMIT_PENDING, "witness alpha differs (retrying)"), "a difference at 0 is pending");
    flip("alpha", 3);
    tick(5000);
    CHECK(is(FEAT_STATE, ADMIT_OK, "") && is(FEAT_HUD_READ, ADMIT_OK, ""), "a difference that is gone by 5000 ends ok");

    reset();
    flip("alpha", 3);
    start(0);
    tick(29000);
    CHECK(is(FEAT_STATE, ADMIT_PENDING, "witness alpha differs (retrying)"), "a difference that persists is still pending at 29000");
    tick(31000);
    CHECK(is(FEAT_STATE, ADMIT_REFUSED, "witness alpha differs"), "and refused after the tick at 31000");

    reset();
    flip("alpha", 3);
    start(0);
    tick(29000);
    tick(30000);
    CHECK(is(FEAT_STATE, ADMIT_REFUSED, "witness alpha differs"), "refused once 30000 ms have passed");

    reset();
    flip("alpha", 3);
    start(10000);
    tick(39000);
    CHECK(is(FEAT_STATE, ADMIT_PENDING, "witness alpha differs (retrying)"), "the grace period counts from adm_init's time: pending at 39000");
    tick(40000);
    CHECK(is(FEAT_STATE, ADMIT_REFUSED, "witness alpha differs"), "and refused at 40000");
}

static void test_unreadable(void)
{
    reset();
    blind_witness("charlie", 3000);
    start(0);
    CHECK(is(FEAT_POINTING, ADMIT_PENDING, "witness charlie not readable yet"), "an unreadable witness: pending at 0");
    CHECK(is(FEAT_HUD_READ, ADMIT_PENDING, "witness charlie not readable yet"), "in every feature of its mask");
    CHECK(is(FEAT_STATE, ADMIT_OK, "") && is(FEAT_STRATAGEMS, ADMIT_OK, "") && is(FEAT_SOUND, ADMIT_OK, ""),
          "and the other features are admitted meanwhile");
    tick(1500);
    CHECK(is(FEAT_POINTING, ADMIT_PENDING, "witness charlie not readable yet"), "still pending at 1500");
    tick(3000);
    CHECK(is(FEAT_POINTING, ADMIT_OK, "") && is(FEAT_HUD_READ, ADMIT_OK, ""), "ok after the tick at 3000");

    reset();
    blind_witness("charlie", 1000000);
    start(0);
    tick(31000);
    tick(120000);
    CHECK(is(FEAT_POINTING, ADMIT_PENDING, "witness charlie not readable yet"), "an unreadable witness is never refused for time");
}

static void test_retry_cadence(void)
{
    int reads;
    reset();
    blind_witness("charlie", 5000);
    start(0);
    reads = g_reads;
    tick(999);
    CHECK(g_reads == reads, "no retry before 1000 ms have passed");
    tick(1000);
    CHECK(g_reads > reads, "a retry at 1000");
    reads = g_reads;
    tick(1999);
    CHECK(g_reads == reads, "no retry 999 ms after the last one");
    tick(2000);
    CHECK(g_reads > reads, "a retry 1000 ms after the last one");
    reads = g_reads;
    tick(500);
    CHECK(g_reads == reads, "a clock that went back retries nothing");
    tick(1500);
    CHECK(g_reads > reads, "and counts from the new time");
}

static void test_priority_and_order(void)
{
    reset();
    flip("alpha", 3);
    blind_witness("charlie", 1000000);
    start(0);
    CHECK(is(FEAT_HUD_READ, ADMIT_PENDING, "witness alpha differs (retrying)"), "two pending witnesses: the first one's reason");
    CHECK(is(FEAT_POINTING, ADMIT_PENDING, "witness charlie not readable yet"), "a feature sees only its own witnesses");
    tick(31000);
    CHECK(is(FEAT_HUD_READ, ADMIT_REFUSED, "witness alpha differs"), "refused beats pending");
    CHECK(is(FEAT_POINTING, ADMIT_PENDING, "witness charlie not readable yet"), "the pending witness stays pending");

    reset();
    flip("charlie", 70);
    blind_witness("alpha", 1000000);
    start(0);
    tick(31000);
    CHECK(is(FEAT_HUD_READ, ADMIT_REFUSED, "witness charlie differs"), "refused beats pending even when the pending witness comes first");
    CHECK(is(FEAT_STATE, ADMIT_PENDING, "witness alpha not readable yet"), "the first witness' other feature is pending");
}

static void test_rewrites(void)
{
    const DbfWitness* bravo = wit("bravo");
    reset();
    flip("bravo", 2);
    g_rw_lo = bravo->rva + 2;
    g_rw_hi = g_rw_lo + 1;
    start(0);
    CHECK(is(FEAT_STRATAGEMS, ADMIT_OK, ""), "a changed byte that HellForge may rewrite is not compared: ok at once");
    CHECK(g_rw_calls > 0 && g_rw_misuse == 0, "rewrites is asked about single bytes");

    reset();
    flip("bravo", 2);
    flip("bravo", 5);
    g_rw_lo = bravo->rva + 2;
    g_rw_hi = g_rw_lo + 1;
    start(0);
    CHECK(is(FEAT_STRATAGEMS, ADMIT_PENDING, "witness bravo differs (retrying)"), "a changed byte beyond the rewritten one still differs");

    reset();
    flip("bravo", 2);
    g_rw_lo = bravo->rva + 3;
    g_rw_hi = g_rw_lo + 1;
    start(0);
    CHECK(is(FEAT_STRATAGEMS, ADMIT_PENDING, "witness bravo differs (retrying)"), "only the reported bytes are masked");

    reset();
    flip("bravo", 2);
    adm_init(&PORT_NO_REWRITES, 0);
    CHECK(is(FEAT_STRATAGEMS, ADMIT_PENDING, "witness bravo differs (retrying)"), "a port without rewrites masks nothing");
    reset();
    adm_init(&PORT_NO_REWRITES, 0);
    CHECK(is(FEAT_STRATAGEMS, ADMIT_OK, "") && g_rw_calls == 0, "and matching bytes need no rewrites");

    reset();
    flip("charlie", 80);
    g_rw_lo = wit("charlie")->rva + 80;
    g_rw_hi = g_rw_lo + 1;
    start(0);
    CHECK(is(FEAT_POINTING, ADMIT_OK, ""), "a masked byte in the second read chunk is ignored too");
}

static void test_chunks(void)
{
    static const unsigned POSITIONS[] = { 0, 1, 62, 63, 64, 65, 98, 99 };
    int found = 0;
    for (size_t i = 0; i < sizeof POSITIONS / sizeof POSITIONS[0]; i++) {
        reset();
        flip("charlie", POSITIONS[i]);
        start(0);
        found += is(FEAT_POINTING, ADMIT_PENDING, "witness charlie differs (retrying)");
    }
    CHECK(found == 8, "a changed byte is found at either end of a witness and on both sides of the 64-byte read chunk");
}

static void test_restart(void)
{
    reset();
    put32(g_game + LFANEW + 8, 0x6AE0E5FFu);
    start(0);
    CHECK(all_are(ADMIT_REFUSED, "build 6ae0e5ff is not 25480438"), "a wrong build refuses everything");
    put32(g_game + LFANEW + 8, GAME_STAMP);
    start(100);
    CHECK(adm_build_ok(NULL) && is(FEAT_STATE, ADMIT_OK, ""), "adm_init again forgets a refusal");
    flip("alpha", 3);
    start(200);
    CHECK(is(FEAT_STATE, ADMIT_PENDING, "witness alpha differs (retrying)"), "adm_init again re-reads matched witnesses");
}

static void test_bad_arguments(void)
{
    static const AdmPort NO_READ = { fake_module_base, NULL, NULL };
    static const AdmPort NO_MODULES = { NULL, fake_read_code, NULL };
    const char* r = NULL;
    reset();
    CHECK(adm_feature((Feature)FEAT_COUNT, &r) == ADMIT_REFUSED && !strcmp(r, "unknown feature"), "FEAT_COUNT is not a feature");
    CHECK(adm_feature((Feature)-1, &r) == ADMIT_REFUSED && !strcmp(r, "unknown feature"), "a negative feature is refused");
    adm_init(NULL, 0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "no code access") && all_are(ADMIT_REFUSED, "no code access"), "adm_init without a port refuses everything");
    adm_init(&NO_READ, 0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "no code access"), "a port without read_code refuses everything");
    adm_init(&NO_MODULES, 0);
    CHECK(!adm_build_ok(&r) && !strcmp(r, "no code access"), "a port without module_base refuses everything");
    tick(5000);
    CHECK(all_are(ADMIT_REFUSED, "no code access"), "and a tick changes nothing");
}

static void test_names(void)
{
    static const char* const EXPECT[] = { "Selection state", "Stratagems", "HUD reads",        "List fade",       "Code entry",
                                          "Scrambled codes", "Wheel pointing", "Camera hold", "Select on Release", "Sounds",
                                          "Cooldown display", "Weapon strip", "Terminals" };
    int same = 1, distinct = 1;
    _Static_assert(sizeof EXPECT / sizeof EXPECT[0] == FEAT_COUNT, "one expected name per feature");
    for (int f = 0; f < FEAT_COUNT; f++) {
        same &= strcmp(adm_feature_name((Feature)f), EXPECT[f]) == 0;
        for (int g = 0; g < f; g++) distinct &= strcmp(adm_feature_name((Feature)f), adm_feature_name((Feature)g)) != 0;
    }
    CHECK(same, "every feature has its player-facing name");
    CHECK(distinct, "no two features share a name");
    CHECK(!strcmp(adm_feature_name((Feature)FEAT_COUNT), "Unknown") && !strcmp(adm_feature_name((Feature)-1), "Unknown"),
          "a feature out of range is Unknown");
}

int main(void)
{
    test_before_init();
    test_table_is_the_test_table();
    test_all_match();
    test_wrong_build();
    test_modules();
    test_one_witness_differs();
    test_grace();
    test_unreadable();
    test_retry_cadence();
    test_priority_and_order();
    test_rewrites();
    test_chunks();
    test_restart();
    test_bad_arguments();
    test_names();
    TEST_MAIN_END
}
