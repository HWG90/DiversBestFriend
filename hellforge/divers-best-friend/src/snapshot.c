/* snapshot: see snapshot.h. */
#include <string.h>
#include "platform.h"
#include "snapshot.h"

static bool g_locks_ready; /* the locks were initialised (once, ever: a lock is not initialised twice) */
static bool g_ready;       /* snap_init has run */

/* The snapshot. g_lock guards g_front, g_has, g_reading and g_skipped. The contents of a buffer are written only by
 * snap_publish, and only while the buffer is neither the newest (g_front) nor being read (g_reading): the reader can only
 * ever take g_front, so it cannot start reading the buffer being written, and the lock around the swap publishes the
 * written bytes to it. */
static DbfLock g_lock;
static DbfSnapshot g_buf[2];
static int g_front;   /* the newest buffer; meaningful when g_has */
static bool g_has;    /* something was published */
static int g_reading; /* the buffer snap_acquire handed out, -1 when none */
static uint32_t g_skipped;

/* The queue: a ring of UI_QUEUE_SLOTS under g_ui_lock. */
static DbfLock g_ui_lock;
static UiEvent g_queue[UI_QUEUE_SLOTS];
static int g_head, g_count;
static uint32_t g_dropped;

void snap_init(void)
{
    if (!g_locks_ready) {
        dbf_lock_init(&g_lock);
        dbf_lock_init(&g_ui_lock);
        g_locks_ready = true;
    }
    dbf_lock_enter(&g_lock);
    memset(g_buf, 0, sizeof g_buf);
    g_front = 0;
    g_has = false;
    g_reading = -1;
    g_skipped = 0;
    dbf_lock_leave(&g_lock);
    dbf_lock_enter(&g_ui_lock);
    memset(g_queue, 0, sizeof g_queue);
    g_head = 0;
    g_count = 0;
    g_dropped = 0;
    dbf_lock_leave(&g_ui_lock);
    g_ready = true;
}

void snap_publish(const DbfSnapshot* s)
{
    int target;
    bool busy;
    if (!g_ready || s == NULL) return;
    dbf_lock_enter(&g_lock);
    target = g_has ? 1 - g_front : 0; /* the buffer that is not the newest */
    busy = g_reading == target;
    if (busy) g_skipped++;
    dbf_lock_leave(&g_lock);
    if (busy) return;
    memcpy(&g_buf[target], s, sizeof *s);
    dbf_lock_enter(&g_lock);
    g_front = target;
    g_has = true;
    dbf_lock_leave(&g_lock);
}

const DbfSnapshot* snap_acquire(void)
{
    const DbfSnapshot* s = NULL;
    if (!g_ready) return NULL;
    dbf_lock_enter(&g_lock);
    if (g_has) {
        g_reading = g_front;
        s = &g_buf[g_front];
    } else {
        g_reading = -1;
    }
    dbf_lock_leave(&g_lock);
    return s;
}

void snap_release(void)
{
    if (!g_ready) return;
    dbf_lock_enter(&g_lock);
    g_reading = -1;
    dbf_lock_leave(&g_lock);
}

uint32_t snap_skipped(void)
{
    uint32_t n;
    if (!g_ready) return 0;
    dbf_lock_enter(&g_lock);
    n = g_skipped;
    dbf_lock_leave(&g_lock);
    return n;
}

void snap_copy_text(char* dst, size_t size, const char* src)
{
    size_t n = 0;
    if (dst == NULL || size == 0) return;
    if (src != NULL)
        while (n < size - 1 && src[n] != '\0') {
            dst[n] = src[n];
            n++;
        }
    dst[n] = '\0';
}

void snap_fill_admission(DbfSnapshot* s)
{
    const char* reason = NULL;
    if (s == NULL) return;
    s->build_ok = adm_build_ok(&reason);
    snap_copy_text(s->build_reason, sizeof s->build_reason, reason);
    for (int f = 0; f < FEAT_COUNT; f++) {
        reason = NULL;
        s->admit[f] = adm_feature((Feature)f, &reason);
        snap_copy_text(s->admit_reason[f], sizeof s->admit_reason[f], reason);
    }
}

bool ui_post(const UiEvent* e)
{
    bool taken = false;
    if (!g_ready || e == NULL) return false;
    dbf_lock_enter(&g_ui_lock);
    if (g_count < UI_QUEUE_SLOTS) {
        g_queue[(g_head + g_count) % UI_QUEUE_SLOTS] = *e;
        g_count++;
        taken = true;
    } else {
        g_dropped++;
    }
    dbf_lock_leave(&g_ui_lock);
    return taken;
}

int ui_drain(UiEvent* out, int max)
{
    int n;
    if (!g_ready || out == NULL || max <= 0) return 0;
    dbf_lock_enter(&g_ui_lock);
    n = g_count < max ? g_count : max;
    for (int i = 0; i < n; i++) out[i] = g_queue[(g_head + i) % UI_QUEUE_SLOTS];
    g_head = (g_head + n) % UI_QUEUE_SLOTS;
    g_count -= n;
    dbf_lock_leave(&g_ui_lock);
    return n;
}

uint32_t ui_dropped(void)
{
    uint32_t n;
    if (!g_ready) return 0;
    dbf_lock_enter(&g_ui_lock);
    n = g_dropped;
    dbf_lock_leave(&g_ui_lock);
    return n;
}
