/* sound: see sound.h. */
#include <stddef.h>
#include "addresses_25480438.h"
#include "sound.h"

void sound_init(SoundState* s, bool (*play)(uint32_t id), void (*log)(const char* line))
{
    if (s == NULL) return;
    s->play = play;
    s->log = log;
    s->disabled = false;
    s->have_last = false;
    s->last_ms = 0;
}

/* Plays one sound; a failure turns the sounds off for the session, with one log line. True: it played. */
static bool play_one(SoundState* s, uint32_t id, uint64_t now)
{
    if (!s->play(id)) {
        s->disabled = true;
        if (s->log != NULL) s->log("Selection sound unavailable");
        return false;
    }
    s->have_last = true;
    s->last_ms = now;
    return true;
}

void sound_step(SoundState* s, ListEvent ev, bool job_started, uint64_t now)
{
    if (s == NULL || s->play == NULL || s->disabled) return;
    if (job_started) {
        (void)play_one(s, DBF_VAL_SOUND_CONFIRM, now);
        return;
    }
    if (ev != LIST_MOVED) return;
    if (s->have_last && now - s->last_ms < SOUND_MOVE_GAP_MS) return; /* a clock gone back wraps to a long gap: plays */
    (void)play_one(s, DBF_VAL_SOUND_MOVE, now);
}
