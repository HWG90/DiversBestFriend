/* Tests for src/sound.c: the selection sounds. A fake play function records the ids it was asked for and answers as the
 * test says; the log callback records its lines. The clock is the test's own number of milliseconds. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "addresses_25480438.h"
#include "logic.h"
#include "sound.h"
#include "test.h"

#define MOVE DBF_VAL_SOUND_MOVE
#define CONFIRM DBF_VAL_SOUND_CONFIRM

static uint32_t g_played[64];
static int g_play_count;
static bool g_play_answer = true;
static char g_logged[8][128];
static int g_log_count;

static bool fake_play(uint32_t id)
{
    if (g_play_count < 64) g_played[g_play_count] = id;
    g_play_count++;
    return g_play_answer;
}

static void fake_log(const char* line)
{
    if (g_log_count < 8) snprintf(g_logged[g_log_count], sizeof g_logged[0], "%s", line);
    g_log_count++;
}

static void start(SoundState* s)
{
    g_play_count = 0;
    g_play_answer = true;
    g_log_count = 0;
    memset(g_played, 0, sizeof g_played);
    sound_init(s, fake_play, fake_log);
}

static bool played_only(const uint32_t* ids, int n)
{
    if (g_play_count != n) {
        printf("  %d sounds played, expected %d\n", g_play_count, n);
        return false;
    }
    for (int i = 0; i < n; i++)
        if (g_played[i] != ids[i]) {
            printf("  sound %d was 0x%x, expected 0x%x\n", i, (unsigned)g_played[i], (unsigned)ids[i]);
            return false;
        }
    return true;
}

static bool nothing_played(void) { return played_only(NULL, 0); }

/* --- tests ----------------------------------------------------------------------------------------------------- */

static void test_ids(void)
{
    CHECK(MOVE == 0x39425a55u && CONFIRM == 0xdd274583u, "the move and confirm sound ids are R46's");
    CHECK(MOVE != CONFIRM, "and differ");
}

static void test_move(void)
{
    SoundState s;
    uint32_t move[1] = { MOVE };
    start(&s);
    sound_step(&s, LIST_MOVED, false, 1000);
    CHECK(played_only(move, 1), "a move plays the move sound");
    CHECK(g_log_count == 0, "and logs nothing");
}

static void test_first_move_any_clock(void)
{
    SoundState s;
    uint32_t move[1] = { MOVE };
    start(&s);
    sound_step(&s, LIST_MOVED, false, 0);
    CHECK(played_only(move, 1), "the first move plays at clock 0: no sound came before it");
}

static void test_no_event(void)
{
    SoundState s;
    start(&s);
    sound_step(&s, LIST_NONE, false, 1000);
    sound_step(&s, LIST_NONE, false, 2000);
    CHECK(nothing_played(), "no event, no job: silence");
}

static void test_confirm_event_without_job(void)
{
    SoundState s;
    start(&s);
    sound_step(&s, LIST_CONFIRM, false, 1000);
    CHECK(nothing_played(), "a Confirm whose job did not start is silent (R46 plays one cue per accepted job)");
}

static void test_move_throttle(void)
{
    SoundState s;
    start(&s);
    sound_step(&s, LIST_MOVED, false, 1000);
    sound_step(&s, LIST_MOVED, false, 1059);
    CHECK(g_play_count == 1, "a second move 59 ms after the first is dropped");
    sound_step(&s, LIST_MOVED, false, 1060);
    CHECK(g_play_count == 2 && g_played[1] == MOVE, "one 60 ms after the first plays");
    sound_step(&s, LIST_MOVED, false, 1100);
    CHECK(g_play_count == 2, "the clock restarts at the sound that played, not at the one that was dropped");
    sound_step(&s, LIST_MOVED, false, 1120);
    CHECK(g_play_count == 3, "60 ms after the last sound that played");
}

static void test_throttle_constant(void)
{
    CHECK(SOUND_MOVE_GAP_MS == 60, "the move gap is 60 ms (R46 feedback.lua:18, 25)");
}

static void test_confirm(void)
{
    SoundState s;
    uint32_t confirm[1] = { CONFIRM };
    start(&s);
    sound_step(&s, LIST_CONFIRM, true, 1000);
    CHECK(played_only(confirm, 1), "a job that started plays the confirm sound");
}

static void test_confirm_without_event(void)
{
    SoundState s;
    uint32_t confirm[1] = { CONFIRM };
    start(&s);
    sound_step(&s, LIST_NONE, true, 1000);
    CHECK(played_only(confirm, 1), "a job started by a slot hotkey (no list event) plays it too");
}

static void test_confirm_ignores_throttle(void)
{
    SoundState s;
    start(&s);
    sound_step(&s, LIST_MOVED, false, 1000);
    sound_step(&s, LIST_CONFIRM, true, 1001);
    CHECK(g_play_count == 2 && g_played[0] == MOVE && g_played[1] == CONFIRM, "confirm plays 1 ms after a move");
    sound_step(&s, LIST_NONE, true, 1002);
    CHECK(g_play_count == 3 && g_played[2] == CONFIRM, "and again 1 ms after a confirm");
}

static void test_confirm_resets_throttle(void)
{
    SoundState s;
    start(&s);
    sound_step(&s, LIST_CONFIRM, true, 1000);
    sound_step(&s, LIST_MOVED, false, 1030);
    CHECK(g_play_count == 1, "a move 30 ms after a confirm is dropped");
    sound_step(&s, LIST_MOVED, false, 1059);
    CHECK(g_play_count == 1, "so is one at 59 ms");
    sound_step(&s, LIST_MOVED, false, 1060);
    CHECK(g_play_count == 2 && g_played[1] == MOVE, "one at 60 ms plays");
}

static void test_move_after_confirm_uses_its_clock(void)
{
    SoundState s;
    start(&s);
    sound_step(&s, LIST_MOVED, false, 1000);
    sound_step(&s, LIST_CONFIRM, true, 1010);
    sound_step(&s, LIST_MOVED, false, 1060);
    CHECK(g_play_count == 2, "after the confirm at 1010 a move at 1060 (50 ms) is still dropped");
    sound_step(&s, LIST_MOVED, false, 1070);
    CHECK(g_play_count == 3, "and one at 1070 plays");
}

static void test_job_tick_has_no_move(void)
{
    SoundState s;
    start(&s);
    sound_step(&s, LIST_MOVED, true, 5000);
    CHECK(g_play_count == 1 && g_played[0] == CONFIRM, "a move and a started job on one tick: only the confirm");
}

static void test_log_once_and_disable(void)
{
    SoundState s;
    start(&s);
    g_play_answer = false;
    sound_step(&s, LIST_MOVED, false, 1000);
    CHECK(g_play_count == 1, "the failing sound was tried once");
    CHECK(g_log_count == 1 && strcmp(g_logged[0], "Selection sound unavailable") == 0,
          "and logged Selection sound unavailable");
    g_play_answer = true;
    sound_step(&s, LIST_MOVED, false, 2000);
    sound_step(&s, LIST_CONFIRM, true, 3000);
    sound_step(&s, LIST_NONE, true, 4000);
    CHECK(g_play_count == 1, "nothing is tried again for the rest of the session, even when play would work");
    CHECK(g_log_count == 1, "and nothing more is logged");
}

static void test_confirm_failure_disables(void)
{
    SoundState s;
    start(&s);
    g_play_answer = false;
    sound_step(&s, LIST_CONFIRM, true, 1000);
    CHECK(g_play_count == 1 && g_log_count == 1, "a failing confirm disables as well, with one line");
    g_play_answer = true;
    sound_step(&s, LIST_MOVED, false, 5000);
    CHECK(g_play_count == 1, "the move sound stays off");
}

static void test_init_again_re_enables(void)
{
    SoundState s;
    uint32_t move[1] = { MOVE };
    start(&s);
    g_play_answer = false;
    sound_step(&s, LIST_MOVED, false, 1000);
    start(&s);
    sound_step(&s, LIST_MOVED, false, 1010);
    CHECK(played_only(move, 1), "sound_init starts a new session: sounds are on and the clock is forgotten");
}

static void test_clock_going_back(void)
{
    SoundState s;
    start(&s);
    sound_step(&s, LIST_MOVED, false, 5000);
    sound_step(&s, LIST_MOVED, false, 100);
    CHECK(g_play_count == 2, "a clock that went back does not silence the cue until it catches up");
}

static void test_large_clock(void)
{
    SoundState s;
    start(&s);
    sound_step(&s, LIST_MOVED, false, 0xFFFFFFFFFFFFFF00ull);
    sound_step(&s, LIST_MOVED, false, 0xFFFFFFFFFFFFFF10ull);
    CHECK(g_play_count == 1, "a 64-bit clock near its limit throttles without wrapping");
    sound_step(&s, LIST_MOVED, false, 0xFFFFFFFFFFFFFF40ull);
    CHECK(g_play_count == 2, "and plays 64 ms on");
}

static void test_null_pieces(void)
{
    SoundState s;
    uint32_t move[1] = { MOVE };
    sound_step(NULL, LIST_MOVED, true, 1000);
    CHECK(true, "NULL state: nothing happens");
    sound_init(NULL, fake_play, fake_log);
    CHECK(true, "sound_init of NULL: nothing happens");

    start(&s);
    sound_init(&s, NULL, fake_log);
    sound_step(&s, LIST_MOVED, true, 1000);
    CHECK(g_play_count == 0 && g_log_count == 0, "no play function: silent, and nothing is logged");

    start(&s);
    sound_init(&s, fake_play, NULL);
    g_play_answer = false;
    sound_step(&s, LIST_MOVED, false, 1000);
    g_play_answer = true;
    sound_step(&s, LIST_MOVED, false, 2000);
    CHECK(g_play_count == 1 && g_log_count == 0, "no log function: the failure still disables, with nothing to write to");

    start(&s);
    sound_step(&s, LIST_MOVED, false, 1000);
    CHECK(played_only(move, 1), "(control) the state used above still works when started properly");
}

static void test_zeroed_state_is_silent(void)
{
    SoundState s;
    memset(&s, 0, sizeof s);
    g_play_count = 0;
    sound_step(&s, LIST_MOVED, true, 1000);
    CHECK(g_play_count == 0, "an all-zero state has no play function: silent");
}

int main(void)
{
    test_ids();
    test_move();
    test_first_move_any_clock();
    test_no_event();
    test_confirm_event_without_job();
    test_move_throttle();
    test_throttle_constant();
    test_confirm();
    test_confirm_without_event();
    test_confirm_ignores_throttle();
    test_confirm_resets_throttle();
    test_move_after_confirm_uses_its_clock();
    test_job_tick_has_no_move();
    test_log_once_and_disable();
    test_confirm_failure_disables();
    test_init_again_re_enables();
    test_clock_going_back();
    test_large_clock();
    test_null_pieces();
    test_zeroed_state_is_silent();
    printf("%s\n", test_failures() == 0 ? "PASS test_sound" : "FAIL test_sound");
    TEST_MAIN_END
}
