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
 * Call snap_init() once, from hellforge_mod_init (the loader's thread), before any tick or panel exists and so before the
 * game or render thread can call anything here. It also resets the queue and both counters; calling it again while a
 * thread is inside any other call here is not allowed. Before it, every call is harmless and does nothing (acquire
 * returns NULL, ui_post refuses, ui_drain returns 0).
 *
 * The list view (DbfSnapshot.list) is the data the Status tab’s entry lines use: the rows of the HUD list
 * in list order with their names, codes, eligibility and timers, which one is chosen, the state of the code entry, the
 * bindings and the settings file. snap_fill_list copies all of it on the game thread, as plain data (no pointer into
 * game memory or into another unit's state, and text in fixed fields), so the render thread draws it without calling
 * anything but the Overlay Host.
 *
 * Portable C11: standard headers, platform.h, admission.h, game.h, logic.h, entry.h, settings.h and text.h (the stratagem
 * names) only. */
#ifndef DBF_SNAPSHOT_H
#define DBF_SNAPSHOT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "admission.h"
#include "entry.h"
#include "game.h"
#include "logic.h"
#include "settings.h"

#define DBF_SNAP_REASON_SIZE 80 /* admit_reason and build_reason: a reason longer than 79 bytes is cut */
#define UI_QUEUE_SLOTS 64

#define DBF_LIST_ROWS ((int)DBF_VAL_CARD_COUNT) /* one row per card of the HUD list */
#define DBF_LIST_NAME_SIZE 48   /* a stratagem's name: the longest vanilla one is 38 bytes, "Stratagem 4294967295" 20 */
#define DBF_LIST_BIND_SIZE 24   /* a binding as the settings file spells it ("pad:dpad_right" is the longest, 14 bytes) */
#define DBF_LIST_STATUS_SIZE 64 /* bind_poll's status text */
#define DBF_LIST_FILE_SIZE 32   /* the settings file's name */

/* snap_fill_list hands logic_list_rows arrays of DBF_LIST_ROWS entries, and logic_list_rows writes LOGIC_LIST_ROWS into
 * each: they must have room for all of them. */
_Static_assert(DBF_LIST_ROWS >= LOGIC_LIST_ROWS, "snap_fill_list's arrays hold what logic_list_rows writes");

/* One row of the list. */
typedef struct ListRowView {
    uint32_t kind;
    char name[DBF_LIST_NAME_SIZE];
    uint8_t code[DBF_CODE_CAPACITY]; /* directions 1 up, 2 right, 3 down, 4 left, as DbfRow.code */
    uint8_t code_len;                /* at most DBF_CODE_CAPACITY; 0: no code */
    bool eligible;                   /* the row may be chosen (logic_list_rows) */
    DbfTimer timer;                  /* logic_timer of the row's timer block */
} ListRowView;

/* What the list and the entry status draw (see the top). Filled by snap_fill_list; all zero before that. */
typedef struct ListView {
    bool valid;                      /* snap_fill_list ran for this snapshot; nothing below means anything without it */
    bool enabled;                    /* the enabled setting: DBF is on */
    int row_count;                   /* rows[0..row_count) are in list order, the top of the list first */
    ListRowView rows[DBF_LIST_ROWS];
    int chosen;                      /* the chosen row's place in rows[] (not its index in GameView.rows); -1: none */
    EntryState entry_state;
    uint32_t entry_kind;             /* the job's stratagem */
    char entry_name[DBF_LIST_NAME_SIZE]; /* its name while the job runs, else "" */
    uint8_t entry_sent, entry_len;   /* directions sent, and the code's length */
    char entry_reason[DBF_REASON_SIZE];  /* why the job failed, "" otherwise */
    char bind_next[DBF_LIST_BIND_SIZE], bind_previous[DBF_LIST_BIND_SIZE], bind_confirm[DBF_LIST_BIND_SIZE];
    char bind_status[DBF_LIST_STATUS_SIZE]; /* bind_poll's status, "" when all is well */
    char settings_file[DBF_LIST_FILE_SIZE]; /* the settings file's name ("settings.ini"), "" when none was read */
    int settings_problems;           /* lines of the settings file that were not understood */
} ListView;

typedef struct DbfSnapshot {
    uint64_t tick;
    GameView game;
    Admit admit[FEAT_COUNT];
    char admit_reason[FEAT_COUNT][DBF_SNAP_REASON_SIZE]; /* copies: admission's own strings die with its next call */
    bool build_ok;
    char build_reason[DBF_SNAP_REASON_SIZE];
    uint32_t host_version; /* the Overlay Host's OvApi.version; 0 when there is none */
    ListView list; /* snap_fill_list fills it; until then it is all zero and not valid */
    uint16_t editor_pad; /* current controller buttons for binding capture */
    bool settings_save_failed;
    bool mcm_registered;
    DbfSettings options; /* game-thread copy of the currently applied preferences */
    char hud_status[192]; /* last engine-side HUD diagnostic */
    bool hud_owned;      /* native HUD bridge currently owns the display */
} DbfSnapshot;

enum { UI_HUD_OPTION = 1, UI_BINDING, UI_BLACKLIST }; /* a: option index / bind action / stratagem kind. Binding b packs kind:code (upper/lower 16 bits). */

typedef struct UiEvent {
    uint32_t kind;
    int32_t a, b;
    float x, y;
    uint64_t changed_rows, hidden_rows; /* one atomic blacklist edit; bits index dbf_blacklist_kinds */
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

/* Game thread: fills s->list from this tick's view; other fields are left alone, and the whole list view is rewritten
 * (nothing of an earlier fill stays). NULL `s` is ignored.
 *   v                 the tick's GameView (NULL: no rows). The rows are logic_list_rows(v, settings): every row in list
 *                     order, with its eligibility; at most DBF_LIST_ROWS.
 *   settings          the player's settings (NULL: DBF is not on, nothing is bound, no row is blacklisted)
 *   list              List Select's state after this tick's step; its choice shows only while it says the list is open
 *                     (NULL: nothing chosen). ListState.chosen indexes v->rows; the view stores the place in list order.
 *   job               the code entry's job (NULL: idle)
 *   bind_status       bind_poll's status text (NULL: "")
 *   settings_file     the settings file's name for the Status tab, with no path ("settings.ini"); NULL or "": no file was
 *                     read and the defaults are in use
 *   settings_problems settings_parse's count of lines that were not understood (a negative count is 0)
 * Names come from dbf_kind_name_copy, never from the static text of dbf_kind_name, which the render thread uses. */
void snap_fill_list(DbfSnapshot* s, const GameView* v, const DbfSettings* settings, const ListState* list,
                    const EntryJob* job, const char* bind_status, const char* settings_file, int settings_problems);

/* Copies `src` (NULL: empty) into dst[size] and always terminates it, cutting src at size - 1 bytes when it is longer; size
 * 0 or a NULL dst does nothing. Bytes, not characters: the texts are ASCII. */
void snap_copy_text(char* dst, size_t size, const char* src);

/* --- the UI queue ---------------------------------------------------------------------------------------------- */

/* Render thread: queues a copy of *e. False (and counted in ui_dropped) when UI_QUEUE_SLOTS events are waiting; false and
 * not counted for NULL or before snap_init. */
bool ui_post_batch(const UiEvent* events, int count);
bool ui_post(const UiEvent* e);

/* Game thread: moves up to `max` queued events, oldest first, into out; returns how many. */
int ui_drain(UiEvent* out, int max);

/* Posts refused because the queue was full. */
uint32_t ui_dropped(void);

#endif
