/* sound: the selection sounds, ported from R46's feedback.lua:1-30 (UI-only sounds: a tick for each changed target, a cue
 * for each accepted job).
 *
 * The caller (dbf.c's tick) calls sound_step once per tick with what that tick did: the answer of logic_list_step, whether
 * a code entry was started (a List Confirm and a slot hotkey both count), and the clock in ms. The sound goes through
 * `play`, which dbf.c sets to nat_ui_sound: the game's own UI sound call, which checks the audio preconditions and the
 * SOUND feature itself.
 *   - Confirm (DBF_VAL_SOUND_CONFIRM) plays whenever a job started that tick, whatever the throttle, and restarts the
 *     throttle's clock (feedback.lua:15: play('confirm'); last_tick=now).
 *   - Move (DBF_VAL_SOUND_MOVE) plays on LIST_MOVED, except on a tick where a job started (feedback.lua:25's `not job`), and
 *     at most once every SOUND_MOVE_GAP_MS ms since the last sound of either kind that played. A move that is too soon is
 *     dropped, not played later. R46 also stayed quiet for the first target of a list just opened (`fresh and list_mode`,
 *     feedback.lua:25); logic_list_step makes that first choice without a LIST_MOVED, so it is silent here too.
 *   - The first `play` that answers false turns the sounds off until sound_init: R46 did the same on a failed pcall
 *     (feedback.lua:8-9), and its audio precondition asserts were such failures. One line, "Selection sound unavailable",
 *     goes to `log`; nat_ui_sound has logged its own reason ("sound skipped: ...") already.
 * A clock that goes back (never GetTickCount64's) counts as the gap having passed, so a bad clock cannot keep the sounds
 * off.
 *
 * The caller skips sound_step while the setting selection_sounds is off and while the SOUND feature is not admitted, so a
 * feature that is merely waiting or refused never reaches `play` and so never turns the sounds off for the session (R46
 * stepped feedback only while it was enabled, feedback.lua:12).
 *
 * Portable C11: standard headers and logic.h (ListEvent). Not thread-safe: only the game thread calls it. */
#ifndef DBF_SOUND_H
#define DBF_SOUND_H

#include <stdbool.h>
#include <stdint.h>
#include "logic.h"

/* The least time between two sounds when the second is a move: R46 feedback.lua:18 and 25 (`now-last_tick>=60`). */
#define SOUND_MOVE_GAP_MS 60u

typedef struct SoundState {
    bool (*play)(uint32_t id);       /* plays a UI sound; false: it could not (nat_ui_sound's answer) */
    void (*log)(const char* line);   /* takes one line, without a line end; NULL: none */
    bool disabled;                   /* a play answered false: no more sounds this session */
    bool have_last;                  /* a sound has played since sound_init */
    uint64_t last_ms;                /* when the last one played */
} SoundState;

/* Starts a session: sounds on, no sound played yet. A NULL `play` plays nothing (and logs nothing); a NULL `log` is none.
 * NULL `s` is ignored. */
void sound_init(SoundState* s, bool (*play)(uint32_t id), void (*log)(const char* line));

/* One tick (see above). `ev` is logic_list_step's answer, `job_started` whether a code entry began this tick, `now` the
 * game thread's clock in ms. NULL `s`, a state that was never initialised (no play function) or a disabled one: nothing. */
void sound_step(SoundState* s, ListEvent ev, bool job_started, uint64_t now);

#endif
