/* snapshot: what the game thread hands the render thread, and what the render thread hands back.
 *
 * Two threads share the mod. The game thread (HellForge's tick) reads the game, fills a DbfSnapshot and publishes it. The
 * render thread (the Goose Overlay Host's draw callbacks) draws the newest snapshot and posts UI events into a bounded
 * queue the game thread drains. The render thread never touches the game, and the game thread never touches the
 * Overlay Host.
 *
 * The snapshot is two buffers and an index. snap_publish copies into the buffer nobody can be reading (the one that is not
 * the newest), then swaps the index under a short lock; snap_acquire takes the lock only to read the index and mark the
 * buffer it returns as being read. A buffer being read is never written: when the render thread still holds the older
 * buffer at the moment the game thread wants it, that publish is skipped (counted by snap_skipped) rather than waited
 * for, and the newer snapshot is published at the next tick. So the game thread never blocks for long, and the render
 * thread always sees a whole snapshot, never a torn one.
 *
 * The queue is a ring of UI_QUEUE_SLOTS events with one producer (the render thread) and one consumer (the game thread),
 * under a lock: simple and obviously correct rather than lock-free. A full queue refuses the post and counts it.
 *
 * Call snap_init() once, from the game thread, before the render thread can call anything here. It also resets the
 * queue and both counters; calling it again while a thread is inside any other call here is not allowed. Before it, every
 * call is harmless and does nothing (acquire returns NULL, ui_post refuses, ui_drain returns 0).
 *
 * Portable C11: standard headers, platform.h, admission.h and game.h only. */
#ifndef DBF_SNAPSHOT_H
#define DBF_SNAPSHOT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "admission.h"
#include "game.h"

#define DBF_SNAP_REASON_SIZE 80 /* admit_reason and build_reason: a reason longer than 79 bytes is cut */
#define UI_QUEUE_SLOTS 64

typedef struct DbfSnapshot {
    uint64_t tick;
    GameView game;
    Admit admit[FEAT_COUNT];
    char admit_reason[FEAT_COUNT][DBF_SNAP_REASON_SIZE]; /* copies: admission's own strings die with its next call */
    bool build_ok;
    char build_reason[DBF_SNAP_REASON_SIZE];
    uint32_t host_version; /* the Overlay Host's OvApi.version; 0 when there is none */
} DbfSnapshot;

typedef struct UiEvent {
    uint32_t kind;
    int32_t a, b;
    float x, y;
} UiEvent;

void snap_init(void);

/* --- the snapshot ---------------------------------------------------------------------------------------------- */

/* Game thread: copies *s in as the newest snapshot. Skipped (and counted) when the render thread still reads the buffer it
 * would write; NULL is ignored. */
void snap_publish(const DbfSnapshot* s);

/* Render thread: the newest snapshot, or NULL before the first publish. It stays valid and unchanged until
 * snap_release (or the next snap_acquire). Acquire once per frame and release at its end; holding it for long makes the
 * game thread skip publishes. */
const DbfSnapshot* snap_acquire(void);
void snap_release(void);

/* Publishes skipped because the render thread held the buffer. */
uint32_t snap_skipped(void);

/* Game thread: fills build_ok, build_reason, admit[] and admit_reason[] from admission (adm_build_ok, adm_feature), copying
 * every reason. Other fields are left alone. NULL is ignored. */
void snap_fill_admission(DbfSnapshot* s);

/* Copies `src` (NULL: empty) into dst[size] and always terminates it, cutting src at size - 1 bytes when it is longer; size
 * 0 or a NULL dst does nothing. Bytes, not characters: the texts are ASCII. */
void snap_copy_text(char* dst, size_t size, const char* src);

/* --- the UI queue ---------------------------------------------------------------------------------------------- */

/* Render thread: queues a copy of *e. False (and counted in ui_dropped) when UI_QUEUE_SLOTS events are waiting; false and
 * not counted for NULL or before snap_init. */
bool ui_post(const UiEvent* e);

/* Game thread: moves up to `max` queued events, oldest first, into out; returns how many. */
int ui_drain(UiEvent* out, int max);

/* Posts refused because the queue was full. */
uint32_t ui_dropped(void);

#endif
