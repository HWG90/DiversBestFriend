/* flags: -DDBF_TEST_WITNESSES */
/* Tests for src/snapshot.c: the double-buffered snapshot (game thread publishes, render thread acquires and releases),
 * the 64-slot UI queue (render thread posts, game thread drains), the copies of the admission reasons, and the safe text
 * copy. The two-thread cases run real threads. snapshot.c keeps its state in statics, so each test starts with
 * snap_init(); test_before_init must run first, while nothing has been started. Admission runs for real over the
 * synthetic game image with the small witness table of tests/test_witnesses.h (alpha gates STATE and HUD_READ, bravo
 * STRATAGEMS, charlie HUD_READ and POINTING, delta SOUND; nothing maps the other features). The capturing flag (the render
 * thread says a host window is open, the game thread reads it) is tested here as well: it shares the snapshot's lock. */
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "entry.h"
#include "logic.h"
#include "memory.h"
#include "settings.h"
#include "snapshot.h"
#include "synthetic.h"
#include "test.h"
#include "ui_settings.h"

#define GRACE_OVER 30000u

/* A snapshot every byte of which follows from `n`, so a torn copy shows. */
static void fill(DbfSnapshot* s, uint64_t n)
{
    memset(s, 0, sizeof *s);
    s->tick = n;
    s->host_version = (uint32_t)n;
    s->build_ok = (n & 1u) != 0;
    s->game.row_count = (int)(n % (DBF_VAL_CARD_COUNT + 1u));
    for (int i = 0; i < DBF_VAL_CARD_COUNT; i++) {
        s->game.rows[i].kind = (uint32_t)n + (uint32_t)i;
        s->game.rows[i].entry = (uint32_t)(n * 3u) + (uint32_t)i;
        memset(s->game.rows[i].timer, (int)((n + (uint64_t)i) & 0xffu), sizeof s->game.rows[i].timer);
    }
    memset(s->game.reason, 'a' + (int)(n % 26u), sizeof s->game.reason - 1);
    for (int f = 0; f < FEAT_COUNT; f++) {
        s->admit[f] = (Admit)((n + (uint64_t)f) % 3u);
        memset(s->admit_reason[f], 'A' + (int)((n + (uint64_t)f) % 26u), sizeof s->admit_reason[f] - 1);
    }
    memset(s->build_reason, 'x', sizeof s->build_reason - 1);
}

static bool consistent(const DbfSnapshot* s)
{
    DbfSnapshot expected;
    fill(&expected, s->tick);
    return memcmp(&expected, s, sizeof expected) == 0;
}

static DbfSnapshot g_src;

static void publish(uint64_t n)
{
    fill(&g_src, n);
    snap_publish(&g_src);
}

/* --- tests ----------------------------------------------------------------------------------------------------- */

static void test_before_init(void)
{
    DbfSnapshot s;
    UiEvent e = { 1, 2, 3, 0.5f, 0.25f }, out[2];
    CHECK(snap_acquire() == NULL, "before snap_init, acquire has nothing");
    snap_release();
    CHECK(true, "before snap_init, release is harmless");
    fill(&s, 1);
    snap_publish(&s);
    CHECK(snap_acquire() == NULL, "before snap_init, publish is ignored");
    CHECK(!ui_post(&e), "before snap_init, ui_post refuses");
    CHECK(ui_drain(out, 2) == 0, "before snap_init, ui_drain returns nothing");
    snap_set_capturing(true);
    CHECK(!snap_capturing(), "before snap_init, the capturing flag is false and set ignores true");
}

static void test_publish_acquire(void)
{
    const DbfSnapshot* s;
    snap_init();
    CHECK(snap_acquire() == NULL, "nothing published: acquire is NULL");
    snap_release();
    publish(1);
    publish(2);
    s = snap_acquire();
    CHECK(s != NULL && s->tick == 2, "publish A then B, acquire gives B");
    CHECK(s != NULL && consistent(s), "and B is whole");
    snap_release();
    s = snap_acquire();
    CHECK(s != NULL && s->tick == 2, "acquire again gives B again");
    snap_release();
    CHECK(snap_skipped() == 0, "nothing was skipped");
}

static void test_publish_copies(void)
{
    const DbfSnapshot* s;
    snap_init();
    fill(&g_src, 7);
    snap_publish(&g_src);
    g_src.tick = 999;
    memset(g_src.game.reason, 'z', 10);
    s = snap_acquire();
    CHECK(s != NULL && s->tick == 7 && consistent(s), "publish copies by value: later edits of the source do not show");
    CHECK(s != &g_src, "and the reader gets the module's own copy");
    snap_release();
}

static void test_publish_while_reading(void)
{
    const DbfSnapshot* b;
    const DbfSnapshot* c;
    snap_init();
    publish(1);
    publish(2);
    b = snap_acquire();
    CHECK(b != NULL && b->tick == 2, "reading B");
    publish(3);
    CHECK(b->tick == 2 && consistent(b), "publish C while B is read: B is still whole and unchanged");
    CHECK(snap_skipped() == 0, "C had a free buffer: nothing skipped");
    snap_release();
    c = snap_acquire();
    CHECK(c != NULL && c->tick == 3 && consistent(c), "after release, acquire gives C");
    CHECK(c != b, "C lives in the other buffer");
    snap_release();
}

static void test_skipped_publish(void)
{
    const DbfSnapshot* a;
    const DbfSnapshot* now;
    snap_init();
    publish(1);
    a = snap_acquire(); /* holds the buffer A is in */
    CHECK(a != NULL && a->tick == 1, "reading A");
    publish(2);        /* goes to the free buffer: fine */
    CHECK(snap_skipped() == 0, "B had a free buffer");
    publish(3);        /* the free buffer is the one A is read from: skipped */
    CHECK(snap_skipped() == 1, "C is skipped while A is still read and B is the newest");
    publish(4);
    CHECK(snap_skipped() == 2, "so is D");
    CHECK(a->tick == 1 && consistent(a), "the reader's buffer was never written");
    snap_release();
    now = snap_acquire();
    CHECK(now != NULL && now->tick == 2, "the newest is still B: the skipped ones are gone, not queued");
    snap_release();
    publish(5);
    CHECK(snap_skipped() == 2, "after release a publish goes through");
    now = snap_acquire();
    CHECK(now != NULL && now->tick == 5 && consistent(now), "and is the one acquired next");
    snap_release();
    snap_init();
    CHECK(snap_skipped() == 0, "snap_init clears the skip count");
}

static void test_acquire_again_without_release(void)
{
    const DbfSnapshot* first;
    const DbfSnapshot* second;
    snap_init();
    publish(1);
    first = snap_acquire();
    publish(2);
    second = snap_acquire(); /* the reader moves on to B without releasing A: A is no longer protected */
    CHECK(first != NULL && second != NULL && second->tick == 2, "acquire without release moves to the newest");
    publish(3);
    CHECK(snap_skipped() == 0, "the buffer left behind is free for the next publish");
    CHECK(second->tick == 2 && consistent(second), "and the one now read is whole");
    snap_release();
}

typedef struct {
    atomic_int done;
    uint64_t published;
} WriterState;

static void* writer_main(void* arg)
{
    WriterState* w = arg;
    DbfSnapshot s;
    for (uint64_t n = 1; n <= 200000; n++) {
        fill(&s, n);
        snap_publish(&s);
        w->published = n;
    }
    atomic_store(&w->done, 1);
    return NULL;
}

static void test_two_threads(void)
{
    WriterState w = { 0, 0 };
    pthread_t thread;
    uint64_t last = 0, reads = 0, torn = 0, moved = 0, backwards = 0;
    snap_init();
    if (pthread_create(&thread, NULL, writer_main, &w) != 0) {
        CHECK(false, "the writer thread started");
        return;
    }
    while (!atomic_load(&w.done)) {
        const DbfSnapshot* s = snap_acquire();
        if (s) {
            uint64_t tick = s->tick;
            volatile int spin = 0;
            reads++;
            if (!consistent(s)) torn++;
            if (tick < last) backwards++;
            last = tick;
            while (spin < 300) spin++; /* hold it while the writer keeps going */
            if (s->tick != tick || !consistent(s)) moved++;
        }
        snap_release();
    }
    pthread_join(thread, NULL);
    printf("  reader: %llu reads, writer: %llu publishes, %u skipped\n", (unsigned long long)reads,
        (unsigned long long)w.published, (unsigned)snap_skipped());
    CHECK(reads > 0, "the reader saw snapshots while the writer ran");
    CHECK(torn == 0, "every snapshot read was whole");
    CHECK(moved == 0, "no snapshot changed while it was held");
    CHECK(backwards == 0, "ticks never went backwards");
    {
        const DbfSnapshot* s = snap_acquire();
        CHECK(s != NULL && s->tick + snap_skipped() >= 1 && consistent(s), "the last snapshot is whole");
        snap_release();
    }
}

static void test_queue_basics(void)
{
    UiEvent e, out[80];
    int n;
    snap_init();
    CHECK(ui_drain(out, 80) == 0, "an empty queue drains nothing");
    CHECK(ui_dropped() == 0, "nothing dropped yet");
    for (int i = 0; i < 64; i++) {
        e = (UiEvent){ (uint32_t)i + 100u, i, -i, (float)i, (float)i * 2.0f };
        if (!ui_post(&e)) {
            CHECK(false, "the first 64 posts are accepted");
            return;
        }
    }
    CHECK(true, "the first 64 posts are accepted");
    e = (UiEvent){ 999, 0, 0, 0, 0 };
    CHECK(!ui_post(&e), "the 65th post is refused");
    CHECK(ui_dropped() == 1, "and counted");
    CHECK(!ui_post(&e), "so is the 66th");
    CHECK(ui_dropped() == 2, "and counted");
    n = ui_drain(out, 80);
    CHECK(n == 64, "65 posts without a drain: 64 drained");
    {
        bool ordered = true;
        for (int i = 0; i < n; i++)
            if (out[i].kind != (uint32_t)i + 100u || out[i].a != i || out[i].b != -i || out[i].x != (float)i
                || out[i].y != (float)i * 2.0f)
                ordered = false;
        CHECK(ordered, "in order, every field intact");
    }
    CHECK(ui_drain(out, 80) == 0, "and then it is empty");
    CHECK(ui_dropped() == 2, "the drop count stays");
    CHECK(ui_post(&e), "a drained queue takes posts again");
    snap_init();
    CHECK(ui_dropped() == 0, "snap_init clears the drop count");
    CHECK(ui_drain(out, 80) == 0, "and the queue");
}

static void test_queue_wrap_and_limits(void)
{
    UiEvent e = { 0 }, out[80];
    int next = 0, expect = 0;
    bool ordered = true;
    snap_init();
    /* 5 rounds of 50 posts and 50 drained, so the ring wraps; every other drain takes at most 7. */
    for (int round = 0; round < 5; round++) {
        for (int i = 0; i < 50; i++) {
            e.a = next++;
            if (!ui_post(&e)) ordered = false;
        }
        for (;;) {
            int n = ui_drain(out, round % 2 ? 7 : 80);
            if (n == 0) break;
            if (n > (round % 2 ? 7 : 80)) ordered = false;
            for (int i = 0; i < n; i++)
                if (out[i].a != expect++) ordered = false;
        }
    }
    CHECK(ordered && expect == next, "the ring wraps and keeps order under partial drains");
    CHECK(ui_dropped() == 0, "without drops");
    e.a = 1;
    ui_post(&e);
    e.a = 2;
    ui_post(&e);
    CHECK(ui_drain(out, 0) == 0, "max 0 drains nothing");
    CHECK(ui_drain(NULL, 5) == 0, "a NULL output drains nothing");
    CHECK(ui_drain(out, 1) == 1 && out[0].a == 1, "max 1 takes the first");
    CHECK(ui_drain(out, 80) == 1 && out[0].a == 2, "and the second stays");
    CHECK(!ui_post(NULL), "a NULL event is refused");
    CHECK(ui_dropped() == 0, "and is not counted as a full queue");
}

typedef struct {
    atomic_int done;
    int accepted, refused;
} ProducerState;

static void* producer_main(void* arg)
{
    ProducerState* p = arg;
    UiEvent e = { 0 };
    for (int i = 0; i < 100000; i++) {
        e.a = i;
        if (ui_post(&e)) p->accepted++;
        else p->refused++;
    }
    atomic_store(&p->done, 1);
    return NULL;
}

static void test_queue_two_threads(void)
{
    ProducerState p = { 0, 0, 0 };
    pthread_t thread;
    UiEvent out[16];
    int received = 0, last = -1;
    bool ordered = true;
    snap_init();
    if (pthread_create(&thread, NULL, producer_main, &p) != 0) {
        CHECK(false, "the producer thread started");
        return;
    }
    for (;;) {
        bool finished = atomic_load(&p.done) != 0; /* read before draining: whatever it posted is then in the queue */
        int n = ui_drain(out, 16);
        for (int i = 0; i < n; i++) {
            if (out[i].a <= last) ordered = false;
            last = out[i].a;
            received++;
        }
        if (finished && n == 0) break;
    }
    pthread_join(thread, NULL);
    printf("  producer: %d accepted, %d refused\n", p.accepted, p.refused);
    CHECK(received == p.accepted, "every accepted event was received exactly once");
    CHECK(ordered, "in the order posted");
    CHECK((uint32_t)p.refused == ui_dropped(), "and every refusal was counted");
}

static const DbfWitness* witness(const char* name)
{
    for (int i = 0; i < dbf_witness_count; i++)
        if (strcmp(dbf_witnesses[i].name, name) == 0) return &dbf_witnesses[i];
    return NULL;
}

static bool start_scene(void)
{
    SynScene scene;
    bool built;
    syn_default(&scene);
    built = syn_build(&scene);
    mem_init(syn_mem_port());
    adm_init(syn_adm_port(), 0);
    return built;
}

static bool reason_is(const char* have, const char* want)
{
    if (strcmp(have, want) == 0) return true;
    printf("  reason was \"%s\", expected \"%s\"\n", have, want);
    return false;
}

static void test_fill_before_adm_init(void)
{
    DbfSnapshot s;
    bool all = true;
    memset(&s, 0xa5, sizeof s);
    snap_fill_admission(&s);
    CHECK(!s.build_ok, "before adm_init the build is not ok");
    CHECK(reason_is(s.build_reason, "not started"), "and says it has not started");
    for (int f = 0; f < FEAT_COUNT; f++)
        if (s.admit[f] != ADMIT_PENDING || strcmp(s.admit_reason[f], "not started") != 0) all = false;
    CHECK(all, "every feature is pending, not started");
}

static void test_fill_admission(void)
{
    DbfSnapshot s;
    bool same = true;
    CHECK(start_scene(), "the synthetic scene was built");
    memset(&s, 0xa5, sizeof s);
    snap_fill_admission(&s);
    CHECK(s.build_ok, "the build is ok");
    CHECK(reason_is(s.build_reason, ""), "with no reason");
    CHECK(s.admit[FEAT_STATE] == ADMIT_OK && reason_is(s.admit_reason[FEAT_STATE], ""), "STATE is admitted, no reason");
    CHECK(s.admit[FEAT_STRATAGEMS] == ADMIT_OK, "STRATAGEMS is admitted");
    CHECK(s.admit[FEAT_WEAPON] == ADMIT_REFUSED && reason_is(s.admit_reason[FEAT_WEAPON], "not mapped yet"),
        "WEAPON has no witness: refused, not mapped yet");
    for (int f = 0; f < FEAT_COUNT; f++) {
        const char* reason = NULL;
        Admit a = adm_feature((Feature)f, &reason);
        if (s.admit[f] != a || strcmp(s.admit_reason[f], reason) != 0) same = false;
    }
    CHECK(same, "every feature matches adm_feature, status and reason");
}

static void test_fill_admission_reasons(void)
{
    DbfSnapshot s;
    const DbfWitness* bravo = witness("bravo");
    const DbfWitness* charlie = witness("charlie");
    CHECK(start_scene() && bravo && charlie, "the scene and the witnesses are there");
    syn_poke_u8(SYN_GAME_BASE + charlie->rva, (uint8_t)(charlie->bytes[0] ^ 0x55u));
    adm_init(syn_adm_port(), 0);
    snap_fill_admission(&s);
    CHECK(s.admit[FEAT_HUD_READ] == ADMIT_PENDING && reason_is(s.admit_reason[FEAT_HUD_READ], "witness charlie differs (retrying)"),
        "a witness that differs within the grace period: pending, retrying");
    syn_poke_u8(SYN_GAME_BASE + bravo->rva, (uint8_t)(bravo->bytes[0] ^ 0x55u));
    adm_init(syn_adm_port(), 0);
    adm_tick(GRACE_OVER);
    snap_fill_admission(&s);
    CHECK(s.admit[FEAT_STRATAGEMS] == ADMIT_REFUSED && reason_is(s.admit_reason[FEAT_STRATAGEMS], "witness bravo differs"),
        "past the grace period: refused");
    /* Admission's reason pointers die with its next call; the snapshot's copies must not. */
    adm_init(syn_adm_port(), 0);
    CHECK(reason_is(s.admit_reason[FEAT_STRATAGEMS], "witness bravo differs"),
        "the copy outlives the next admission call");
}

static void test_copy_text(void)
{
    char field[80 + 8];
    char longer[200];
    memset(longer, 'q', sizeof longer - 1);
    longer[sizeof longer - 1] = '\0';

    memset(field, 0x7e, sizeof field);
    snap_copy_text(field, 80, "short");
    CHECK(strcmp(field, "short") == 0, "a short text is copied whole");
    CHECK(field[80] == 0x7e && field[87] == 0x7e, "and nothing past the field is touched");

    memset(field, 0x7e, sizeof field);
    snap_copy_text(field, 80, longer);
    CHECK(strlen(field) == 79, "an over-long text is cut to 79 characters");
    CHECK(field[79] == '\0', "with its terminator");
    CHECK(memcmp(field, longer, 79) == 0, "keeping the start");
    CHECK(field[80] == 0x7e && field[87] == 0x7e, "and nothing past the field is touched");

    memset(field, 0x7e, sizeof field);
    memset(longer, 'r', 79);
    longer[79] = '\0';
    snap_copy_text(field, 80, longer);
    CHECK(strlen(field) == 79 && field[80] == 0x7e, "a text of exactly 79 fits");

    memset(field, 0x7e, sizeof field);
    snap_copy_text(field, 80, NULL);
    CHECK(field[0] == '\0', "NULL gives an empty text");

    memset(field, 0x7e, sizeof field);
    snap_copy_text(field, 1, "abc");
    CHECK(field[0] == '\0' && field[1] == 0x7e, "a field of one holds only the terminator");

    memset(field, 0x7e, sizeof field);
    snap_copy_text(field, 0, "abc");
    CHECK(field[0] == 0x7e, "a field of zero is not touched");
    snap_copy_text(NULL, 5, "abc");
    CHECK(true, "a NULL field is ignored");
}

/* --- the capturing flag ---------------------------------------------------------------------------------------- */

static void test_capturing_flag(void)
{
    snap_init();
    CHECK(!snap_capturing(), "after snap_init, nothing is capturing");
    snap_set_capturing(true);
    CHECK(snap_capturing(), "set true: capturing");
    snap_set_capturing(true);
    CHECK(snap_capturing(), "set true again: still capturing");
    publish(1);
    (void)snap_acquire();
    snap_release();
    CHECK(snap_capturing(), "publishing, acquiring and releasing leave it alone");
    snap_set_capturing(false);
    CHECK(!snap_capturing(), "set false: not capturing");
    snap_set_capturing(true);
    snap_init();
    CHECK(!snap_capturing(), "snap_init puts it back to false");
}

static void* capturing_writer(void* arg)
{
    for (int i = 0; i < 20000; i++) snap_set_capturing((i & 1) == 0);
    snap_set_capturing(true);
    return arg;
}

static void test_capturing_two_threads(void)
{
    pthread_t thread;
    int reads = 0;
    snap_init();
    pthread_create(&thread, NULL, capturing_writer, NULL);
    for (int i = 0; i < 20000; i++) reads += snap_capturing() ? 1 : 0; /* either value, never a crash or a torn read */
    pthread_join(thread, NULL);
    CHECK(snap_capturing(), "after a render thread toggled it thousands of times, the last value it stored is read");
    CHECK(reads >= 0, "reading it while the render thread writes does not fail");
}

static void test_snapshot_field_sizes(void)
{
    DbfSnapshot s;
    CHECK(sizeof s.admit_reason[0] == 80, "admission reasons have 80 bytes each");
    CHECK(sizeof s.build_reason == 80, "and so does the build reason");
}


/* --- snap_fill_list ---------------------------------------------------------------------------------------------- */

static void put_u32(uint8_t* block, size_t off, uint32_t v) { memcpy(block + off, &v, sizeof v); }

/* An active row of `kind` on card `card` at list position `y`, with a code of n directions; its timer block is idle. */
static DbfRow list_row(uint32_t kind, uintptr_t card, float y, const uint8_t* code, int n)
{
    DbfRow r;
    memset(&r, 0, sizeof r);
    r.card = card;
    r.list_y = y;
    r.kind = kind;
    r.active = true;
    r.code_len = (uint8_t)n;
    if (n > 0) memcpy(r.code, code, (size_t)n > sizeof r.code ? sizeof r.code : (size_t)n);
    put_u32(r.timer, DBF_OFF_CARD_TIMER_KIND_OFFSET, kind);
    return r;
}

/* Three cards: A (kind 3, y 1) is the lowest, B (kind 118, y 3) the top, C (kind 150, y 2) in between. List order: B, C, A. */
static void list_view(GameView* v)
{
    static const uint8_t a[5] = { 1, 2, 3, 3, 3 };
    static const uint8_t b[3] = { 2, 2, 1 };
    memset(v, 0, sizeof *v);
    v->in_gameplay = true;
    v->hud_ready = true;
    v->menu_open = true;
    v->row_count = 3;
    v->rows[0] = list_row(3, 0x1000, 1.0f, a, 5);
    v->rows[1] = list_row(118, 0x2000, 3.0f, b, 3);
    v->rows[2] = list_row(150, 0x3000, 2.0f, NULL, 0);
}

static DbfSettings g_list_settings;

static void fill_list(DbfSnapshot* s, const GameView* v, const ListState* l, const EntryJob* job)
{
    snap_fill_list(s, v, &g_list_settings, l, job, "", "settings.ini", 0);
}

static void test_fill_list_rows(void)
{
    DbfSnapshot s;
    GameView v;
    list_view(&v);
    settings_defaults(&g_list_settings);
    memset(&s, 0xa5, sizeof s);
    s.tick = 77;
    fill_list(&s, &v, NULL, NULL);
    CHECK(s.list.valid && s.list.enabled, "the list view is filled, and DBF is on");
    CHECK(s.list.row_count == 3, "three rows");
    CHECK(strcmp(s.list.rows[0].name, "Orbital Precision Strike") == 0 && s.list.rows[0].kind == 118, "the top card comes first");
    CHECK(strcmp(s.list.rows[1].name, "Stratagem 150") == 0 && s.list.rows[1].kind == 150, "then the one in between");
    CHECK(strcmp(s.list.rows[2].name, "Eagle 500kg Bomb") == 0 && s.list.rows[2].kind == 3, "then the lowest");
    CHECK(s.list.rows[0].code_len == 3 && s.list.rows[0].code[0] == 2 && s.list.rows[0].code[2] == 1, "a row keeps its code");
    CHECK(s.list.rows[2].code_len == 5 && s.list.rows[2].code[4] == 3, "all five directions of the other");
    CHECK(s.list.rows[1].code_len == 0, "a row with no code has none");
    CHECK(s.list.rows[0].eligible && s.list.rows[1].eligible && s.list.rows[2].eligible, "all three can be chosen");
    CHECK(s.list.rows[3].name[0] == '\0' && s.list.rows[3].kind == 0 && !s.list.rows[3].eligible && s.list.rows[15].code_len == 0,
          "rows past the count are empty (the view was cleared, not merged)");
    CHECK(s.tick == 77, "the rest of the snapshot is left alone");
}

static void test_fill_list_eligibility_and_timers(void)
{
    DbfSnapshot s;
    GameView v;
    list_view(&v);
    settings_defaults(&g_list_settings);
    /* C (kind 150) on a 45 s cooldown, A (kind 3) unavailable, B hidden by the blacklist. */
    put_u32(v.rows[2].timer, DBF_OFF_CARD_TIMER_STATE_OFFSET, DBF_VAL_TIMER_STATE_COOLDOWN);
    {
        float seconds = 44.2f;
        memcpy(v.rows[2].timer + DBF_OFF_CARD_TIMER_COOLDOWN_SECONDS_OFFSET, &seconds, sizeof seconds);
    }
    put_u32(v.rows[0].timer, DBF_OFF_CARD_TIMER_STATE_OFFSET, DBF_VAL_TIMER_STATE_UNAVAILABLE);
    g_list_settings.blacklist_kind[118] = true;
    fill_list(&s, &v, NULL, NULL);
    CHECK(!s.list.rows[0].eligible, "a blacklisted kind is shown but cannot be chosen");
    CHECK(!s.list.rows[1].eligible && s.list.rows[1].timer.valid && s.list.rows[1].timer.cooldown &&
              s.list.rows[1].timer.seconds == 45,
          "a cooldown: not eligible, its seconds rounded up");
    CHECK(!s.list.rows[2].eligible && s.list.rows[2].timer.unavailable, "an unavailable card: not eligible, flagged");
    CHECK(s.list.rows[0].timer.valid && !s.list.rows[0].timer.cooldown && !s.list.rows[0].timer.unavailable,
          "a row with no timer has a valid, empty one");

    list_view(&v);
    v.rows[0].kind = 0; /* a card whose entry is not in the payload */
    settings_defaults(&g_list_settings);
    fill_list(&s, &v, NULL, NULL);
    CHECK(!s.list.rows[2].eligible, "kind 0 cannot be chosen");
}

static void test_fill_list_chosen(void)
{
    DbfSnapshot s;
    GameView v;
    ListState l;
    list_view(&v);
    settings_defaults(&g_list_settings);
    memset(&l, 0, sizeof l);
    l.was_open = true;
    l.chosen = 2; /* GameView.rows[2]: kind 150, second in list order */
    fill_list(&s, &v, &l, NULL);
    CHECK(s.list.chosen == 1, "chosen is the place in list order, not the index in GameView.rows");
    l.chosen = 1;
    fill_list(&s, &v, &l, NULL);
    CHECK(s.list.chosen == 0, "the top card is place 0");
    l.chosen = 0;
    fill_list(&s, &v, &l, NULL);
    CHECK(s.list.chosen == 2, "the lowest is place 2");
    l.chosen = -1;
    fill_list(&s, &v, &l, NULL);
    CHECK(s.list.chosen == -1, "nothing chosen");
    l.chosen = 3;
    fill_list(&s, &v, &l, NULL);
    CHECK(s.list.chosen == -1, "a choice past the rows is none");
    l.chosen = 0;
    l.was_open = false;
    fill_list(&s, &v, &l, NULL);
    CHECK(s.list.chosen == -1, "a state the list was not open in has no choice");
    fill_list(&s, &v, NULL, NULL);
    CHECK(s.list.chosen == -1, "no list state: none");
}

static void test_fill_list_settings(void)
{
    DbfSnapshot s;
    GameView v;
    list_view(&v);
    settings_defaults(&g_list_settings);
    fill_list(&s, &v, NULL, NULL);
    CHECK(strcmp(s.list.bind_next, "wheel_down") == 0 && strcmp(s.list.bind_previous, "wheel_up") == 0 &&
              strcmp(s.list.bind_confirm, "mouse1") == 0,
          "the default bindings, spelt as settings.ini spells them");
    g_list_settings.bind[BIND_NEXT] = (Binding){ BIND_KEY, 'E' };
    g_list_settings.bind[BIND_CONFIRM].kind = BIND_NONE;
    g_list_settings.bind[BIND_CONFIRM].code = 0;
    g_list_settings.enabled = false;
    fill_list(&s, &v, NULL, NULL);
    CHECK(strcmp(s.list.bind_next, "key:e") == 0 && strcmp(s.list.bind_confirm, "none") == 0, "a key; an unbound action reads none");
    CHECK(!s.list.enabled && s.list.valid, "the enabled setting is copied (the list is filled either way)");

    snap_fill_list(&s, &v, NULL, NULL, NULL, NULL, NULL, 0);
    CHECK(s.list.valid && !s.list.enabled, "no settings: DBF is not on");
    CHECK(strcmp(s.list.bind_next, "none") == 0 && strcmp(s.list.bind_previous, "none") == 0 &&
              strcmp(s.list.bind_confirm, "none") == 0,
          "and nothing is bound");
    CHECK(s.list.row_count == 3, "the rows are still listed");
}

static void test_fill_list_texts(void)
{
    DbfSnapshot s;
    GameView v;
    char big[400];
    list_view(&v);
    settings_defaults(&g_list_settings);
    snap_fill_list(&s, &v, &g_list_settings, NULL, NULL, "wheel bindings need Overlay Host 0.5.0", "settings.ini", 3);
    CHECK(strcmp(s.list.bind_status, "wheel bindings need Overlay Host 0.5.0") == 0, "the bindings status is copied");
    CHECK(strcmp(s.list.settings_file, "settings.ini") == 0 && s.list.settings_problems == 3, "the file name and the problem count");
    snap_fill_list(&s, &v, &g_list_settings, NULL, NULL, NULL, NULL, -2);
    CHECK(s.list.bind_status[0] == '\0' && s.list.settings_file[0] == '\0', "NULL texts are empty");
    CHECK(s.list.settings_problems == 0, "a negative problem count is stored as 0");
    memset(big, 'z', sizeof big - 1);
    big[sizeof big - 1] = '\0';
    snap_fill_list(&s, &v, &g_list_settings, NULL, NULL, big, big, 1);
    CHECK(strlen(s.list.bind_status) == sizeof s.list.bind_status - 1 && strlen(s.list.settings_file) == sizeof s.list.settings_file - 1,
          "long texts are cut to their fields, terminated");
}

static void test_fill_list_entry(void)
{
    DbfSnapshot s;
    GameView v;
    EntryJob job;
    list_view(&v);
    settings_defaults(&g_list_settings);
    fill_list(&s, &v, NULL, NULL);
    CHECK(s.list.entry_state == ENTRY_IDLE && s.list.entry_sent == 0 && s.list.entry_len == 0, "no job: idle");

    memset(&job, 0, sizeof job);
    job.state = ENTRY_RUNNING;
    job.kind = 118;
    job.sent = 2;
    job.code.len = 5;
    fill_list(&s, &v, NULL, &job);
    CHECK(s.list.entry_state == ENTRY_RUNNING && s.list.entry_kind == 118 && s.list.entry_sent == 2 && s.list.entry_len == 5,
          "a running job: its kind, the directions sent and the code's length");
    CHECK(strcmp(s.list.entry_name, "Orbital Precision Strike") == 0, "and the stratagem's name");

    job.state = ENTRY_FAILED;
    snap_copy_text(job.reason, sizeof job.reason, "menu closed");
    fill_list(&s, &v, NULL, &job);
    CHECK(s.list.entry_state == ENTRY_FAILED && strcmp(s.list.entry_reason, "menu closed") == 0, "a failed job: its reason");

    job.state = ENTRY_DONE;
    job.reason[0] = '\0';
    fill_list(&s, &v, NULL, &job);
    CHECK(s.list.entry_state == ENTRY_DONE && s.list.entry_reason[0] == '\0', "a finished job");

    memset(&job, 0, sizeof job);
    fill_list(&s, &v, NULL, &job);
    CHECK(s.list.entry_state == ENTRY_IDLE && s.list.entry_name[0] == '\0', "an idle job has no name");
}

static void test_fill_list_limits(void)
{
    DbfSnapshot s;
    GameView v;
    list_view(&v);
    settings_defaults(&g_list_settings);
    v.rows[0].code_len = 200;
    fill_list(&s, &v, NULL, NULL);
    CHECK(s.list.rows[2].code_len == DBF_CODE_CAPACITY, "a code length past the array is cut to it");

    memset(&v, 0, sizeof v);
    for (int i = 0; i < 16; i++) {
        v.rows[i] = list_row(20u + (uint32_t)i, 0x1000u + (uintptr_t)i * 0x100, (float)(16 - i), NULL, 0);
    }
    v.row_count = 16;
    fill_list(&s, &v, NULL, NULL);
    CHECK(s.list.row_count == 16 && s.list.rows[0].kind == 20 && s.list.rows[15].kind == 35, "sixteen rows, top first");

    v.row_count = 99;
    fill_list(&s, &v, NULL, NULL);
    CHECK(s.list.row_count == 16, "a row count past sixteen is cut");
    v.row_count = -4;
    fill_list(&s, &v, NULL, NULL);
    CHECK(s.list.row_count == 0 && s.list.valid, "a negative one is none");

    snap_fill_list(&s, NULL, &g_list_settings, NULL, NULL, NULL, NULL, 0);
    CHECK(s.list.valid && s.list.row_count == 0, "no view: no rows, the rest still filled");
    snap_fill_list(NULL, &v, &g_list_settings, NULL, NULL, NULL, NULL, 0);
    CHECK(true, "no snapshot: nothing happens");
}

static void test_fill_list_names_are_private(void)
{
    DbfSnapshot s;
    GameView v;
    const char* mine;
    list_view(&v);
    settings_defaults(&g_list_settings);
    mine = dbf_kind_name(777u); /* the render thread's static text */
    fill_list(&s, &v, NULL, NULL);
    CHECK(strcmp(mine, "Stratagem 777") == 0, "filling the list does not write the render thread's name buffer");
    CHECK(strcmp(s.list.rows[1].name, "Stratagem 150") == 0, "(control) while it did name kind 150");
}

static void test_list_view_fields(void)
{
    DbfSnapshot s;
    CHECK(sizeof s.list.rows / sizeof s.list.rows[0] == 16 && DBF_LIST_ROWS == 16, "the list view has room for the 16 cards");
    CHECK(sizeof s.list.rows[0].name >= 40, "a name field holds the longest vanilla name (38) and a number name");
    CHECK(sizeof s.list.entry_reason >= DBF_REASON_SIZE, "the entry reason field holds a whole job reason");
    CHECK(sizeof s.list.bind_next >= 16, "a binding field holds pad:dpad_right");
}

int main(void)
{
    test_before_init();
    test_fill_before_adm_init();
    test_publish_acquire();
    test_publish_copies();
    test_publish_while_reading();
    test_skipped_publish();
    test_acquire_again_without_release();
    test_two_threads();
    test_queue_basics();
    test_queue_wrap_and_limits();
    test_queue_two_threads();
    test_fill_admission();
    test_fill_admission_reasons();
    test_copy_text();
    test_capturing_flag();
    test_capturing_two_threads();
    test_snapshot_field_sizes();
    test_fill_list_rows();
    test_fill_list_eligibility_and_timers();
    test_fill_list_chosen();
    test_fill_list_settings();
    test_fill_list_texts();
    test_fill_list_entry();
    test_fill_list_limits();
    test_fill_list_names_are_private();
    test_list_view_fields();
    printf("%s\n", test_failures() == 0 ? "PASS test_snapshot" : "FAIL test_snapshot");
    TEST_MAIN_END
}
