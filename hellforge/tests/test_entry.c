/* Tests for src/entry.c: code entry through the game's input path, per direction, paced and Instant, with every abort.
 * They run against the synthetic 25480438 image of tests/synthetic.c with the generated witness table (every feature
 * admitted; a test refuses ENTRY by changing a byte of its witness), a memory port that writes into the image (with
 * failures on demand), and native's real wrappers over a port whose input handler is synthetic.c's fake input component
 * (syn_input_handler) and whose scramble query answers what the test says. game_read makes each tick's view, as dbf.c
 * will.
 *
 * The fake component and these tests spell R46's numbers out (input.lua:240-282): the count at component + 0, the
 * matched kind at + 0x14, the queued kind at + 0x2c, direction i at component + 3 + i, action a's byte at actions + 32 * a
 * (left 1, right 2, up 3, down 4) and code direction d pressed as action ({3,2,4,1})[d]. None of them is taken from the
 * generated header, so a value given to the wrong name there (a swapped DIRECTION_n_ACTION among them) fails here.
 *
 * entry, codes, game, native and memory keep state in statics: every test starts with start(). */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "codes.h"
#include "entry.h"
#include "game.h"
#include "memory.h"
#include "native.h"
#include "synthetic.h"
#include "test.h"

#define GRACE_OVER 30000u
#define RVA_EFFECTS 0x33264b0u     /* R46 input.lua:153 */
#define AT_EFFECTS ((uintptr_t)0x2d000000000ull)
#define AT_ELSEWHERE ((uintptr_t)0x30000001000ull) /* neither the settings block nor the loader image */
/* R46's numbers for code entry (input.lua:240-282), written out. */
#define COUNT_AT 0x0u              /* input.lua:241, 258: u32, the directions the game has taken */
#define MATCHED_AT 0x14u           /* input.lua:242, 259, 275: u32, the kind matched */
#define QUEUED_AT 0x2cu            /* input.lua:242: u32 */
#define DIRECTIONS_AT 3u           /* input.lua:260: direction i (1-based) at component + 3 + i */
#define ACTION_STRIDE 32u          /* input.lua:188, 265: action a's byte at actions + 32 * a */
#define PANEL_OPEN 0x38769u        /* native.lua:214: the menu-open byte in the stratagem panel */
#define AVATAR_MENU 0xfd8u         /* input.lua:118: bit 9 (512) is the menu-active bit */
#define MENU_ACTIVE_BIT 512u
#define PAYLOAD_COUNT 0x788u       /* input.lua:230 */
#define PAYLOAD_KINDS 0x188u       /* input.lua:234 */
#define PAYLOAD_STRIDE 0x30u       /* input.lua:234 */
#define GAME_MODE 0xac21cu         /* native.lua:82: 4 in gameplay */
/* input.lua:263-264: "Native actions: left=1 right=2 up=3 down=4", code direction d is action ({3,2,4,1})[d]. */
static const int ACTION_FOR[5] = { 0, 3, 2, 4, 1 };

/* The code of kind 118 in these tests: up, right, down, left, so every direction (and every action) is used once. */
static const uint8_t CODE[4] = { 1, 2, 3, 4 };

/* --- the ports ------------------------------------------------------------------------------------------------- */

/* Memory: synthetic reads; writes into the image, except the ones fail_writes() asks to fail. */
static int g_writes;    /* writes asked for since start() */
static int g_fail_from; /* the first write (1-based) that fails */
static int g_fail_count;

static int write_port(uintptr_t address, const void* data, size_t size)
{
    int index = ++g_writes;
    if (g_fail_count > 0 && index >= g_fail_from && index < g_fail_from + g_fail_count) return -1;
    return syn_write_mapped(address, data, size);
}

static const MemPort MEM = { syn_read, write_port };

/* After `after` more writes, the next `count` fail (without writing). */
static void fail_writes(int after, int count)
{
    g_fail_from = g_writes + after + 1;
    g_fail_count = count;
}

/* Native: the fake input component as the input handler, a scramble query that answers g_answer, and a log. */
static uint32_t g_answer;

static uintptr_t fake_scramble_query(uintptr_t effects, uint32_t* out, uint32_t key, uint32_t kind, uintptr_t a5, uintptr_t a6)
{
    *out = g_answer;
    return 0;
}

#define MAX_LINES 512
static char g_lines[MAX_LINES][160];
static int g_line_count;

static void fake_log(const char* line)
{
    if (g_line_count < MAX_LINES) snprintf(g_lines[g_line_count], sizeof g_lines[0], "%s", line);
    g_line_count++;
}

static const NativePort NATIVE = { syn_input_handler, NULL, NULL, NULL, NULL, fake_scramble_query, fake_log };
static const NativePort NO_HANDLER = { NULL, NULL, NULL, NULL, NULL, fake_scramble_query, fake_log };

/* --- helpers --------------------------------------------------------------------------------------------------- */

static SynScene g_scene;
static GameView g_view;

static bool start_with(const SynScene* s, const NativePort* port)
{
    bool built = syn_build(s);
    mem_init(&MEM);
    adm_init(syn_adm_port(), 0);
    built = built && syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, AT_EFFECTS);
    native_init(port);
    native_set_base(SYN_GAME_BASE);
    codes_init(NULL);
    game_init(SYN_GAME_BASE, SYN_IMAGE_SIZE);
    syn_input_reset();
    syn_input_expect(118, CODE, 4);
    g_answer = 0xffffffffu;
    g_line_count = 0;
    g_writes = 0;
    g_fail_count = 0;
    return built;
}

/* The default scene with kind 118 (card 0, payload entry 0) given CODE. */
static bool start(void)
{
    syn_default(&g_scene);
    g_scene.stratagems[0].code_len = 4;
    memcpy(g_scene.stratagems[0].code, CODE, sizeof CODE);
    return start_with(&g_scene, &NATIVE);
}

/* This tick's view, as dbf.c reads it before entry runs. */
static const GameView* view(void)
{
    game_read(&g_view);
    return &g_view;
}

static bool begin(EntryJob* job, uint32_t kind, uint32_t interval, bool instant, uint64_t now)
{
    memset(job, 0xa5, sizeof *job);
    job->state = ENTRY_IDLE;
    return entry_begin(job, view(), kind, interval, instant, false, now);
}

static void step(EntryJob* job, uint64_t now, bool trigger_down)
{
    entry_step(job, view(), now, trigger_down);
}

static uint8_t action_byte(int a)
{
    uint8_t byte = 0xee;
    syn_read(syn_local_actions() + ACTION_STRIDE * (uintptr_t)a, &byte, 1);
    return byte;
}

static bool actions_idle(void)
{
    for (int a = 1; a <= 4; a++) {
        if (action_byte(a) == 0) continue;
        printf("  action %d's byte is %u\n", a, (unsigned)action_byte(a));
        return false;
    }
    return true;
}

static bool journal_empty(void)
{
    int n = mem_journal_count(MEM_OWNER_ENTRY);
    if (n == 0) return true;
    printf("  %d ENTRY entries in the journal\n", n);
    return false;
}

/* Every action byte back to 0 and nothing of ENTRY's left in the journal. */
static bool clean(void)
{
    bool idle = actions_idle(), empty = journal_empty();
    return idle && empty;
}

static uint32_t component_u32(uint32_t offset)
{
    uint32_t v = 0xeeeeeeeeu;
    syn_read(syn_local_component() + offset, &v, sizeof v);
    return v;
}

/* The component says the game took `n` directions, `dirs`, and matched `matched`. */
static bool component_is(uint32_t n, uint32_t matched, const uint8_t* dirs)
{
    bool same = component_u32(COUNT_AT) == n && component_u32(MATCHED_AT) == matched;
    for (uint32_t i = 1; same && i <= n; i++) {
        uint8_t byte = 0;
        syn_read(syn_local_component() + DIRECTIONS_AT + i, &byte, 1);
        same = byte == dirs[i - 1];
    }
    if (!same) printf("  component: count %u, matched %u\n", (unsigned)component_u32(COUNT_AT), (unsigned)component_u32(MATCHED_AT));
    return same;
}

/* Calls first..first+n-1 found the actions of directions dirs[0..n) pressed, by R46's table. */
static bool pressed(int first, const uint8_t* dirs, int n)
{
    for (int i = 0; i < n; i++) {
        if (syn_input_action(first + i) == ACTION_FOR[dirs[i]]) continue;
        printf("  call %d found action %d pressed, expected %d\n", first + i, syn_input_action(first + i), ACTION_FOR[dirs[i]]);
        return false;
    }
    return true;
}

static bool state_is(const EntryJob* job, EntryState state, const char* reason)
{
    if (job->state == state && strcmp(job->reason, reason) == 0) return true;
    printf("  job state %d, reason \"%s\" (expected %d, \"%s\"); sent %u, calls %d\n", (int)job->state, job->reason, (int)state,
           reason, (unsigned)job->sent, syn_input_calls());
    return false;
}

/* entry_begin refuses `kind` with `reason`, writing and calling nothing. */
static bool refused(EntryJob* job, uint32_t kind, const char* reason)
{
    bool started = begin(job, kind, 70, false, 0);
    if (!started && state_is(job, ENTRY_FAILED, reason) && g_writes == 0 && syn_input_calls() == 0) return true;
    printf("  begin(%u): %d, %d writes, %d calls\n", (unsigned)kind, started, g_writes, syn_input_calls());
    return false;
}

static bool sent_is(const EntryJob* job, int sent, int calls)
{
    if (job->sent == sent && syn_input_calls() == calls) return true;
    printf("  sent %u, calls %d (expected %d, %d)\n", (unsigned)job->sent, syn_input_calls(), sent, calls);
    return false;
}

/* The game clears the component when its menu closes. */
static void clear_component(void)
{
    uint8_t zero[12] = { 0 };
    syn_poke_u32(syn_local_component() + COUNT_AT, 0);
    syn_poke_u32(syn_local_component() + MATCHED_AT, 0);
    syn_poke_u32(syn_local_component() + QUEUED_AT, 0);
    syn_poke(syn_local_component() + DIRECTIONS_AT + 1u, zero, sizeof zero);
}

static void set_menu_open(uint8_t open) { syn_poke_u8(syn_panel() + PANEL_OPEN, open); }

static void set_menu_active(bool active)
{
    syn_poke_u32(syn_local_avatar() + AVATAR_MENU, active ? MENU_ACTIVE_BIT | 0x5u : 0x5u);
}

static const DbfWitness* witness(const char* name)
{
    for (int i = 0; i < dbf_witness_count; i++)
        if (strcmp(dbf_witnesses[i].name, name) == 0) return &dbf_witnesses[i];
    return NULL;
}

/* Changes a byte of the witness and restarts admission, past the grace period or not. */
static void spoil_witness(const char* name, bool past_grace)
{
    const DbfWitness* w = witness(name);
    if (!w) return;
    syn_poke_u8(SYN_GAME_BASE + w->rva, (uint8_t)(w->bytes[0] ^ 0x55u));
    adm_init(syn_adm_port(), 0);
    if (past_grace) adm_tick(GRACE_OVER);
}

/* Hooks run inside a handler call (syn_input_on_call). */
static int g_hook_call; /* the call they act in */
static void hook_close_menu(int call)
{
    if (call == g_hook_call) set_menu_active(false);
}
static void hook_change_code(int call)
{
    static const uint8_t other[4] = { 1, 2, 4, 3 };
    if (call == g_hook_call) syn_set_code(syn_definition(118), syn_code_array(118), 4, other);
}
static void hook_release(int call)
{
    for (uint32_t a = 1; a <= 4; a++) syn_poke_u8(syn_local_actions() + ACTION_STRIDE * a, 0);
}

/* --- paced and Instant ----------------------------------------------------------------------------------------- */

static void test_paced(void)
{
    EntryJob job;
    char line[96];
    start();
    CHECK(begin(&job, 118, 70, false, 1000) && state_is(&job, ENTRY_RUNNING, ""), "begin: the job runs");
    CHECK(job.kind == 118 && job.code.len == 4 && memcmp(job.code.dir, CODE, 4) == 0 && job.code.kind_used == 118
              && !job.code.scrambled && job.sent == 0 && job.interval_ms == 70 && !job.instant && !job.latched,
          "  kind 118, its code, nothing sent, 70 ms, paced");
    CHECK(job.next_at == 1000 && job.deadline == 4000 && job.settle_at == 0,
          "  next_at is now; the deadline 1000 + max(3000, 4 * 70 + 1500) (R46 selection.lua:92)");
    CHECK(job.identity_manager == syn_avatars() && job.identity_key == syn_local_key()
              && job.component == syn_local_component(),
          "  the identity is the avatar manager and the local key, with the local input component");
    CHECK(syn_input_calls() == 0 && g_writes == 0 && clean() && component_is(0, 0, CODE), "  begin writes and calls nothing");

    step(&job, 1000, false);
    CHECK(sent_is(&job, 1, 1) && pressed(0, CODE, 1) && job.next_at == 1070 && component_is(1, 0, CODE) && clean(),
          "1000 ms: direction 1 (up, action 3) taken; next_at 1070; the byte released, the journal empty");
    step(&job, 1069, false);
    CHECK(sent_is(&job, 1, 1) && state_is(&job, ENTRY_RUNNING, ""), "1069 ms: nothing is due");
    step(&job, 1070, true);
    CHECK(sent_is(&job, 2, 2) && pressed(1, CODE + 1, 1) && job.next_at == 1140 && component_is(2, 0, CODE) && clean(),
          "1070 ms: direction 2 (right, action 2); a held trigger does not matter when paced");
    step(&job, 1140, false);
    CHECK(sent_is(&job, 3, 3) && pressed(2, CODE + 2, 1) && job.next_at == 1210 && component_is(3, 0, CODE) && clean(),
          "1140 ms: direction 3 (down, action 4)");
    step(&job, 1209, false);
    CHECK(sent_is(&job, 3, 3), "1209 ms: nothing");
    step(&job, 1210, false);
    CHECK(sent_is(&job, 4, 4) && pressed(3, CODE + 3, 1) && state_is(&job, ENTRY_DONE, "") && component_is(4, 118, CODE)
              && clean(),
          "1210 ms: direction 4 (left, action 1): done, the game matched kind 118");
    step(&job, 1280, false);
    CHECK(sent_is(&job, 4, 4) && state_is(&job, ENTRY_DONE, ""), "a done job does nothing more");
    CHECK(g_writes == 8, "two writes per direction: the press and the release");
    snprintf(line, sizeof line, "call input_handler(0x%llx)", (unsigned long long)syn_local_component());
    {
        int checkpoints = 0;
        for (int i = 0; i < g_line_count && i < MAX_LINES; i++) checkpoints += strcmp(g_lines[i], line) == 0;
        CHECK(checkpoints == 4, "native logged a checkpoint before each of the four handler calls");
    }
}

static void test_interval_zero(void)
{
    EntryJob job;
    start();
    CHECK(begin(&job, 118, 0, false, 500) && job.deadline == 3500 && job.next_at == 500, "interval 0: deadline now + 3000");
    for (int i = 1; i <= 4; i++) {
        step(&job, 500, false);
        CHECK(sent_is(&job, i, i) && clean(), "  one direction per step, the clock standing still");
    }
    CHECK(state_is(&job, ENTRY_DONE, "") && pressed(0, CODE, 4) && component_is(4, 118, CODE), "  done after four steps");
}

static void test_instant(void)
{
    EntryJob job;
    start();
    CHECK(begin(&job, 118, 70, true, 2000) && job.instant && job.interval_ms == 0 && job.deadline == 5000,
          "Instant: interval 0, the deadline now + 3000");
    step(&job, 2000, true);
    CHECK(sent_is(&job, 3, 3) && pressed(0, CODE, 3) && component_is(3, 0, CODE) && job.settle_at == 0 && clean()
              && state_is(&job, ENTRY_RUNNING, ""),
          "the first step sends every direction but the last; the trigger is down");
    step(&job, 2050, true);
    CHECK(sent_is(&job, 3, 3) && job.settle_at == 0, "trigger still down: the last waits");
    step(&job, 2060, false);
    CHECK(sent_is(&job, 3, 3) && job.settle_at == 2160, "trigger up at 2060: it may go at 2160");
    step(&job, 2100, true);
    CHECK(sent_is(&job, 3, 3) && job.settle_at == 0, "down again at 2100: the wait starts over");
    step(&job, 2110, false);
    CHECK(sent_is(&job, 3, 3) && job.settle_at == 2210, "up at 2110: 2210");
    step(&job, 2209, false);
    CHECK(sent_is(&job, 3, 3) && state_is(&job, ENTRY_RUNNING, ""), "2209: not yet");
    step(&job, 2210, false);
    CHECK(sent_is(&job, 4, 4) && pressed(3, CODE + 3, 1) && state_is(&job, ENTRY_DONE, "") && component_is(4, 118, CODE)
              && clean(),
          "2210: the trigger has been up 100 ms, the last direction goes, done");

    start();
    begin(&job, 118, 70, true, 0);
    step(&job, 0, false);
    CHECK(sent_is(&job, 3, 3) && job.settle_at == 100, "trigger up from the start: three at once, the last at 100");
    step(&job, 99, false);
    CHECK(sent_is(&job, 3, 3), "  not at 99");
    step(&job, 100, false);
    CHECK(sent_is(&job, 4, 4) && state_is(&job, ENTRY_DONE, ""), "  at 100");

    /* A code of one direction: the only direction is the last. */
    syn_default(&g_scene);
    g_scene.stratagems[1].code_len = 1;
    g_scene.stratagems[1].code[0] = 2;
    start_with(&g_scene, &NATIVE);
    syn_input_expect(4, (const uint8_t[]){ 2 }, 1);
    CHECK(begin(&job, 4, 0, true, 0), "Instant, a one-direction code (kind 4)");
    step(&job, 0, false);
    CHECK(sent_is(&job, 0, 0) && job.settle_at == 100, "  nothing at once: its one direction is the last");
    step(&job, 100, false);
    CHECK(sent_is(&job, 1, 1) && syn_input_action(0) == ACTION_FOR[2] && state_is(&job, ENTRY_DONE, "")
              && component_u32(MATCHED_AT) == 4 && clean(),
          "  sent at 100, done");
}

/* --- interruptions (Review Focus 1) ---------------------------------------------------------------------------- */

static void test_menu_closed_between_directions(void)
{
    EntryJob job;
    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    step(&job, 70, false);
    CHECK(sent_is(&job, 2, 2) && component_is(2, 0, CODE), "two directions in");
    set_menu_open(0);
    step(&job, 140, false);
    CHECK(state_is(&job, ENTRY_FAILED, "menu closed") && sent_is(&job, 2, 2) && clean(),
          "the menu released between directions: failed, nothing more pressed, every byte 0, the journal empty");
    step(&job, 210, false);
    CHECK(sent_is(&job, 2, 2) && state_is(&job, ENTRY_FAILED, "menu closed"), "  a failed job does nothing more");

    /* The game clears its component when the menu closes; the next open works as before. */
    clear_component();
    set_menu_open(1);
    CHECK(begin(&job, 118, 70, false, 1000), "the menu opened again: a new job begins");
    step(&job, 1000, false);
    step(&job, 1070, false);
    step(&job, 1140, false);
    step(&job, 1210, false);
    CHECK(state_is(&job, ENTRY_DONE, "") && component_is(4, 118, CODE) && pressed(2, CODE, 4) && clean(),
          "  and runs to done");

    /* The game closes its input menu (the active bit) while the HUD byte still says open. */
    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    set_menu_active(false);
    step(&job, 70, false);
    CHECK(state_is(&job, ENTRY_FAILED, "menu inactive") && sent_is(&job, 1, 1) && clean(), "the menu-active bit clears: failed");
    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    set_menu_active(false);
    step(&job, 30, false);
    CHECK(state_is(&job, ENTRY_FAILED, "menu inactive") && sent_is(&job, 1, 1),
          "  also on a step with no direction due: every step checks");

    /* Instant: the game closes the menu inside the second call; the third direction is not pressed. */
    start();
    g_hook_call = 1;
    syn_input_on_call(hook_close_menu);
    begin(&job, 118, 0, true, 0);
    step(&job, 0, true);
    CHECK(state_is(&job, ENTRY_FAILED, "menu inactive") && sent_is(&job, 2, 2) && clean(),
          "Instant, the menu closes inside the second call: failed before the third direction");

    /* Death, a new session, mission end. */
    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    syn_change_peer(0x5151515151515151ull);
    step(&job, 70, false);
    CHECK(state_is(&job, ENTRY_FAILED, "local player unavailable") && sent_is(&job, 1, 1) && clean(),
          "the local player's chain breaks (a new session): failed");
    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    syn_poke_u32(syn_game_state() + GAME_MODE, 0);
    step(&job, 70, false);
    CHECK(state_is(&job, ENTRY_FAILED, "menu closed") && sent_is(&job, 1, 1) && clean(), "the mission ends: failed");
}

static void test_identity_changed(void)
{
    EntryJob job;
    GameView v;
    for (int which = 0; which < 3; which++) {
        start();
        begin(&job, 118, 70, false, 0);
        step(&job, 0, false);
        v = *view();
        if (which == 0) v.local.key ^= 1u;
        if (which == 1) v.local.manager += 0x1000u;
        if (which == 2) v.local.component += 0x1238u;
        entry_step(&job, &v, 70, false);
        CHECK(state_is(&job, ENTRY_FAILED, "player changed") && sent_is(&job, 1, 1) && clean(),
              which == 0 ? "another key: failed" : which == 1 ? "another avatar manager: failed" : "another input component: failed");
    }
}

static void test_deadline(void)
{
    EntryJob job;
    start();
    CHECK(begin(&job, 118, 250, false, 0) && job.deadline == 3000, "250 ms, four directions: the deadline is 3000");
    step(&job, 0, false);
    step(&job, 3001, false);
    CHECK(state_is(&job, ENTRY_FAILED, "timed out") && sent_is(&job, 1, 1) && clean(), "3001 ms: timed out, nothing sent");

    start();
    begin(&job, 118, 250, false, 0);
    step(&job, 0, false);
    step(&job, 250, false);
    step(&job, 500, false);
    step(&job, 3000, false);
    CHECK(state_is(&job, ENTRY_DONE, "") && sent_is(&job, 4, 4), "at the deadline itself the last direction still goes");

    syn_default(&g_scene);
    g_scene.stratagems[0].code_len = 12;
    memcpy(g_scene.stratagems[0].code, (const uint8_t[]){ 1, 2, 3, 4, 4, 3, 2, 1, 1, 1, 2, 2 }, 12);
    start_with(&g_scene, &NATIVE);
    CHECK(begin(&job, 118, 250, false, 0) && job.deadline == 4500, "twelve directions at 250 ms: 12 * 250 + 1500");
    entry_cancel(&job, NULL);
    CHECK(begin(&job, 118, 250, true, 0) && job.deadline == 3000, "  Instant uses an interval of 0: 3000");

    start();
    begin(&job, 118, 70, true, 0);
    step(&job, 0, true);
    step(&job, 3000, true);
    CHECK(state_is(&job, ENTRY_RUNNING, "") && sent_is(&job, 3, 3), "Instant, the trigger held: running at 3000");
    step(&job, 3001, true);
    CHECK(state_is(&job, ENTRY_FAILED, "timed out") && sent_is(&job, 3, 3) && clean(), "  timed out at 3001");
}

static void test_payload_changed(void)
{
    EntryJob job;
    uintptr_t payload;
    start();
    payload = syn_payload(g_scene.local_entry);
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    syn_poke_u32(payload + PAYLOAD_KINDS, 7);
    step(&job, 70, false);
    CHECK(state_is(&job, ENTRY_FAILED, "stratagem no longer in the mission") && sent_is(&job, 1, 1) && clean(),
          "the kind leaves the payload: failed");
    start();
    payload = syn_payload(g_scene.local_entry);
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    syn_poke_u32(payload + PAYLOAD_COUNT, 40);
    step(&job, 70, false);
    CHECK(state_is(&job, ENTRY_FAILED, "invalid stratagem entry count") && sent_is(&job, 1, 1), "a payload count over 32: failed");
}

/* --- the code changes (Review Focus 3) ------------------------------------------------------------------------- */

static void test_code_changes(void)
{
    static const uint8_t other[4] = { 1, 2, 4, 3 };
    EntryJob job;
    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    step(&job, 70, false);
    syn_set_code(syn_definition(118), syn_code_array(118), 4, other);
    step(&job, 140, false);
    CHECK(state_is(&job, ENTRY_FAILED, "code changed") && sent_is(&job, 2, 2) && clean(),
          "the code changes after direction 2 (a Lua mod's set_code): failed before direction 3 is sent");

    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    step(&job, 70, false);
    g_answer = 3; /* a scramble effect starts: kind 118 reads kind 119's code */
    step(&job, 140, false);
    CHECK(state_is(&job, ENTRY_FAILED, "code changed") && sent_is(&job, 2, 2) && clean(),
          "a scramble effect starts after direction 2: failed before direction 3");

    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    syn_set_code(syn_definition(118), AT_ELSEWHERE, 4, NULL);
    step(&job, 70, false);
    CHECK(state_is(&job, ENTRY_FAILED, "code changed: code outside the game and HellForge") && sent_is(&job, 1, 1),
          "the code can no longer be read: failed with codes' reason");

    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    syn_set_code(syn_definition(118), syn_code_array(118), 4, CODE); /* rewritten, the same directions */
    step(&job, 70, false);
    CHECK(state_is(&job, ENTRY_RUNNING, "") && sent_is(&job, 2, 2), "the same code written again is no change");

    start();
    g_hook_call = 1;
    syn_input_on_call(hook_change_code);
    begin(&job, 118, 0, true, 0);
    step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_FAILED, "code changed") && sent_is(&job, 2, 2) && clean(),
          "Instant, the code changes inside the second call: the third direction is not sent");
}

static void test_scrambled_job(void)
{
    static const uint8_t made_up_119[3] = { 4, 1, 2 }; /* synthetic.c's code for kind 119: 1 + (119 + i) % 4 */
    EntryJob job;
    start();
    g_answer = 3; /* scramble on, seed 0: kind 118 -> (118 + 0) % 149 + 1 = 119 (R46 input.lua:157) */
    syn_input_expect(118, made_up_119, 3); /* the game matches the scrambled code and reports the kind asked for */
    CHECK(begin(&job, 118, 0, false, 0) && job.kind == 118 && job.code.kind_used == 119 && job.code.scrambled
              && job.code.len == 3 && memcmp(job.code.dir, made_up_119, 3) == 0,
          "a job under a scramble effect: kind 118 with kind 119's code");
    step(&job, 0, false);
    step(&job, 0, false);
    step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_DONE, "") && pressed(0, made_up_119, 3) && component_is(3, 118, made_up_119) && clean(),
          "  done: the game matched kind 118, the kind asked for, not 119");
}

/* --- the game's answers ---------------------------------------------------------------------------------------- */

static void test_game_answers(void)
{
    EntryJob job;
    start();
    syn_input_ignore(true);
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_FAILED, "the game did not take the direction") && sent_is(&job, 1, 1) && clean()
              && component_is(0, 0, CODE),
          "the handler does not count the direction: failed, the byte released, the journal empty");

    start();
    syn_input_expect(118, (const uint8_t[]){ 1, 2, 3, 3 }, 4);
    begin(&job, 118, 0, false, 0);
    for (int i = 0; i < 4; i++) step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_FAILED, "the game did not accept the code") && sent_is(&job, 4, 4) && clean(),
          "no match after the last direction: failed");

    start();
    syn_input_expect(119, CODE, 4);
    begin(&job, 118, 0, false, 0);
    for (int i = 0; i < 4; i++) step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_FAILED, "the game did not accept the code"), "the last direction matches another kind: failed");

    start();
    syn_input_expect(99, CODE, 2);
    begin(&job, 118, 0, false, 0);
    for (int i = 0; i < 3; i++) step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_FAILED, "the game matched another stratagem") && sent_is(&job, 2, 2) && clean(),
          "a match after direction 2 of 4: failed, direction 3 not sent");
}

static void test_game_state_between_directions(void)
{
    EntryJob job;
    struct {
        uint32_t offset, value;
        bool byte;
        const char* reason;
        const char* text;
    } cases[] = {
        { COUNT_AT, 5, false, "the game's input changed", "the count changes between directions: failed" },
        { MATCHED_AT, 4, false, "the game's input changed", "a matched kind appears between directions: failed" },
        { DIRECTIONS_AT + 1u, 2, true, "the game's code sequence changed", "direction 1's byte changes: failed" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        start();
        begin(&job, 118, 70, false, 0);
        step(&job, 0, false);
        if (cases[i].byte)
            syn_poke_u8(syn_local_component() + cases[i].offset, (uint8_t)cases[i].value);
        else
            syn_poke_u32(syn_local_component() + cases[i].offset, cases[i].value);
        step(&job, 70, false);
        CHECK(state_is(&job, ENTRY_FAILED, cases[i].reason) && sent_is(&job, 1, 1) && clean(), cases[i].text);
    }

    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    syn_poke_u8(syn_local_actions() + ACTION_STRIDE * 1u, 1); /* the player holds left */
    g_writes = 0;
    step(&job, 70, false);
    CHECK(state_is(&job, ENTRY_FAILED, "manual direction input") && sent_is(&job, 1, 1) && g_writes == 0
              && action_byte(1) == 1 && journal_empty(),
          "a direction held by the player: failed, nothing written, the player's byte left alone");
}

/* --- writes and the handler ------------------------------------------------------------------------------------ */

static void test_writes_and_handler(void)
{
    EntryJob job;
    start();
    begin(&job, 118, 70, false, 0);
    fail_writes(0, 1);
    step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_FAILED, "direction could not be pressed") && sent_is(&job, 0, 0) && clean(),
          "the press cannot be written: failed, the handler not called, nothing journaled");

    start();
    begin(&job, 118, 70, false, 0);
    fail_writes(1, 1);
    step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_FAILED, "direction could not be released") && sent_is(&job, 1, 1)
              && action_byte(ACTION_FOR[1]) == 1 && mem_journal_count(MEM_OWNER_ENTRY) == 1,
          "the release cannot be written: failed, the byte stays pressed and its entry stays journaled");
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0 && clean(), "  a later restore (the tick's) releases it");

    start();
    syn_input_on_call(hook_release);
    begin(&job, 118, 0, false, 0);
    for (int i = 0; i < 4; i++) step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_DONE, "") && sent_is(&job, 4, 4) && clean() && g_writes == 4,
          "the game releases the byte itself inside each call: that counts as released, done");

    syn_default(&g_scene);
    g_scene.stratagems[0].code_len = 4;
    memcpy(g_scene.stratagems[0].code, CODE, sizeof CODE);
    start_with(&g_scene, &NO_HANDLER);
    CHECK(begin(&job, 118, 70, false, 0), "a native port without the input handler: begin works");
    step(&job, 0, false);
    CHECK(state_is(&job, ENTRY_FAILED, "input handler unavailable") && sent_is(&job, 0, 0) && clean() && g_writes == 2,
          "  the first direction: pressed, not handled, released; failed");
}

/* --- admission and begin --------------------------------------------------------------------------------------- */

static void test_entry_admission(void)
{
    EntryJob job;
    char want[96];
    start();
    spoil_witness("input_handler", true);
    snprintf(want, sizeof want, "%s: witness input_handler differs", adm_feature_name(FEAT_ENTRY));
    CHECK(!begin(&job, 118, 70, false, 0) && state_is(&job, ENTRY_FAILED, want) && syn_input_calls() == 0 && g_writes == 0,
          "ENTRY refused: entry_begin false with admission's reason, nothing written or called");
    start();
    spoil_witness("input_handler", false);
    snprintf(want, sizeof want, "%s: witness input_handler differs (retrying)", adm_feature_name(FEAT_ENTRY));
    CHECK(!begin(&job, 118, 70, false, 0) && state_is(&job, ENTRY_FAILED, want), "ENTRY pending: the same, with its reason");

    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    spoil_witness("input_handler", true);
    g_writes = 0;
    step(&job, 70, false);
    snprintf(want, sizeof want, "%s: witness input_handler differs", adm_feature_name(FEAT_ENTRY));
    CHECK(state_is(&job, ENTRY_FAILED, want) && sent_is(&job, 1, 1) && g_writes == 0 && clean(),
          "ENTRY refused between directions: failed before anything is pressed");
}

static void test_begin_refusals(void)
{
    EntryJob job;
    uintptr_t payload;
    struct {
        uint32_t offset;
        const char* text;
    } dirty[] = {
        { COUNT_AT, "a count left in the component: \"close and reopen the menu\"" },
        { MATCHED_AT, "a matched kind left: the same" },
        { QUEUED_AT, "a queued kind left: the same" },
    };

    start();
    set_menu_open(0);
    CHECK(refused(&job, 118, "menu closed"), "the menu closed: refused, nothing written or called");
    start();
    set_menu_active(false);
    CHECK(refused(&job, 118, "menu inactive"), "the menu inactive: refused");
    start();
    view(); /* the identity game_read keeps; the next read sees the new session */
    syn_change_peer(0x5151515151515151ull);
    CHECK(refused(&job, 118, "local player unavailable"), "no code-entry chain (a new session): refused");
    for (size_t i = 0; i < sizeof dirty / sizeof dirty[0]; i++) {
        start();
        syn_poke_u32(syn_local_component() + dirty[i].offset, 118);
        CHECK(refused(&job, 118, "close and reopen the menu"), dirty[i].text);
    }
    for (int a = 1; a <= 4; a++) {
        start();
        syn_poke_u8(syn_local_actions() + ACTION_STRIDE * (uintptr_t)a, 1);
        CHECK(refused(&job, 118, "manual direction input"), "a direction action held: refused");
    }
    start();
    CHECK(refused(&job, 7, "stratagem not in the mission"), "a kind the payload does not hold: refused");
    start();
    payload = syn_payload(g_scene.local_entry);
    syn_poke_u32(payload + PAYLOAD_KINDS + PAYLOAD_STRIDE * 4u, 7); /* entry 4, just past the count of 4 */
    CHECK(refused(&job, 7, "stratagem not in the mission"), "a kind just past the payload's count: refused");
    start();
    payload = syn_payload(g_scene.local_entry);
    syn_poke_u32(payload + PAYLOAD_COUNT, 33);
    CHECK(refused(&job, 118, "invalid stratagem entry count"), "a payload count over 32: refused");
    start();
    payload = syn_payload(g_scene.local_entry);
    syn_poke_u32(payload + PAYLOAD_KINDS + PAYLOAD_STRIDE * 3u, 151);
    CHECK(refused(&job, 151, "unknown stratagem kind"), "no code for the kind (151 with the vanilla table): codes' reason");
    start();
    syn_set_code(syn_definition(118), AT_ELSEWHERE, 4, NULL);
    CHECK(refused(&job, 118, "code outside the game and HellForge"), "a code codes refuses: refused with its reason");

    start();
    CHECK(!entry_begin(NULL, view(), 118, 70, false, false, 0), "a NULL job: false");
    memset(&job, 0, sizeof job);
    CHECK(!entry_begin(&job, NULL, 118, 70, false, false, 0) && state_is(&job, ENTRY_FAILED, "menu closed"),
          "a NULL view: refused, \"menu closed\"");
    CHECK(entry_begin(&job, view(), 118, 70, false, true, 0) && job.latched, "latched is kept in the job");
    {
        EntryJob copy = job;
        CHECK(!entry_begin(&job, view(), 4, 0, true, false, 5) && memcmp(&copy, &job, sizeof job) == 0,
              "a running job is left alone by another begin");
    }
}

/* --- cancel and idle jobs -------------------------------------------------------------------------------------- */

static void test_cancel(void)
{
    EntryJob job, copy;
    start();
    begin(&job, 118, 70, false, 0);
    step(&job, 0, false);
    entry_cancel(&job, "Confirm pressed");
    CHECK(state_is(&job, ENTRY_FAILED, "Confirm pressed") && clean(), "a running job cancelled: failed with the reason");
    step(&job, 70, false);
    CHECK(sent_is(&job, 1, 1), "  and does nothing more");
    start();
    begin(&job, 118, 70, false, 0);
    entry_cancel(&job, NULL);
    CHECK(state_is(&job, ENTRY_FAILED, "cancelled"), "a NULL reason: \"cancelled\"");
    copy = job;
    entry_cancel(&job, "again");
    CHECK(memcmp(&copy, &job, sizeof job) == 0, "a job that is not running is left alone");
    entry_cancel(NULL, "x");

    start();
    memset(&job, 0, sizeof job);
    step(&job, 0, false);
    CHECK(job.state == ENTRY_IDLE && syn_input_calls() == 0 && g_writes == 0, "an idle job's step does nothing");
    entry_step(NULL, view(), 0, false);
    begin(&job, 118, 70, false, 0);
    entry_step(&job, NULL, 0, false);
    CHECK(state_is(&job, ENTRY_FAILED, "menu closed") && syn_input_calls() == 0 && clean(), "a NULL view fails a running job");
}

int main(void)
{
    CHECK(start(), "the synthetic image builds with kind 118's four-direction code");
    test_paced();
    test_interval_zero();
    test_instant();
    test_menu_closed_between_directions();
    test_identity_changed();
    test_deadline();
    test_payload_changed();
    test_code_changes();
    test_scrambled_job();
    test_game_answers();
    test_game_state_between_directions();
    test_writes_and_handler();
    test_entry_admission();
    test_begin_refusals();
    test_cancel();
    CHECK(syn_write_count() == 0, "nothing went through the refusing write port");
    syn_free();
    TEST_MAIN_END
}
