/* Tests for src/native.c: the six game functions behind a NativePort, with a fake port that records, in order, every
 * checkpoint line the wrappers log and every call they make. Admission runs for real over the synthetic 25480438 image of
 * tests/synthetic.c with the generated witness table (the image serves exactly the table's bytes, so every feature is
 * admitted); a test refuses or delays a feature by changing a byte of one of its witnesses. The audio and effects objects
 * the wrappers read are not part of the synthetic scene: start() pokes them in at the numbers R46 reads (native.lua:325-332,
 * input.lua:153), spelled out here on purpose and not with the generated header's names, so the tests check the address
 * table as well as the wrappers. native.c keeps state in statics, so every test starts with start(); test_before_init must
 * run first, while nothing has been started. */
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "memory.h"
#include "native.h"
#include "synthetic.h"
#include "test.h"

#define GRACE_OVER 30000u

/* game.dll globals and offsets (R46 native.lua:325-332, input.lua:153). */
#define RVA_AUDIO 0x3326318u
#define RVA_GAME_STATE 0x3326340u
#define RVA_EFFECTS 0x33264b0u
#define OFF_ENGINE_CALL 0x288u
#define OFF_ENGINE_TAIL 0x338u
#define OFF_GAME_AUDIO 0x10f8u

/* The fake audio and effects objects: user space, 8-aligned, far apart. */
#define AT_ENGINE ((uintptr_t)0x2c000000000ull)
#define AT_ENGINE_CALL ((uintptr_t)0x2c100000000ull)
#define AT_ENGINE_TAIL ((uintptr_t)0x2c200000000ull)
#define AT_GAME_AUDIO ((uintptr_t)0x2c300000000ull)
#define AT_EFFECTS ((uintptr_t)0x2d000000000ull)

#define COMPONENT ((uintptr_t)0x2e0000040ull)
#define WEAPON ((uintptr_t)0x2e0000a80ull)

/* --- the fake port --------------------------------------------------------------------------------------------- */

#define MAX_EVENTS 16
static char g_events[MAX_EVENTS][200]; /* "log: <line>" and "call: <function> <arguments>", in the order they happened */
static int g_event_count;              /* counted past MAX_EVENTS too */

static uint8_t g_open_returns;
static bool g_scramble_writes;         /* fake_scramble_query writes g_scramble_answer to *out */
static uint32_t g_scramble_answer;
static uint32_t g_out_on_entry;        /* *out as the game saw it */
static uintptr_t g_scramble_a5, g_scramble_a6;

static void event(const char* format, ...)
{
    va_list args;
    if (g_event_count < MAX_EVENTS) {
        va_start(args, format);
        vsnprintf(g_events[g_event_count], sizeof g_events[0], format, args);
        va_end(args);
    }
    g_event_count++;
}

static void fake_log(const char* line) { event("log: %s", line); }
static void fake_input_handler(uintptr_t component) { event("call: input_handler 0x%llx", (unsigned long long)component); }
static uint8_t fake_open_input(uintptr_t component)
{
    event("call: open_input 0x%llx", (unsigned long long)component);
    return g_open_returns;
}
static void fake_close_input(uintptr_t component) { event("call: close_input 0x%llx", (unsigned long long)component); }
static void fake_request_slot(uintptr_t weapon, uint32_t slot)
{
    event("call: request_slot 0x%llx 0x%x", (unsigned long long)weapon, (unsigned)slot);
}
static void fake_ui_sound(uintptr_t unused, uint32_t id)
{
    event("call: ui_sound 0x%llx 0x%x", (unsigned long long)unused, (unsigned)id);
}
static uintptr_t fake_scramble_query(uintptr_t effects, uint32_t* out, uint32_t key, uint32_t kind, uintptr_t a5, uintptr_t a6)
{
    event("call: scramble_query 0x%llx out 0x%x 0x%x", (unsigned long long)effects, (unsigned)key, (unsigned)kind);
    g_out_on_entry = *out;
    g_scramble_a5 = a5;
    g_scramble_a6 = a6;
    if (g_scramble_writes) *out = g_scramble_answer;
    return 0x1234; /* not used by the wrapper */
}

/* The port without a clock (now_ms NULL: every call logs), as an initialiser written before now_ms existed. */
static const NativePort PORT = { fake_input_handler, fake_open_input, fake_close_input, fake_request_slot,
                                 fake_ui_sound, fake_scramble_query, fake_log };

static uint64_t g_now;
static uint64_t fake_now(void) { return g_now; }

/* The same port with a millisecond clock. */
static const NativePort CLOCKED = { fake_input_handler, fake_open_input, fake_close_input, fake_request_slot,
                                    fake_ui_sound, fake_scramble_query, fake_log, fake_now };

/* --- helpers --------------------------------------------------------------------------------------------------- */

static void poke_audio(void)
{
    syn_poke_u64(SYN_GAME_BASE + RVA_AUDIO, AT_ENGINE);
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_CALL, AT_ENGINE_CALL);
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_TAIL, AT_ENGINE_TAIL);
    syn_poke_u64(syn_game_state() + OFF_GAME_AUDIO, AT_GAME_AUDIO);
    syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, AT_EFFECTS);
}

/* A fresh game with every feature admitted, the audio and effects objects in place, and the native layer started on `port`
 * with the game.dll base set. */
static void start(const NativePort* port)
{
    SynScene s;
    syn_default(&s);
    syn_build(&s);
    mem_init(syn_mem_port());
    adm_init(syn_adm_port(), 0);
    poke_audio();
    native_init(port);
    native_set_base(SYN_GAME_BASE);
    g_event_count = 0;
    g_open_returns = 1;
    g_scramble_writes = false;
    g_scramble_answer = 0;
    g_out_on_entry = 0;
    g_scramble_a5 = g_scramble_a6 = 0xdead;
}

static const DbfWitness* witness(const char* name)
{
    for (int i = 0; i < dbf_witness_count; i++)
        if (strcmp(dbf_witnesses[i].name, name) == 0) return &dbf_witnesses[i];
    return NULL;
}

/* Changes a byte of the witness and restarts admission, past the grace period or not: its features are then refused, or
 * pending. */
static void spoil_witness(const char* name, bool past_grace)
{
    const DbfWitness* w = witness(name);
    if (!w) return;
    syn_poke_u8(SYN_GAME_BASE + w->rva, (uint8_t)(w->bytes[0] ^ 0x55u));
    adm_init(syn_adm_port(), 0);
    if (past_grace) adm_tick(GRACE_OVER);
}

static void restore_witness(const char* name)
{
    const DbfWitness* w = witness(name);
    if (w) syn_poke_u8(SYN_GAME_BASE + w->rva, w->bytes[0]);
}

/* The events so far are exactly the `count` strings that follow. */
static bool events_are(int count, ...)
{
    va_list args;
    bool same = g_event_count == count;
    va_start(args, count);
    for (int i = 0; i < count; i++) {
        const char* want = va_arg(args, const char*);
        if (i < g_event_count && i < MAX_EVENTS && strcmp(g_events[i], want) != 0) same = false;
    }
    va_end(args);
    if (!same) {
        printf("  events were (%d):\n", g_event_count);
        for (int i = 0; i < g_event_count && i < MAX_EVENTS; i++) printf("    %s\n", g_events[i]);
    }
    return same;
}

static bool no_events(void) { return events_are(0); }

/* All six wrappers once, with their results in `ok` (input handler, open, close, slot, sound, scramble). */
static void call_all(bool ok[6])
{
    uint8_t byte = 0;
    uint32_t answer = 0;
    ok[0] = nat_input_handler(COMPONENT);
    ok[1] = nat_open_input(COMPONENT, &byte);
    ok[2] = nat_close_input(COMPONENT);
    ok[3] = nat_request_slot(WEAPON, 5);
    ok[4] = nat_ui_sound(0x39425a55u);
    ok[5] = nat_scramble_query(0x11u, 0x22u, &answer);
}

static bool results_are(const bool ok[6], bool a, bool b, bool c, bool d, bool e, bool f)
{
    bool same = ok[0] == a && ok[1] == b && ok[2] == c && ok[3] == d && ok[4] == e && ok[5] == f;
    if (!same)
        printf("  results were %d %d %d %d %d %d, expected %d %d %d %d %d %d\n", ok[0], ok[1], ok[2], ok[3], ok[4], ok[5], a, b,
               c, d, e, f);
    return same;
}

static bool event_is(int index, const char* text)
{
    if (index < g_event_count && index < MAX_EVENTS && strcmp(g_events[index], text) == 0) return true;
    printf("  event %d was \"%s\", expected \"%s\"\n", index, index < g_event_count && index < MAX_EVENTS ? g_events[index] : "(none)",
           text);
    return false;
}

static bool event_has(int index, const char* part)
{
    return index < g_event_count && index < MAX_EVENTS && strstr(g_events[index], part) != NULL;
}

/* --- tests ----------------------------------------------------------------------------------------------------- */

static void test_before_init(void)
{
    bool ok[6];
    uint8_t byte = 0x77;
    uint32_t answer = 0x1234;
    call_all(ok);
    CHECK(results_are(ok, false, false, false, false, false, false), "before native_init: every wrapper returns false");
    CHECK(!nat_open_input(COMPONENT, &byte) && byte == 0x77, "before native_init: nat_open_input leaves *result alone");
    CHECK(!nat_scramble_query(1, 2, &answer) && answer == 0x1234, "before native_init: nat_scramble_query leaves *out alone");
    native_init(NULL);
    native_set_base(SYN_GAME_BASE);
    call_all(ok);
    CHECK(results_are(ok, false, false, false, false, false, false), "native_init(NULL): every wrapper returns false");
}

static void test_synthetic_admits_the_features(void)
{
    start(&PORT);
    CHECK(adm_feature(FEAT_ENTRY, NULL) == ADMIT_OK && adm_feature(FEAT_LATCH, NULL) == ADMIT_OK
              && adm_feature(FEAT_SOUND, NULL) == ADMIT_OK && adm_feature(FEAT_SCRAMBLE, NULL) == ADMIT_OK,
          "the synthetic game admits ENTRY, LATCH, SOUND and SCRAMBLE");
}

static void test_calls_after_a_checkpoint(void)
{
    bool ok[6];
    uint8_t byte = 0;
    uint32_t answer = 0;
    start(&PORT);
    CHECK(nat_input_handler(COMPONENT) && events_are(2, "log: call input_handler(0x2e0000040)", "call: input_handler 0x2e0000040"),
          "nat_input_handler: one checkpoint line, then the call, true");
    g_event_count = 0;
    CHECK(nat_open_input(COMPONENT, &byte) && events_are(2, "log: call open_input(0x2e0000040)", "call: open_input 0x2e0000040"),
          "nat_open_input: one checkpoint line, then the call, true");
    g_event_count = 0;
    CHECK(nat_close_input(COMPONENT) && events_are(2, "log: call close_input(0x2e0000040)", "call: close_input 0x2e0000040"),
          "nat_close_input: one checkpoint line, then the call, true");
    g_event_count = 0;
    CHECK(nat_request_slot(WEAPON, 5)
              && events_are(2, "log: call request_slot(0x2e0000a80, 0x5)", "call: request_slot 0x2e0000a80 0x5"),
          "nat_request_slot: one checkpoint line with both arguments, then the call, true");
    g_event_count = 0;
    CHECK(nat_ui_sound(0x39425a55u) && events_are(2, "log: call ui_sound(0x39425a55)", "call: ui_sound 0x0 0x39425a55"),
          "nat_ui_sound: one checkpoint line, then ui_sound(0, id), true");
    g_event_count = 0;
    CHECK(nat_scramble_query(0xdeadbeefu, 7, &answer)
              && events_are(2, "log: call scramble_query(0x2d000000000, 0xdeadbeef, 0x7)",
                            "call: scramble_query 0x2d000000000 out 0xdeadbeef 0x7"),
          "nat_scramble_query: one checkpoint line with effects, key and kind, then the call, true");
    start(&PORT);
    call_all(ok);
    CHECK(results_are(ok, true, true, true, true, true, true) && g_event_count == 12,
          "all six wrappers call when all four features are admitted: six lines and six calls");
    {
        bool alternating = true;
        for (int i = 0; i < 12 && i < MAX_EVENTS; i++)
            if (strncmp(g_events[i], i % 2 == 0 ? "log: call " : "call: ", i % 2 == 0 ? 10 : 6) != 0) alternating = false;
        CHECK(alternating, "every call is preceded by its own checkpoint line");
    }
}

static void test_checkpoint_hex(void)
{
    uint32_t answer = 0;
    start(&PORT);
    CHECK(nat_input_handler(0) && event_is(0, "log: call input_handler(0x0)"), "a zero argument is 0x0");
    g_event_count = 0;
    CHECK(nat_input_handler((uintptr_t)0x7ffffffffff8ull) && event_is(0, "log: call input_handler(0x7ffffffffff8)"),
          "a 47-bit pointer is its hex digits, lowercase, without leading zeros");
    g_event_count = 0;
    CHECK(nat_request_slot(0, 0xffffffffu) && event_is(0, "log: call request_slot(0x0, 0xffffffff)"),
          "slot 0xffffffff on a null weapon: both in hex");
    g_event_count = 0;
    CHECK(nat_scramble_query(0, 0, &answer) && event_is(0, "log: call scramble_query(0x2d000000000, 0x0, 0x0)"),
          "key 0 and kind 0 are logged as 0x0");
}

static void test_open_input_result(void)
{
    uint8_t byte = 0x55;
    start(&PORT);
    g_open_returns = 1;
    CHECK(nat_open_input(COMPONENT, &byte) && byte == 1, "nat_open_input stores the returned byte (1)");
    g_open_returns = 0;
    CHECK(nat_open_input(COMPONENT, &byte) && byte == 0, "nat_open_input stores the returned byte (0)");
    g_open_returns = 0xfe;
    CHECK(nat_open_input(COMPONENT, &byte) && byte == 0xfe, "nat_open_input stores any returned byte (0xfe)");
    g_event_count = 0;
    byte = 0x55;
    CHECK(!nat_open_input(COMPONENT, NULL) && no_events(), "nat_open_input(NULL result): false, nothing called, nothing logged");
    CHECK(byte == 0x55, "the byte is left alone");
}

/* Refuses one witness and checks which wrappers still work. A refused or pending feature calls nothing and logs nothing. */
static void check_gate(const char* witness_name, bool past_grace, const char* what, bool entry, bool latch, bool sound,
                       bool scramble)
{
    bool ok[6];
    char text[160];
    start(&PORT);
    spoil_witness(witness_name, past_grace);
    call_all(ok);
    snprintf(text, sizeof text, "%s: input handler %s, open/close/slot %s, sound %s, scramble %s", what,
             entry ? "called" : "refused", latch ? "called" : "refused", sound ? "called" : "refused",
             scramble ? "called" : "refused");
    CHECK(results_are(ok, entry, latch, latch, latch, sound, scramble), text);
    CHECK(g_event_count == 2 * ((entry ? 1 : 0) + (latch ? 3 : 0) + (sound ? 1 : 0) + (scramble ? 1 : 0)),
          "  and only the admitted ones logged and called");
}

static void test_feature_gates(void)
{
    /* input_handler gates ENTRY only; wheel_action_sound gates LATCH and SOUND; ui_sound SOUND only; scramble_query SCRAMBLE
     * only (the tables of addresses_25480438.h). */
    check_gate("input_handler", true, "ENTRY refused", false, true, true, true);
    check_gate("wheel_action_sound", true, "LATCH and SOUND refused", true, false, false, true);
    check_gate("ui_sound", true, "SOUND refused", true, true, false, true);
    check_gate("scramble_query", true, "SCRAMBLE refused", true, true, true, false);
    check_gate("release_close", true, "ENTRY and LATCH refused", false, false, true, true);
    check_gate("input_handler", false, "ENTRY pending (witness differs, grace not over)", false, true, true, true);
    check_gate("ui_sound", false, "SOUND pending", true, true, false, true);
}

static void test_a_pending_feature_recovers(void)
{
    start(&PORT);
    spoil_witness("ui_sound", false);
    CHECK(!nat_ui_sound(0x39425a55u) && no_events(), "SOUND pending: nothing called");
    restore_witness("ui_sound");
    adm_tick(2000);
    CHECK(nat_ui_sound(0x39425a55u) && g_event_count == 2, "after the witness matches again and admission retried: called");
}

static void test_missing_functions(void)
{
    bool ok[6];
    NativePort partial;
    start(&PORT);
    partial = PORT;
    partial.input_handler = NULL;
    native_init(&partial);
    native_set_base(SYN_GAME_BASE);
    call_all(ok);
    CHECK(results_are(ok, false, true, true, true, true, true), "a NULL input_handler: only that wrapper returns false");
    CHECK(g_event_count == 10, "  and logged nothing for it");
    partial = PORT;
    partial.open_input = NULL;
    native_init(&partial);
    native_set_base(SYN_GAME_BASE);
    g_event_count = 0;
    call_all(ok);
    CHECK(results_are(ok, true, false, true, true, true, true) && g_event_count == 10, "a NULL open_input: only that one");
    partial = PORT;
    partial.close_input = NULL;
    native_init(&partial);
    native_set_base(SYN_GAME_BASE);
    g_event_count = 0;
    call_all(ok);
    CHECK(results_are(ok, true, true, false, true, true, true) && g_event_count == 10, "a NULL close_input: only that one");
    partial = PORT;
    partial.request_slot = NULL;
    native_init(&partial);
    native_set_base(SYN_GAME_BASE);
    g_event_count = 0;
    call_all(ok);
    CHECK(results_are(ok, true, true, true, false, true, true) && g_event_count == 10, "a NULL request_slot: only that one");
    partial = PORT;
    partial.ui_sound = NULL;
    native_init(&partial);
    native_set_base(SYN_GAME_BASE);
    g_event_count = 0;
    call_all(ok);
    CHECK(results_are(ok, true, true, true, true, false, true) && g_event_count == 10, "a NULL ui_sound: only that one");
    partial = PORT;
    partial.scramble_query = NULL;
    native_init(&partial);
    native_set_base(SYN_GAME_BASE);
    g_event_count = 0;
    call_all(ok);
    CHECK(results_are(ok, true, true, true, true, true, false) && g_event_count == 10, "a NULL scramble_query: only that one");
    memset(&partial, 0, sizeof partial);
    native_init(&partial);
    native_set_base(SYN_GAME_BASE);
    g_event_count = 0;
    call_all(ok);
    CHECK(results_are(ok, false, false, false, false, false, false) && no_events(), "an empty port: nothing, silently");
}

static void test_no_log_function(void)
{
    bool ok[6];
    NativePort quiet;
    start(&PORT);
    quiet = PORT;
    quiet.log = NULL;
    native_init(&quiet);
    native_set_base(SYN_GAME_BASE);
    call_all(ok);
    CHECK(results_are(ok, true, true, true, true, true, true) && g_event_count == 6,
          "a port without log: every wrapper still calls (six calls, no lines)");
    CHECK(event_has(0, "call: input_handler") && event_has(5, "call: scramble_query"), "  and in order");
    poke_audio();
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_CALL, 0);
    g_event_count = 0;
    CHECK(!nat_ui_sound(1) && no_events(), "a port without log: a sound skipped is still false, with nothing to log");
}

static void test_sound_preconditions(void)
{
    start(&PORT);
    CHECK(nat_ui_sound(0xdd274583u) && event_is(0, "log: call ui_sound(0xdd274583)") && event_is(1, "call: ui_sound 0x0 0xdd274583"),
          "all five audio pointers present: the confirm sound is played");

    start(&PORT);
    syn_poke_u64(SYN_GAME_BASE + RVA_AUDIO, 0);
    CHECK(!nat_ui_sound(1) && g_event_count == 1 && event_is(0, "log: sound skipped: audio engine (game.dll+0x3326318)"),
          "no audio engine: false, the sound is not called, one \"sound skipped\" line names the pointer");

    start(&PORT);
    syn_poke_u64(SYN_GAME_BASE + RVA_GAME_STATE, 0);
    CHECK(!nat_ui_sound(1) && g_event_count == 1 && event_is(0, "log: sound skipped: game state (game.dll+0x3326340)"),
          "no game state: false, named");

    start(&PORT);
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_CALL, 0);
    CHECK(!nat_ui_sound(1) && g_event_count == 1 && event_is(0, "log: sound skipped: audio call pointer (engine+0x288)"),
          "no *(engine+0x288): false, named");

    start(&PORT);
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_TAIL, 0);
    CHECK(!nat_ui_sound(1) && g_event_count == 1 && event_is(0, "log: sound skipped: audio tail-call pointer (engine+0x338)"),
          "no *(engine+0x338): false, named");

    start(&PORT);
    syn_poke_u64(syn_game_state() + OFF_GAME_AUDIO, 0);
    CHECK(!nat_ui_sound(1) && g_event_count == 1 && event_is(0, "log: sound skipped: game audio pointer (game+0x10f8)"),
          "no *(game+0x10f8): false, named");

    start(&PORT);
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_CALL, AT_ENGINE_CALL + 4);
    CHECK(!nat_ui_sound(1) && g_event_count == 1 && event_has(0, "engine+0x288"), "a pointer that is not 8-aligned counts as missing");

    start(&PORT);
    syn_poke_u64(SYN_GAME_BASE + RVA_AUDIO, 0x1234);
    CHECK(!nat_ui_sound(1) && g_event_count == 1 && event_has(0, "audio engine"), "an implausible pointer (0x1234) counts as missing");

    start(&PORT);
    syn_unmap(syn_game_state() + OFF_GAME_AUDIO);
    CHECK(!nat_ui_sound(1) && g_event_count == 1 && event_has(0, "game+0x10f8"), "a pointer that cannot be read counts as missing");

    start(&PORT);
    syn_unmap(AT_ENGINE);
    CHECK(!nat_ui_sound(1) && g_event_count == 1 && event_has(0, "engine+0x288"), "an engine that cannot be read: its first pointer is missing");
}

static void test_sound_skip_logged_once(void)
{
    start(&PORT);
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_CALL, 0);
    CHECK(!nat_ui_sound(1) && g_event_count == 1, "the first skipped sound logs a line");
    CHECK(!nat_ui_sound(2) && !nat_ui_sound(3) && g_event_count == 1, "the same gap again: no further line");
    syn_poke_u64(SYN_GAME_BASE + RVA_AUDIO, 0);
    CHECK(!nat_ui_sound(4) && g_event_count == 1, "another gap later: still one line for the session");
    poke_audio();
    CHECK(nat_ui_sound(5) && g_event_count == 3 && event_is(1, "log: call ui_sound(0x5)") && event_is(2, "call: ui_sound 0x0 0x5"),
          "when the pointers are back the sound is played and logged as usual");
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_TAIL, 0);
    g_event_count = 0;
    CHECK(!nat_ui_sound(6) && no_events(), "and a later gap in the same session is not logged again");
    native_init(&PORT);
    native_set_base(SYN_GAME_BASE);
    CHECK(!nat_ui_sound(7) && g_event_count == 1 && event_has(0, "sound skipped: audio tail-call pointer"),
          "a new session (native_init) logs its first skipped sound again");
}

static void test_sound_not_admitted_logs_nothing(void)
{
    start(&PORT);
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_CALL, 0);
    spoil_witness("ui_sound", true);
    CHECK(!nat_ui_sound(1) && no_events(), "SOUND refused and the audio missing: false, not even a \"sound skipped\" line");
    restore_witness("ui_sound");
    adm_init(syn_adm_port(), 0);
    CHECK(!nat_ui_sound(1) && g_event_count == 1, "  and once admitted the first skip is logged (the refusal did not use it up)");
}

static void test_no_base(void)
{
    uint32_t answer = 0x4321;
    start(&PORT);
    native_init(&PORT); /* forgets the base */
    CHECK(!nat_ui_sound(1) && events_are(1, "log: native: game.dll base not set"),
          "no game.dll base: the sound is not called, one line \"native: game.dll base not set\"");
    g_event_count = 0;
    CHECK(!nat_ui_sound(2) && no_events(), "  logged once a session");
    CHECK(!nat_scramble_query(1, 2, &answer) && events_are(1, "log: scramble query skipped: no base") && answer == 0x4321,
          "no game.dll base: no scramble query, one line \"scramble query skipped: no base\"");
    g_event_count = 0;
    CHECK(!nat_scramble_query(1, 2, &answer) && no_events(), "  logged once a session");
    CHECK(nat_input_handler(COMPONENT) && g_event_count == 2, "  the wrappers that read no global do not need the base");
    native_set_base(SYN_GAME_BASE);
    g_event_count = 0;
    CHECK(nat_scramble_query(1, 2, &answer) && g_event_count == 2, "native_set_base makes the global readers work");
    syn_poke_u64(AT_ENGINE + OFF_ENGINE_CALL, 0);
    g_event_count = 0;
    CHECK(!nat_ui_sound(3) && events_are(1, "log: sound skipped: audio call pointer (engine+0x288)"),
          "the base line did not use up the session's \"sound skipped\" line");
    native_set_base(0);
    g_event_count = 0;
    CHECK(!nat_scramble_query(1, 2, &answer) && no_events(), "native_set_base(0) takes the base away again (already logged)");
}

/* The per-tick calls (the scramble query, the UI sound) log their checkpoint on their first call of the session and
 * then at most once per 1000 ms each; the calls themselves are always made. The user-triggered calls log every time. */
static void test_per_tick_checkpoints_throttled(void)
{
    uint32_t answer = 0;
    start(&CLOCKED);
    g_now = 5000;
    CHECK(nat_scramble_query(1, 2, &answer) && events_are(2, "log: call scramble_query(0x2d000000000, 0x1, 0x2)",
                                                          "call: scramble_query 0x2d000000000 out 0x1 0x2"),
          "the session's first scramble query: checkpoint, then the call");
    g_event_count = 0;
    g_now = 5999;
    CHECK(nat_scramble_query(1, 3, &answer) && events_are(1, "call: scramble_query 0x2d000000000 out 0x1 0x3"),
          "999 ms later: the call without a checkpoint");
    g_event_count = 0;
    g_now = 6000;
    CHECK(nat_scramble_query(1, 4, &answer) && events_are(2, "log: call scramble_query(0x2d000000000, 0x1, 0x4)",
                                                          "call: scramble_query 0x2d000000000 out 0x1 0x4"),
          "1000 ms after the last checkpoint: logged again");
    g_event_count = 0;
    CHECK(nat_ui_sound(0x39425a55u) && events_are(2, "log: call ui_sound(0x39425a55)", "call: ui_sound 0x0 0x39425a55"),
          "the sound has its own limit: its first call is logged");
    g_event_count = 0;
    g_now = 6500;
    CHECK(nat_ui_sound(1) && nat_scramble_query(1, 5, &answer) && g_event_count == 2 && event_has(0, "call: ui_sound")
              && event_has(1, "call: scramble_query"),
          "500 ms later: sound and query called, neither logged");
    g_event_count = 0;
    g_now = 7000;
    CHECK(nat_ui_sound(2) && events_are(2, "log: call ui_sound(0x2)", "call: ui_sound 0x0 0x2"),
          "1000 ms after its last checkpoint: the sound is logged again");
    g_event_count = 0;
    CHECK(nat_input_handler(COMPONENT) && nat_input_handler(COMPONENT) && g_event_count == 4,
          "the input handler logs every call, clock or not");
    g_event_count = 0;
    CHECK(nat_open_input(COMPONENT, &(uint8_t){ 0 }) && nat_close_input(COMPONENT) && nat_request_slot(WEAPON, 5)
              && nat_close_input(COMPONENT) && g_event_count == 8,
          "open, close and the slot request log every call");
    g_now = 6600; /* 600 ms after the query's last checkpoint, 400 before the sound's next one is due */
    native_init(&CLOCKED);
    native_set_base(SYN_GAME_BASE);
    g_event_count = 0;
    CHECK(nat_scramble_query(1, 6, &answer) && nat_ui_sound(3) && g_event_count == 4,
          "a new session (native_init): its first query and sound are logged at once");

    start(&CLOCKED);
    g_now = 0;
    CHECK(nat_scramble_query(1, 2, &answer) && g_event_count == 2, "a first call at clock 0 is logged");
    g_event_count = 0;
    g_now = 999;
    CHECK(nat_scramble_query(1, 2, &answer) && g_event_count == 1, "  not at 999");
    g_event_count = 0;
    g_now = 1000;
    CHECK(nat_scramble_query(1, 2, &answer) && g_event_count == 2, "  again at 1000");
    start(&PORT);
    CHECK(nat_scramble_query(1, 2, &answer) && nat_scramble_query(1, 2, &answer) && g_event_count == 4,
          "without a clock every call is logged");
}

static void test_scramble_arguments(void)
{
    uint32_t answer = 0;
    start(&PORT);
    g_scramble_writes = true;
    g_scramble_answer = 3;
    CHECK(nat_scramble_query(0x1badf00du, 62, &answer), "the query is made");
    CHECK(events_are(2, "log: call scramble_query(0x2d000000000, 0x1badf00d, 0x3e)",
                     "call: scramble_query 0x2d000000000 out 0x1badf00d 0x3e"),
          "its arguments are [EFFECTS], out, key, kind");
    CHECK(g_out_on_entry == 0xffffffffu, "*out was 0xffffffff when the game was asked");
    CHECK(g_scramble_a5 == 0 && g_scramble_a6 == 0, "the two optional outputs are null");
    CHECK(answer == 3, "what the game wrote to *out is the answer");

    answer = 7; /* a leftover from an earlier question must not leak through when the game writes nothing */
    g_scramble_writes = false;
    CHECK(nat_scramble_query(1, 2, &answer) && answer == 0xffffffffu && g_out_on_entry == 0xffffffffu,
          "when the game writes nothing, *out stays 0xffffffff");

    g_scramble_writes = true;
    g_scramble_answer = 0xffffffffu;
    CHECK(nat_scramble_query(1, 2, &answer) && answer == 0xffffffffu, "an answer of 0xffffffff is delivered as is");
}

static void test_scramble_effects_missing(void)
{
    uint32_t answer = 0x1111;
    start(&PORT);
    syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, 0);
    CHECK(!nat_scramble_query(1, 2, &answer) && events_are(1, "log: scramble query skipped: no effects pointer")
              && answer == 0x1111,
          "no effects pointer: false, nothing called, one \"scramble query skipped\" line, *out left alone");
    g_event_count = 0;
    CHECK(!nat_scramble_query(1, 2, &answer) && no_events(), "  the line is logged once a session");
    syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, AT_EFFECTS + 2);
    CHECK(!nat_scramble_query(1, 2, &answer) && no_events() && answer == 0x1111, "a misaligned effects pointer is missing too");
    syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, 0x40);
    CHECK(!nat_scramble_query(1, 2, &answer) && no_events() && answer == 0x1111, "an implausible effects pointer is missing too");
    syn_unmap(SYN_GAME_BASE + RVA_EFFECTS);
    CHECK(!nat_scramble_query(1, 2, &answer) && no_events() && answer == 0x1111, "an effects global that cannot be read is missing too");
    native_init(&PORT);
    native_set_base(SYN_GAME_BASE);
    CHECK(!nat_scramble_query(1, 2, &answer) && events_are(1, "log: scramble query skipped: no effects pointer"),
          "a new session (native_init) logs its first skipped query again");
    start(&PORT);
    CHECK(!nat_scramble_query(1, 2, NULL) && no_events(), "nat_scramble_query(NULL out): false, nothing called, nothing logged");
    spoil_witness("scramble_query", true);
    syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, 0);
    CHECK(!nat_scramble_query(1, 2, &answer) && no_events(), "SCRAMBLE refused and no effects pointer: not even the skip line");
}

static void test_scramble_refused_leaves_out_alone(void)
{
    uint32_t answer = 0x2222;
    start(&PORT);
    spoil_witness("scramble_query", true);
    CHECK(!nat_scramble_query(1, 2, &answer) && no_events() && answer == 0x2222, "SCRAMBLE refused: *out left alone");
}

static void test_reinit(void)
{
    bool ok[6];
    start(&PORT);
    native_init(NULL);
    native_set_base(SYN_GAME_BASE);
    call_all(ok);
    CHECK(results_are(ok, false, false, false, false, false, false) && no_events(), "native_init(NULL) after a session: nothing is called");
    native_init(&PORT);
    native_set_base(SYN_GAME_BASE);
    call_all(ok);
    CHECK(results_are(ok, true, true, true, true, true, true), "native_init again: the wrappers work again");
}

int main(void)
{
    test_before_init();
    test_synthetic_admits_the_features();
    test_calls_after_a_checkpoint();
    test_checkpoint_hex();
    test_open_input_result();
    test_feature_gates();
    test_a_pending_feature_recovers();
    test_missing_functions();
    test_no_log_function();
    test_sound_preconditions();
    test_sound_skip_logged_once();
    test_sound_not_admitted_logs_nothing();
    test_no_base();
    test_per_tick_checkpoints_throttled();
    test_scramble_arguments();
    test_scramble_effects_missing();
    test_scramble_refused_leaves_out_alone();
    test_reinit();
    CHECK(syn_write_count() == 0, "no wrapper asked for a single write");
    syn_free();
    TEST_MAIN_END
}
