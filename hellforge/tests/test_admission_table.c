/* Tests for src/admission.c with the generated witness table (no test table): the table is sound, and admission over a
 * game that serves exactly the table's bytes admits every feature the table maps. The synthetic game is only a header and
 * the witness spans themselves; test_admission.c covers the rules with a small table of its own. */
#include <stdint.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "test.h"

#define GAME_BASE ((uintptr_t)0x140000000ull)
#define EXE_BASE ((uintptr_t)0x200000000ull)
#define HEADER_SIZE 0x1000u /* below every witness */
#define LFANEW 0x80u

static uint8_t g_game_header[HEADER_SIZE];
static uint8_t g_exe_header[HEADER_SIZE];
static int g_tamper;         /* flip the byte of game.dll at g_tamper_rva in everything read */
static uint32_t g_tamper_rva;

static void put32(uint8_t* p, uint32_t v)
{
    for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * i));
}

static void put_header(uint8_t* image, uint32_t stamp)
{
    memset(image, 0, HEADER_SIZE);
    image[0] = 'M';
    image[1] = 'Z';
    put32(image + 0x3c, LFANEW);
    memcpy(image + LFANEW, "PE\0\0", 4);
    put32(image + LFANEW + 8, stamp);
}

static uintptr_t fake_module_base(const char* module, size_t* size)
{
    if (size) *size = 0x3000000u;
    if (!strcmp(module, "game.dll")) return GAME_BASE;
    if (!strcmp(module, "helldivers2.exe")) return EXE_BASE;
    return 0;
}

static int fake_read_code(uintptr_t address, void* out, size_t size)
{
    if (address >= EXE_BASE && address - EXE_BASE < HEADER_SIZE && size <= HEADER_SIZE - (address - EXE_BASE)) {
        memcpy(out, g_exe_header + (address - EXE_BASE), size);
        return 0;
    }
    if (address < GAME_BASE) return -1;
    uintptr_t rva = address - GAME_BASE;
    if (rva < HEADER_SIZE) {
        if (size > HEADER_SIZE - rva) return -1;
        memcpy(out, g_game_header + rva, size);
        return 0;
    }
    for (int i = 0; i < dbf_witness_count; i++) {
        const DbfWitness* w = &dbf_witnesses[i];
        if (rva >= w->rva && rva - w->rva <= (uintptr_t)w->size && size <= w->size - (rva - w->rva)) {
            memcpy(out, w->bytes + (rva - w->rva), size);
            if (g_tamper && g_tamper_rva >= rva && g_tamper_rva - rva < size) ((uint8_t*)out)[g_tamper_rva - rva] ^= 0xff;
            return 0;
        }
    }
    return -1;
}

static const AdmPort PORT = { fake_module_base, fake_read_code, NULL };

static void start(void)
{
    put_header(g_game_header, 0x6AB3B43Fu);
    put_header(g_exe_header, 0x6AB382E4u);
    adm_init(&PORT, 0);
}

static int is(Feature f, Admit want, const char* reason)
{
    const char* got = NULL;
    Admit admit = adm_feature(f, &got);
    return admit == want && got != NULL && (reason == NULL || strcmp(got, reason) == 0);
}

static uint32_t mapped_mask(void)
{
    uint32_t mask = 0;
    for (int i = 0; i < dbf_witness_count; i++) mask |= dbf_witnesses[i].features;
    return mask;
}

static void test_table_is_sound(void)
{
    int sound = 1, unique = 1;
    for (int i = 0; i < dbf_witness_count; i++) {
        const DbfWitness* w = &dbf_witnesses[i];
        sound &= w->name != NULL && w->name[0] != '\0' && w->size > 0 && w->bytes != NULL && w->features != 0 &&
                 (w->features >> DBF_FEATURE_COUNT) == 0 && w->rva >= HEADER_SIZE;
        for (int j = 0; j < i; j++) unique &= strcmp(w->name, dbf_witnesses[j].name) != 0;
    }
    CHECK(dbf_witness_count > 0 && sound, "every witness has a name, bytes, a size, an rva above the header and known features");
    CHECK(unique, "witness names are unique");
    CHECK((mapped_mask() & ((1u << DBF_FEATURE_WEAPON) | (1u << DBF_FEATURE_TERMINAL))) == 0,
          "no witness maps the weapon strip or the terminals yet");
    CHECK(mapped_mask() == (((1u << DBF_FEATURE_COUNT) - 1u) & ~((1u << DBF_FEATURE_WEAPON) | (1u << DBF_FEATURE_TERMINAL))),
          "every other feature has at least one witness");
}

static void test_table_admits(void)
{
    const char* r = NULL;
    int ok = 1;
    g_tamper = 0;
    start();
    CHECK(adm_build_ok(&r) && r != NULL && r[0] == '\0', "the stamps of build 25480438 are accepted");
    for (int f = 0; f < FEAT_COUNT; f++) {
        if (mapped_mask() & (1u << f)) ok &= is((Feature)f, ADMIT_OK, "");
        else ok &= is((Feature)f, ADMIT_REFUSED, "not mapped yet");
    }
    CHECK(ok, "a game that holds the table's bytes: every mapped feature ok, the others not mapped yet");
    CHECK(is(FEAT_WEAPON, ADMIT_REFUSED, "not mapped yet") && is(FEAT_TERMINAL, ADMIT_REFUSED, "not mapped yet"),
          "the weapon strip and the terminals are refused: not mapped yet");
}

/* One byte of the game differs, at the first byte of each witness in turn: exactly the features of the witnesses covering
 * that byte are refused (witnesses can overlap), and the rest are as before. */
static void test_each_witness_gates_its_features(void)
{
    int right = 1;
    for (int i = 0; i < dbf_witness_count; i++) {
        uint32_t bad = 0;
        g_tamper = 1;
        g_tamper_rva = dbf_witnesses[i].rva;
        for (int j = 0; j < dbf_witness_count; j++) {
            const DbfWitness* w = &dbf_witnesses[j];
            if (g_tamper_rva >= w->rva && g_tamper_rva - w->rva < w->size) bad |= w->features;
        }
        start();
        adm_tick(31000);
        for (int f = 0; f < FEAT_COUNT; f++) {
            const char* reason = NULL;
            Admit admit = adm_feature((Feature)f, &reason);
            if (bad & (1u << f)) {
                size_t n = strlen(reason);
                right &= admit == ADMIT_REFUSED && !strncmp(reason, "witness ", 8) && n > 8 + 8 && !strcmp(reason + n - 8, " differs");
            } else if (mapped_mask() & (1u << f)) {
                right &= admit == ADMIT_OK;
            } else {
                right &= admit == ADMIT_REFUSED && !strcmp(reason, "not mapped yet");
            }
        }
    }
    g_tamper = 0;
    CHECK(right, "a changed byte in any witness refuses exactly that witness' features");
}

int main(void)
{
    test_table_is_sound();
    test_table_admits();
    test_each_witness_gates_its_features();
    TEST_MAIN_END
}
