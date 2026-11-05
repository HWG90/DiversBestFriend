/* Tests for src/latch.c: the Hold->Press lease of the stratagem menu's binding and the slot hotkeys that use it. They run
 * against the synthetic 25480438 image of tests/synthetic.c with the generated witness table (every feature admitted; a
 * test refuses one by changing a byte of its witness), a memory port that writes into the image (with failures on
 * demand), and native's real wrappers over a port of synthetic.c's fakes: the input handler, open_input, close_input and
 * request_slot. game_read makes each tick's view, as dbf.c will.
 *
 * R46's numbers are written out here (menu_latch.lua:9-75, input.lua:283-364), not taken from the generated header: the
 * patched records (flags - trigger * 65536 with the trigger 0, the other bytes kept), the trigger dwords (controls + 808 +
 * 32 * 485 + 24 and actions + 24, through synthetic.c's accessors, which spell them out), the local menu action byte
 * (actions + 0), the weapon block's slot (avatar + 0x420 + 4) and the stratagem slot 5, and the equipped slots (payload
 * entry slot + 3). synthetic.c lays the binding map out with R46's numbers too, so a value given to the wrong name in
 * the generated header fails here.
 *
 * latch, entry, codes, game, native and memory keep state in statics: every test starts with start(). */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "codes.h"
#include "entry.h"
#include "game.h"
#include "latch.h"
#include "memory.h"
#include "native.h"
#include "synthetic.h"
#include "test.h"

#define GRACE_OVER 30000u
#define RVA_EFFECTS 0x33264b0u     /* R46 input.lua:153 */
#define AT_EFFECTS ((uintptr_t)0x2d000000000ull)
#define RVA_CONTROLS 0x347cf18u    /* input.lua:313 */
#define RVA_UI 0x347ce28u          /* input.lua:294 */
#define UI_OBSTRUCTION (0x429cu + 20u) /* input.lua:295: u32, 0 when nothing covers the HUD */
#define BINDING_MAP 686800u        /* menu_latch.lua:11 */
#define COUNT_AT 0x0u              /* input.lua:241: u32, the directions the game has taken */
#define MATCHED_AT 0x14u           /* input.lua:242, 384 */
#define QUEUED_AT 0x2cu            /* input.lua:242, 384 */
#define ACTION_STRIDE 32u          /* input.lua:188: action a's byte at actions + 32 * a */
#define MENU_DOWN 0u               /* input.lua:289: the menu action's byte at actions + 0 */
#define PANEL_OPEN 0x38769u        /* native.lua:214 */
#define AVATAR_MENU 0xfd8u         /* input.lua:118: bit 9 */
#define MENU_ACTIVE_BIT 512u
#define PAYLOAD_COUNT 0x788u       /* input.lua:358 */
#define PAYLOAD_KINDS 0x188u       /* input.lua:361 */
#define PAYLOAD_STRIDE 0x30u
#define SLOT_ENTRY_BASE 3u         /* input.lua:361: slot s is payload entry s + 3 */
#define WEAPON_SLOT 4u             /* input.lua:332: u32 at the weapon block + 4 */
#define STRATAGEM_SLOT 5u          /* input.lua:334 */
#define FINISH_MS 2000u            /* release.lua:51 */

/* The code of kind 118, the stratagem in equipped slot 1 here: every direction once. */
static const uint8_t CODE[4] = { 1, 2, 3, 4 };

/* SYN_MENU_RECORDS[0] and [2] as R46 patches them (menu_latch.lua:71): flags - trigger * 65536, the trigger 0. */
static const uint8_t HOLD_PATCHED[20] = { 0x43, 0x00, 0x10, 0x00, 0x4b, 0x00, 0x00, 0x00, 0x00, 0x00,
                                          0x00, 0x00, 0x11, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00 };
static const uint8_t LONG_HOLD_PATCHED[20] = { 0x47, 0x00, 0x30, 0x00, 0x02, 0x20, 0x00, 0x00, 0x00, 0x00,
                                               0x00, 0x00, 0x55, 0x00, 0x00, 0x00, 0x66, 0x00, 0x00, 0x00 };

/* --- the ports ------------------------------------------------------------------------------------------------- */

static int g_writes;    /* writes asked for since start() */
static int g_fail_from; /* the first write (1-based) that fails */
static int g_fail_count;

static int write_port(uintptr_t address, const void* data, size_t size)
{
    int index = ++g_writes;
    if (g_fail_count > 0 && index >= g_fail_from && index < g_fail_from + g_fail_count) return -1;
    return syn_write_mapped(address, data, size);
}

static uintptr_t g_unreadable;

static int read_port(uintptr_t address, void* data, size_t size)
{
    if (address == g_unreadable) return -1;
    return syn_read(address, data, size);
}

static const MemPort MEM = { read_port, write_port };

/* After `after` more writes, the next `count` fail (without writing). */
static void fail_writes(int after, int count)
{
    g_fail_from = g_writes + after + 1;
    g_fail_count = count;
}

static uintptr_t fake_scramble_query(uintptr_t effects, uint32_t* out, uint32_t key, uint32_t kind, uintptr_t a5, uintptr_t a6)
{
    return 0;
}

static void fake_log(const char* line) {}

/* latch's own log lines. */
#define MAX_LINES 32
static char g_lines[MAX_LINES][160];
static int g_line_count;

static void latch_log(const char* line)
{
    if (g_line_count < MAX_LINES) snprintf(g_lines[g_line_count], sizeof g_lines[0], "%s", line);
    g_line_count++;
}

/* How many of latch's lines since start() contain `text`. */
static int lines_with(const char* text)
{
    int n = 0;
    for (int i = 0; i < g_line_count && i < MAX_LINES; i++) n += strstr(g_lines[i], text) != NULL;
    return n;
}

static const NativePort NATIVE = { syn_input_handler, syn_open_input, syn_close_input, syn_request_slot, NULL,
                                   fake_scramble_query, fake_log };

/* --- helpers --------------------------------------------------------------------------------------------------- */

static SynScene g_scene;
static GameView g_view;
static char g_why[DBF_REASON_SIZE];

static bool start_with(const SynScene* s)
{
    bool built = syn_build(s);
    g_unreadable = 0;
    mem_init(&MEM);
    adm_init(syn_adm_port(), 0);
    built = built && syn_poke_u64(SYN_GAME_BASE + RVA_EFFECTS, AT_EFFECTS);
    native_init(&NATIVE);
    native_set_base(SYN_GAME_BASE);
    codes_init(NULL);
    game_init(SYN_GAME_BASE, SYN_IMAGE_SIZE);
    latch_init(SYN_GAME_BASE, latch_log);
    g_line_count = 0;
    syn_input_reset();
    syn_input_expect(118, CODE, 4);
    syn_menu_reset();
    g_writes = 0;
    g_fail_count = 0;
    g_why[0] = '\0';
    return built;
}

/* The default scene with eight payload entries: 0 to 3 the shared mission slots (kinds 10 to 13), 4 to 7 the equipped
 * slots 1 to 4 (kinds 118 with CODE, 4, 50 and 63; input.lua:359-361), every card showing one. Menu open and active. */
static bool start(void)
{
    static const uint32_t KINDS[8] = { 10, 11, 12, 13, 118, 4, 50, 63 };
    syn_default(&g_scene);
    g_scene.stratagem_count = 8;
    for (int i = 0; i < 8; i++) {
        g_scene.stratagems[i].kind = KINDS[i];
        g_scene.stratagems[i].code_len = 3;
        memcpy(g_scene.stratagems[i].code, (const uint8_t[3]){ 1, 3, 2 }, 3);
        g_scene.card_entry[i] = i;
    }
    g_scene.stratagems[4].code_len = 4;
    memcpy(g_scene.stratagems[4].code, CODE, sizeof CODE);
    return start_with(&g_scene);
}

static const GameView* view(void)
{
    game_read(&g_view);
    return &g_view;
}

static bool acquire(void)
{
    view();
    return latch_acquire(&g_view.local, g_why, sizeof g_why);
}

static bool refresh(void)
{
    view();
    return latch_refresh(&g_view.local, g_why, sizeof g_why);
}

static bool shortcut(EntryJob* job, int slot, uint32_t interval, bool instant, uint64_t now)
{
    return entry_begin_shortcut(job, view(), slot, interval, instant, now, g_why, sizeof g_why);
}

static void tick(EntryJob* job, uint64_t now, bool trigger_down, bool confirm_down)
{
    entry_step_shortcut(job, view(), now, trigger_down, confirm_down);
}

static uint32_t u32_at(uintptr_t at)
{
    uint32_t v = 0xeeeeeeeeu;
    syn_read(at, &v, sizeof v);
    return v;
}

static uint8_t u8_at(uintptr_t at)
{
    uint8_t v = 0xee;
    syn_read(at, &v, 1);
    return v;
}

static bool record_is(int bucket, int record, const uint8_t want[20])
{
    uint8_t now[20] = { 0 };
    syn_read(syn_binding_record(bucket, record), now, sizeof now);
    if (memcmp(now, want, sizeof now) == 0) return true;
    printf("  bucket %d record %d:", bucket, record);
    for (int i = 0; i < 20; i++) printf(" %02x", now[i]);
    printf("\n");
    return false;
}

static bool dword_is(const char* name, uintptr_t at, uint32_t want)
{
    uint32_t now = u32_at(at);
    if (now == want) return true;
    printf("  %s reads %u, expected %u\n", name, (unsigned)now, (unsigned)want);
    return false;
}

static bool reason_is(const char* want)
{
    if (strcmp(g_why, want) == 0) return true;
    printf("  reason \"%s\", expected \"%s\"\n", g_why, want);
    return false;
}

static bool journal_is(int latch, int entry)
{
    int l = mem_journal_count(MEM_OWNER_LATCH), e = mem_journal_count(MEM_OWNER_ENTRY);
    if (l == latch && e == entry) return true;
    printf("  journal: %d LATCH and %d ENTRY entries (expected %d and %d)\n", l, e, latch, entry);
    return false;
}

/* Every record and trigger dword the latch could change holds the game's original, and the journal holds nothing of
 * the latch's (Review Focus 2). */
static bool originals(void)
{
    bool ok = record_is(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0]);
    ok = record_is(syn_menu_bucket(), 1, SYN_MENU_RECORDS[1]) && ok;
    ok = record_is(syn_menu_bucket(), 2, SYN_MENU_RECORDS[2]) && ok;
    ok = record_is(syn_other_bucket(), 0, SYN_OTHER_RECORD) && ok;
    ok = dword_is("the controls' menu trigger", syn_controls_menu_trigger(), 2) && ok;
    ok = dword_is("the local menu trigger", syn_local_menu_trigger(), 2) && ok;
    ok = journal_is(0, 0) && ok;
    return ok && !latch_held();
}

/* What acquire wrote is still in place (the patched records and both dwords 0), whether or not the latch is held. */
static bool latched_bytes(void)
{
    bool ok = record_is(syn_menu_bucket(), 0, HOLD_PATCHED);
    ok = record_is(syn_menu_bucket(), 2, LONG_HOLD_PATCHED) && ok;
    ok = dword_is("the controls' menu trigger", syn_controls_menu_trigger(), 0) && ok;
    ok = dword_is("the local menu trigger", syn_local_menu_trigger(), 0) && ok;
    return ok;
}

/* After a release for another player (R46 menu_latch.lua:38): every record and the controls' dword original, the old
 * player's actions dword left as the latch left it (0), and nothing of the latch's in the journal. */
static bool originals_but_old_trigger(void)
{
    bool ok = record_is(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0]);
    ok = record_is(syn_menu_bucket(), 1, SYN_MENU_RECORDS[1]) && ok;
    ok = record_is(syn_menu_bucket(), 2, SYN_MENU_RECORDS[2]) && ok;
    ok = record_is(syn_other_bucket(), 0, SYN_OTHER_RECORD) && ok;
    ok = dword_is("the controls' menu trigger", syn_controls_menu_trigger(), 2) && ok;
    ok = dword_is("the old player's menu trigger", syn_local_menu_trigger(), 0) && ok;
    ok = journal_is(0, 0) && ok;
    return ok && !latch_held();
}

/* The latch is on: the Hold and LongHold records patched, the Press record and the other action's Hold untouched, both
 * trigger dwords 0. */
static bool latched(void)
{
    bool ok = record_is(syn_menu_bucket(), 0, HOLD_PATCHED);
    ok = record_is(syn_menu_bucket(), 1, SYN_MENU_RECORDS[1]) && ok;
    ok = record_is(syn_menu_bucket(), 2, LONG_HOLD_PATCHED) && ok;
    ok = record_is(syn_other_bucket(), 0, SYN_OTHER_RECORD) && ok;
    ok = dword_is("the controls' menu trigger", syn_controls_menu_trigger(), 0) && ok;
    ok = dword_is("the local menu trigger", syn_local_menu_trigger(), 0) && ok;
    return ok && latch_held();
}

static void poke_record(int bucket, int record, const uint8_t bytes[20])
{
    syn_poke(syn_binding_record(bucket, record), bytes, 20);
}

/* Menu record `record` with flags `flags` and trigger `trigger`, the rest of SYN_MENU_RECORDS[record]'s bytes. */
static void poke_flags(int record, uint32_t flags, uint32_t trigger)
{
    uint8_t bytes[20];
    memcpy(bytes, SYN_MENU_RECORDS[record], 20);
    memcpy(bytes, &flags, 4);
    memcpy(bytes + 8, &trigger, 4);
    poke_record(syn_menu_bucket(), record, bytes);
}

static void set_menu_open(uint8_t open) { syn_poke_u8(syn_panel() + PANEL_OPEN, open); }

static void set_menu_active(bool active)
{
    syn_poke_u32(syn_local_avatar() + AVATAR_MENU, active ? MENU_ACTIVE_BIT | 0x5u : 0x5u);
}

/* The game closes its menu (after the code, or a closed menu to begin with). */
static void menu_closes(void)
{
    set_menu_open(0);
    set_menu_active(false);
}

static uint32_t weapon_slot(void) { return u32_at(syn_local_weapon() + WEAPON_SLOT); }

static uintptr_t payload(void) { return syn_payload(g_scene.local_entry); }

static bool actions_idle(void)
{
    for (uint32_t a = 1; a <= 4; a++)
        if (u8_at(syn_local_actions() + ACTION_STRIDE * a) != 0) return false;
    return true;
}

static bool calls_are(int open, int request, int close)
{
    if (syn_open_calls() == open && syn_request_calls() == request && syn_close_calls() == close
        && syn_menu_stray_calls() == 0)
        return true;
    printf("  open %d, request %d, close %d, stray %d (expected %d, %d, %d, 0)\n", syn_open_calls(), syn_request_calls(),
           syn_close_calls(), syn_menu_stray_calls(), open, request, close);
    return false;
}

static bool job_is(const EntryJob* job, EntryState state, const char* reason)
{
    if (job->state == state && strcmp(job->reason, reason) == 0) return true;
    printf("  job state %d, reason \"%s\" (expected %d, \"%s\"); sent %u\n", (int)job->state, job->reason, (int)state,
           reason, (unsigned)job->sent);
    return false;
}

static const DbfWitness* witness(const char* name)
{
    for (int i = 0; i < dbf_witness_count; i++)
        if (strcmp(dbf_witnesses[i].name, name) == 0) return &dbf_witnesses[i];
    return NULL;
}

static void spoil_witness(const char* name)
{
    const DbfWitness* w = witness(name);
    if (!w) return;
    syn_poke_u8(SYN_GAME_BASE + w->rva, (uint8_t)(w->bytes[0] ^ 0x55u));
    adm_init(syn_adm_port(), 0);
    adm_tick(GRACE_OVER);
}

/* Hooks run inside a handler call. */
static int g_hook_call;
static void hook_change_code(int call)
{
    static const uint8_t other[4] = { 1, 2, 4, 3 };
    if (call == g_hook_call) syn_set_code(syn_definition(118), syn_code_array(118), 4, other);
}
static void hook_ignore(int call)
{
    if (call == g_hook_call) syn_input_ignore(true);
}
static void hook_new_session(void)
{
    syn_change_peer(0x5151515151515151ull);
}
static void hook_respawn(void)
{
    syn_respawn_local(syn_local_key() ^ 0x100u);
}
static void hook_menu_closes(int call)
{
    if (call == g_hook_call) set_menu_active(false);
}

/* A paced shortcut for slot 1 on a closed menu, its four directions in at 0, 70, 140 and 210 ms. */
static void run_to_done(EntryJob* job)
{
    menu_closes();
    shortcut(job, 1, 70, false, 0);
    for (uint64_t t = 0; t <= 210; t += 70) tick(job, t, false, false);
}

/* --- the lease ------------------------------------------------------------------------------------------------- */

static void test_acquire_and_release(void)
{
    start();
    CHECK(originals(), "the image starts with Hold (2) in both trigger dwords and the three menu records");
    CHECK(acquire() && reason_is("") && latch_held(), "acquire: the latch is taken");
    CHECK(latched(), "  the Hold and LongHold records are Press (flags - trigger * 65536, trigger 0), the Press record "
                     "and the other action's Hold untouched, both trigger dwords 0");
    CHECK(journal_is(4, 0) && g_writes == 4, "  four entries and four writes: two records, two dwords");
    CHECK(u8_at(syn_controls_menu_action()) == 0, "  the controls' menu action byte is read, not written");
    CHECK(!acquire() && reason_is("menu latch already held") && g_writes == 4 && journal_is(4, 0),
          "a second acquire is refused and writes nothing");
    CHECK(latch_release(true) == 0 && originals(), "release: every record and dword is back, the journal empty");
    CHECK(latch_release(true) == 0 && originals() && g_writes == 8, "a second release has nothing to do");

    /* A trigger dword that already reads 0 is not journaled. */
    start();
    syn_poke_u32(syn_local_menu_trigger(), 0);
    CHECK(acquire() && journal_is(3, 0) && dword_is("the local trigger", syn_local_menu_trigger(), 0),
          "a dword already 0 at acquire: left alone, three entries");
    CHECK(latch_release(true) == 0 && dword_is("the local trigger", syn_local_menu_trigger(), 0)
              && record_is(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0]) && journal_is(0, 0),
          "  release: the records back, the dword still 0");

    /* LongHold alone is enough. */
    start();
    poke_record(syn_menu_bucket(), 0, SYN_MENU_RECORDS[1]);
    CHECK(acquire() && record_is(syn_menu_bucket(), 2, LONG_HOLD_PATCHED) && journal_is(3, 0),
          "only a LongHold record: it is latched");
    latch_release(true);
}

static void test_refresh(void)
{
    uint8_t theirs[20];
    start();
    acquire();
    g_writes = 0;
    CHECK(refresh() && g_writes == 0 && journal_is(4, 0) && latched(), "refresh with nothing changed: true, nothing written");
    syn_poke_u32(syn_controls_menu_trigger(), 2);
    CHECK(refresh() && g_writes == 1 && journal_is(4, 0) && latched(),
          "the game rewrote the controls' dword: zeroed again, the journal does not grow");
    syn_poke_u32(syn_local_menu_trigger(), 9);
    CHECK(!refresh() && reason_is("menu trigger changed") && latch_held(),
          "the local dword now LongHold, its original Hold: refused, the latch still held");
    syn_poke_u32(syn_local_menu_trigger(), 2);
    poke_record(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0]);
    CHECK(refresh() && journal_is(4, 0) && latched(), "a record back at its original: patched again, no new entry");
    CHECK(latch_release(true) == 0 && originals(), "  and release gives everything back");

    /* A dword that reads 0 at acquire and later 9 is zeroed then, and release gives back the 9 (R46's refresh). */
    start();
    syn_poke_u32(syn_local_menu_trigger(), 0);
    acquire();
    syn_poke_u32(syn_local_menu_trigger(), 9);
    CHECK(refresh() && journal_is(4, 0) && dword_is("the local trigger", syn_local_menu_trigger(), 0),
          "a dword first seen nonzero at a refresh: zeroed and journaled");
    CHECK(refresh() && journal_is(4, 0), "  the next refresh counts that entry as the latch's own");
    CHECK(latch_release(true) == 0 && dword_is("the local trigger", syn_local_menu_trigger(), 9),
          "  release puts back the value it saw");

    start();
    acquire();
    syn_poke_u32(syn_controls_menu_trigger(), 7);
    CHECK(!refresh() && reason_is("unexpected menu trigger state"), "a trigger dword neither 0, 2 nor 9: refused");

    start();
    acquire();
    memcpy(theirs, SYN_MENU_RECORDS[0], 20);
    theirs[4] = 0x5a; /* the player bound another key meanwhile */
    poke_record(syn_menu_bucket(), 0, theirs);
    CHECK(!refresh() && reason_is("menu binding changed"), "a record someone else changed: refused");
    CHECK(latch_release(true) == 1 && record_is(syn_menu_bucket(), 0, theirs)
              && record_is(syn_menu_bucket(), 2, SYN_MENU_RECORDS[2]) && journal_is(0, 0) && !latch_held(),
          "  release leaves their record, puts the rest back and counts the one");

    start();
    acquire();
    syn_poke_u32(syn_binding_bucket(syn_menu_bucket()) + 4u, 2);
    CHECK(!refresh() && reason_is("menu binding changed"), "the bucket's count below a patched record: refused");
    g_writes = 0;
    CHECK(latch_release(true) == 1 && g_writes == 3
              && record_is(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0]) && record_is(syn_menu_bucket(), 2, LONG_HOLD_PATCHED)
              && dword_is("controls trigger", syn_controls_menu_trigger(), 2)
              && dword_is("local trigger", syn_local_menu_trigger(), 2) && journal_is(0, 0),
          "  release restores only the records still owned and both triggers");
    start();
    acquire();
    syn_poke_u32(syn_binding_bucket(syn_menu_bucket()), 0x50001u);
    CHECK(!refresh() && reason_is("menu binding changed"), "the bucket no longer Display Stratagem List's: refused");
    g_writes = 0;
    CHECK(latch_release(true) == 2 && g_writes == 2
              && record_is(syn_menu_bucket(), 0, HOLD_PATCHED) && record_is(syn_menu_bucket(), 2, LONG_HOLD_PATCHED)
              && dword_is("controls trigger", syn_controls_menu_trigger(), 2)
              && dword_is("local trigger", syn_local_menu_trigger(), 2) && journal_is(0, 0),
          "  release restores only the records still owned and both triggers");
    start();
    acquire();
    syn_poke_u64(syn_controls() + BINDING_MAP, syn_bindings() + 0x100000u);
    CHECK(!refresh() && reason_is("menu binding changed"), "the map moved to another table: refused");
    g_writes = 0;
    CHECK(latch_release(true) == 2 && g_writes == 2
              && record_is(syn_menu_bucket(), 0, HOLD_PATCHED) && record_is(syn_menu_bucket(), 2, LONG_HOLD_PATCHED)
              && dword_is("controls trigger", syn_controls_menu_trigger(), 2)
              && dword_is("local trigger", syn_local_menu_trigger(), 2) && journal_is(0, 0),
          "  release restores only the records still owned and both triggers");
    start();
    acquire();
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls() + 0x10000u);
    CHECK(!refresh() && reason_is("controls changed"), "another controls object: refused");
    start();
    acquire();
    spoil_witness("wheel_action_sound");
    {
        char want[96];
        snprintf(want, sizeof want, "%s: witness wheel_action_sound differs", adm_feature_name(FEAT_LATCH));
        CHECK(!refresh() && reason_is(want), "LATCH refused: refused with admission's reason");
    }
    CHECK(latch_release(true) == 0 && originals(), "  release still restores");

    start();
    acquire();
    mem_restore_all();
    g_writes = 0;
    CHECK(!refresh() && reason_is("menu latch restored elsewhere") && !latch_held() && g_writes == 0 && originals(),
          "the journal restored elsewhere: refused, no longer held, nothing latched again");
    CHECK(!refresh() && reason_is("menu latch not held"), "not held: refused");
    CHECK(!latch_refresh(NULL, NULL, 0), "a NULL context and reason: refused");

    /* A restore_all elsewhere that could not write everything back still ends the latch: the refresh must not patch
     * again what was put back, as new entries. */
    start();
    acquire();
    fail_writes(0, 1); /* newest first: the local dword's write fails, the rest are put back */
    mem_restore_all();
    g_writes = 0;
    CHECK(!refresh() && reason_is("menu latch restored elsewhere") && !latch_held() && g_writes == 0 && journal_is(1, 0)
              && record_is(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0]) && record_is(syn_menu_bucket(), 2, SYN_MENU_RECORDS[2]),
          "restore_all elsewhere left one entry: refused, nothing patched again, the one entry left for release");
    CHECK(latch_release(true) == 0 && originals(), "  release puts the last one back");

    /* A re-assert whose write fails says so. */
    start();
    acquire();
    poke_record(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0]);
    view();
    fail_writes(0, 1);
    CHECK(!latch_refresh(&g_view.local, g_why, sizeof g_why) && reason_is("menu binding could not be latched"),
          "a record's re-assert write fails: \"menu binding could not be latched\"");
    CHECK(latch_release(true) == 0 && originals(), "  release puts everything back");
}

/* latch_release is mem_restore(MEM_OWNER_LATCH) with memory's rules (Task 10's rulings). */
static void test_release(void)
{
    uint8_t theirs[20];
    start();
    acquire();
    syn_poke_u32(syn_local_menu_trigger(), 2); /* the game writes its original back, as it does every frame */
    g_writes = 0;
    CHECK(latch_release(true) == 0 && g_writes == 3 && originals(),
          "release while the game rewrote a dword's original: counted as restored, nothing written there");

    start();
    acquire();
    memcpy(theirs, SYN_MENU_RECORDS[2], 20);
    theirs[12] = 0x99;
    poke_record(syn_menu_bucket(), 2, theirs);
    CHECK(latch_release(true) == 1 && record_is(syn_menu_bucket(), 2, theirs)
              && record_is(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0])
              && dword_is("the controls' trigger", syn_controls_menu_trigger(), 2)
              && dword_is("the local trigger", syn_local_menu_trigger(), 2) && journal_is(0, 0),
          "release with a record the game changed meanwhile: that one left alone and counted, the rest back");

    start();
    acquire();
    fail_writes(0, 1); /* newest first: the local dword's write fails */
    CHECK(latch_release(true) == 1 && !latch_held() && journal_is(1, 0)
              && dword_is("the local trigger", syn_local_menu_trigger(), 0),
          "a release write that fails: counted, its entry kept, the latch no longer held");
    CHECK(latch_release(true) == 0 && originals(), "  the next release retries it");

    start();
    acquire();
    fail_writes(0, 1);
    latch_release(true);
    CHECK(acquire() && journal_is(4, 0) && latched(), "acquire retries a leftover entry first, then latches");
    latch_release(true);
    start();
    acquire();
    fail_writes(0, 1);
    latch_release(true);
    fail_writes(0, 1); /* and acquire's retry of it fails too */
    CHECK(!acquire() && reason_is("the last menu latch is not restored yet") && journal_is(1, 0) && !latch_held(),
          "acquire while the leftover cannot be written back: refused");
    CHECK(latch_release(true) == 0 && originals(), "  a later release puts it back");

    /* R46's owner checks (menu_latch.lua:26-44). Another player: the actions dword is dropped, the rest restored. */
    start();
    acquire();
    g_writes = 0;
    CHECK(latch_release(false) == 1 && g_writes == 3 && originals_but_old_trigger()
              && lines_with("trigger was left alone") == 1,
          "release for another player: the records and the controls' dword back, the old actions dword left (one line)");

    /* Another controls object, or none: nothing is written. */
    /* (b) Another controls object (a different, plausible pointer): every entry dropped, nothing written. */
    start();
    acquire();
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls() + 0x10000u);
    g_writes = 0;
    CHECK(latch_release(true) == 4 && g_writes == 0 && journal_is(0, 0) && !latch_held()
              && record_is(syn_menu_bucket(), 0, HOLD_PATCHED) && dword_is("the old trigger", syn_controls_menu_trigger(), 0)
              && lines_with("controls object changed") == 1,
          "release after the controls object changed: every entry dropped, nothing written, one line");
    CHECK(latch_release(true) == 0 && lines_with("controls object changed") == 1, "  a second release: nothing, no line");

    /* (a) The pointer is 0, or cannot be read: everything kept for a retry, then restored once it reads the latched
     * object again. */
    for (int which = 0; which < 2; which++) {
        const char* text = which == 0 ? "release with the controls pointer 0" : "release with the controls pointer unreadable";
        char line[160];
        start();
        acquire();
        if (which == 0) syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, 0);
        else syn_unmap(SYN_GAME_BASE + RVA_CONTROLS);
        g_writes = 0;
        snprintf(line, sizeof line, "%s: every entry kept and counted, nothing written, one line", text);
        CHECK(latch_release(true) == 4 && g_writes == 0 && journal_is(4, 0) && !latch_held() && latched_bytes()
                  && lines_with("controls pointer cannot be read") == 1 && lines_with("controls object changed") == 0,
              line);
        CHECK(latch_release(true) == 4 && g_writes == 0 && journal_is(4, 0)
                  && lines_with("controls pointer cannot be read") == 1,
              "  the next retry while it still cannot be read: kept, no second line");
        syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls());
        CHECK(latch_release(true) == 0 && originals(), "  the pointer back: the retry restores every record and dword");
    }
    /* A second unreadable spell, after one that ended with a write still failing, gets its own line. */
    start();
    acquire();
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, 0);
    latch_release(true);
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls());
    fail_writes(0, 1);
    CHECK(latch_release(true) == 1 && journal_is(1, 0), "the pointer back but one write fails: that entry kept");
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, 0);
    CHECK(latch_release(true) == 1 && journal_is(1, 0) && lines_with("controls pointer cannot be read") == 2,
          "  unreadable again: kept, and a line for this spell too");
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls());
    CHECK(latch_release(true) == 0 && originals(), "  readable: restored");

    start();
    acquire();
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, 0);
    latch_release(true);
    view();
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, 0);
    CHECK(!latch_acquire(&g_view.local, g_why, sizeof g_why) && reason_is("the last menu latch is not restored yet")
              && journal_is(4, 0),
          "acquire while the kept entries still cannot be checked: refused, nothing new taken");
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls());
    CHECK(latch_release(true) == 0 && originals(), "  and the pointer back: restored");

    start();
    acquire();
    fail_writes(2, 1); /* both dwords restore, then record 2 fails */
    CHECK(latch_release(true) == 1 && journal_is(1, 0), "one binding record stays journaled after a failed restore");
    syn_poke_u32(syn_binding_bucket(syn_menu_bucket()) + 4u, 2);
    g_writes = 0;
    CHECK(latch_release(true) == 1 && g_writes == 0 && journal_is(0, 0)
              && record_is(syn_menu_bucket(), 2, LONG_HOLD_PATCHED),
          "retry after list shrink forgets the detached record without writing");

    for (int field = 0; field < 4; field++) {
        start();
        acquire();
        uintptr_t map = syn_controls() + BINDING_MAP;
        uintptr_t bucket = syn_binding_bucket(syn_menu_bucket());
        uintptr_t fields[] = { map, map + 8u, bucket, bucket + 4u };
        g_unreadable = fields[field];
        g_writes = 0;
        CHECK(latch_release(true) == 4 && g_writes == 0 && journal_is(4, 0) && latched_bytes(),
              "unreadable binding metadata keeps the lease bytes and journal for retry");
        g_unreadable = 0;
        CHECK(latch_release(true) == 0 && originals(), "retry with readable metadata restores the owned entries");
    }

    /* The checks are made again on a retry. */
    start();
    acquire();
    fail_writes(0, 1);
    latch_release(true); /* the local dword is kept */
    g_writes = 0;
    CHECK(latch_release(false) == 1 && g_writes == 0 && originals_but_old_trigger(),
          "a retry for another player: the kept actions dword dropped without writing");
    start();
    acquire();
    fail_writes(0, 1);
    latch_release(true);
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls() + 0x10000u);
    g_writes = 0;
    CHECK(latch_release(true) == 1 && g_writes == 0 && journal_is(0, 0) && lines_with("controls object changed") == 1,
          "a retry after the controls object changed: dropped without writing");
    start();
    acquire();
    fail_writes(0, 1);
    latch_release(true);
    syn_respawn_local(syn_local_key() ^ 0x100u);
    CHECK(acquire() && journal_is(3, 0) && lines_with("trigger was left alone") == 1
              && dword_is("the local trigger", syn_local_menu_trigger(), 0),
          "acquire for a respawned player: the old player's kept dword dropped, then the latch taken (that dword is 0)");
    CHECK(latch_release(true) == 0 && dword_is("the local trigger", syn_local_menu_trigger(), 0)
              && record_is(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0]) && journal_is(0, 0),
          "  and released");
}

/* Task 12 fix round, I1: the tick's retry asks latch_owner_is, which compares manager, key and component as R46's
 * avatar_valid does (input.lua:376). A respawn into another avatar keeps the manager and the key but not the component
 * (nor the actions block): the retry must leave the old block's actions dword alone. */
static void test_owner(void)
{
    GameLocal moved, other;
    start();
    CHECK(!latch_owner_is(&view()->local), "no latch: nobody is its owner");
    acquire();
    CHECK(latch_owner_is(&g_view.local), "the player the latch was taken for is its owner");
    CHECK(!latch_owner_is(NULL), "no player is not");
    moved = g_view.local;
    moved.component += 0x1000u;
    moved.avatar += 0x1000u;
    moved.actions += 0x400u;
    CHECK(!latch_owner_is(&moved), "the same manager and key with another component is not (a respawn)");
    other = g_view.local;
    other.key ^= 0x100u;
    CHECK(!latch_owner_is(&other), "another key is not");
    other = g_view.local;
    other.manager += 8u;
    CHECK(!latch_owner_is(&other), "another manager is not");

    /* Leftovers kept while the controls pointer cannot be read, then retried as the tick does for the moved player. */
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, 0);
    latch_release(true);
    CHECK(journal_is(4, 0) && latch_owner_is(&g_view.local), "the kept entries still belong to the latch's player");
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls());
    g_writes = 0;
    CHECK(latch_release(latch_owner_is(&moved)) == 1 && journal_is(0, 0)
              && dword_is("the old block's trigger", syn_local_menu_trigger(), 0)
              && dword_is("the controls trigger", syn_controls_menu_trigger(), 2)
              && record_is(syn_menu_bucket(), 0, SYN_MENU_RECORDS[0]) && record_is(syn_menu_bucket(), 2, SYN_MENU_RECORDS[2])
              && g_writes == 3 && lines_with("trigger was left alone") == 1,
          "the retry for the respawned player: records and the controls dword back, the old actions dword not written");
    CHECK(!latch_owner_is(&g_view.local), "with every entry gone the latch has no owner");
}

static bool refused_acquire(const char* reason)
{
    bool taken;
    view();
    g_writes = 0;
    taken = latch_acquire(&g_view.local, g_why, sizeof g_why);
    if (!taken && reason_is(reason) && g_writes == 0 && journal_is(0, 0) && !latch_held()) return true;
    printf("  acquire %d, %d writes\n", taken, g_writes);
    return false;
}

static void test_acquire_refusals(void)
{
    char want[96];
    start();
    poke_record(syn_menu_bucket(), 0, SYN_MENU_RECORDS[1]);
    poke_record(syn_menu_bucket(), 2, SYN_MENU_RECORDS[1]);
    CHECK(refused_acquire("no Hold mapping"), "no Hold or LongHold record in the menu bucket (another action's Hold does "
                                              "not count): refused, nothing written");
    start();
    poke_flags(0, 0x00120033u, 2);
    CHECK(refused_acquire("unexpected Hold binding format"), "a Hold record whose format nibble is 3: refused");
    start();
    poke_flags(2, 0x00320047u, 9);
    CHECK(refused_acquire("unexpected Hold binding format"),
          "a LongHold record whose flags say Hold: refused, the Hold record before it not written either");
    start();
    syn_poke_u32(syn_controls() + BINDING_MAP + 8u, 255);
    CHECK(refused_acquire("menu binding map unrecognised"), "a map capacity of 255: refused");
    start();
    syn_poke_u32(syn_binding_bucket(syn_menu_bucket()), 0x50001u);
    CHECK(refused_acquire("menu binding missing"), "no bucket keyed 0x50000: refused");
    start();
    syn_poke_u32(syn_binding_bucket(syn_menu_bucket()) + 4u, 17);
    CHECK(refused_acquire("invalid menu bindings"), "a bucket count of 17: refused");
    start();
    syn_poke_u64(syn_controls() + BINDING_MAP, 0);
    CHECK(refused_acquire("menu bindings unreadable"), "no table pointer: refused");
    start();
    syn_unmap(syn_binding_bucket(2));
    CHECK(refused_acquire("menu bindings unreadable"), "a bucket before the menu's unreadable: refused");
    start();
    syn_poke_u32(syn_controls_menu_trigger(), 5);
    CHECK(refused_acquire("unexpected menu trigger state"), "the controls' trigger dword 5: refused");
    start();
    syn_poke_u32(syn_local_menu_trigger(), 1);
    CHECK(refused_acquire("unexpected menu trigger state"), "the local trigger dword 1: refused");
    start();
    syn_poke_u8(syn_controls_menu_action(), 2);
    CHECK(refused_acquire("invalid menu action"), "the controls' menu action byte 2: refused");
    start();
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, 0);
    CHECK(refused_acquire("controls unreadable"), "no controls object (GameLocal.controls 0): refused");
    start();
    syn_poke_u32(syn_ui() + UI_OBSTRUCTION, 1);
    CHECK(refused_acquire("UI obstructed"), "the UI obstructed: refused");
    start();
    spoil_witness("wheel_action_sound");
    snprintf(want, sizeof want, "%s: witness wheel_action_sound differs", adm_feature_name(FEAT_LATCH));
    CHECK(refused_acquire(want), "LATCH refused: refused with admission's reason");
    start();
    CHECK(!latch_acquire(NULL, g_why, sizeof g_why) && reason_is("local player unavailable") && g_writes == 0,
          "a NULL context: refused");
    start();
    latch_init(0, latch_log);
    CHECK(refused_acquire("controls unreadable"), "no game.dll base to read the controls pointer: refused");
    start();
    view();
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls() + 0x10000u);
    CHECK(!latch_acquire(&g_view.local, g_why, sizeof g_why) && reason_is("controls changed") && g_writes == 0
              && journal_is(0, 0),
          "the controls pointer no longer the context's: refused");

    /* A swap that fails puts back what was swapped before it. */
    start();
    view();
    fail_writes(1, 1);
    CHECK(!latch_acquire(&g_view.local, g_why, sizeof g_why) && reason_is("menu binding could not be latched")
              && originals(),
          "the second record's write fails: refused, the first record put back");
    start();
    view();
    fail_writes(3, 1);
    CHECK(!latch_acquire(&g_view.local, g_why, sizeof g_why) && reason_is("menu trigger could not be latched")
              && originals(),
          "the second dword's write fails: refused, both records and the first dword put back");
}

/* --- slot hotkeys ---------------------------------------------------------------------------------------------- */

static void test_shortcut_closed_menu(void)
{
    EntryJob job;
    start();
    menu_closes();
    CHECK(shortcut(&job, 1, 70, false, 1000) && reason_is("") && job_is(&job, ENTRY_RUNNING, "") && job.latched
              && job.kind == 118 && shortcut_active(),
          "slot 1 on a closed menu: the job runs, latched, for payload entry 4's kind 118");
    CHECK(calls_are(1, 1, 0) && syn_requested_slot() == STRATAGEM_SLOT && weapon_slot() == STRATAGEM_SLOT,
          "  the menu opened once, slot 5 requested once (the weapon had slot 1)");
    CHECK(latched() && syn_input_calls() == 0, "  the latch on, nothing entered yet");
    CHECK(u8_at(syn_panel() + PANEL_OPEN) == 1, "  the menu is open now");
    for (uint64_t t = 1000; t <= 1210; t += 70) tick(&job, t, false, false);
    CHECK(job_is(&job, ENTRY_DONE, "") && job.sent == 4 && u32_at(syn_local_component() + MATCHED_AT) == 118,
          "four ticks 70 ms apart: the code is in, the game matched kind 118");
    CHECK(shortcut_active() && latched() && journal_is(4, 0) && actions_idle(),
          "  done, but the latch holds while the menu is still open");
    syn_poke_u32(syn_local_menu_trigger(), 2);
    tick(&job, 1500, false, false);
    CHECK(shortcut_active() && latched() && journal_is(4, 0), "  a tick later the latch is refreshed (the dword zeroed)");
    menu_closes();
    tick(&job, 1600, false, false);
    CHECK(!shortcut_active() && job_is(&job, ENTRY_DONE, "") && originals() && calls_are(1, 1, 0),
          "the game closes the menu: the latch restored (every record and dword original), done, no close called");
    CHECK(weapon_slot() == STRATAGEM_SLOT, "  the slot request is not undone");
    tick(&job, 1700, false, false);
    CHECK(job_is(&job, ENTRY_DONE, "") && originals(), "  later ticks do nothing");

    /* The weapon already has the stratagem slot: no request. */
    start();
    menu_closes();
    syn_poke_u32(syn_local_weapon() + WEAPON_SLOT, STRATAGEM_SLOT);
    CHECK(shortcut(&job, 1, 70, false, 0) && calls_are(1, 0, 0), "the weapon already on slot 5: no request");
    entry_cancel_shortcut(&job, view(), "test over");
}

static void test_shortcut_open_menu(void)
{
    EntryJob job;
    start();
    CHECK(shortcut(&job, 1, 0, false, 0) && calls_are(0, 1, 0) && latched(),
          "slot 1 with the menu open: not opened again, the latch on");
    for (int i = 0; i < 4; i++) tick(&job, 0, false, false);
    CHECK(job_is(&job, ENTRY_DONE, "") && shortcut_active(), "interval 0: one direction a tick, done");
    menu_closes();
    tick(&job, 10, false, false);
    CHECK(!shortcut_active() && originals() && calls_are(0, 1, 0), "the menu closes: the latch restored");

    /* Confirm with a menu the player opened: cancelled, but DBF does not close the player's menu. */
    start();
    shortcut(&job, 1, 70, false, 0);
    tick(&job, 0, false, false);
    tick(&job, 70, false, true);
    CHECK(job_is(&job, ENTRY_FAILED, "Confirm pressed") && !shortcut_active() && originals() && calls_are(0, 1, 0),
          "Confirm on the player's own menu: cancelled, the latch restored, no close");
}

static void test_shortcut_slots(void)
{
    static const uint32_t WANT[5] = { 0, 118, 4, 50, 63 };
    for (int slot = 1; slot <= 4; slot++) {
        EntryJob job;
        char text[96];
        start();
        snprintf(text, sizeof text, "slot %d is payload entry %d (kind %u)", slot, slot + (int)SLOT_ENTRY_BASE,
                 (unsigned)WANT[slot]);
        CHECK(shortcut(&job, slot, 70, false, 0) && job.kind == WANT[slot], text);
        entry_cancel_shortcut(&job, view(), NULL);
        CHECK(job_is(&job, ENTRY_FAILED, "cancelled") && originals(), "  cancelled with no reason: \"cancelled\", restored");
    }
}

static void test_shortcut_instant(void)
{
    EntryJob job;
    start();
    menu_closes();
    CHECK(shortcut(&job, 1, 70, true, 0) && job.instant, "an Instant shortcut runs");
    tick(&job, 0, true, false);
    CHECK(job.sent == 3 && job_is(&job, ENTRY_RUNNING, ""), "  three directions at once, the last held while the key is down");
    tick(&job, 10, false, false);
    tick(&job, 110, false, false);
    CHECK(job_is(&job, ENTRY_DONE, "") && shortcut_active() && latched(), "  the last 100 ms after the key went up: done");
    menu_closes();
    tick(&job, 120, false, false);
    CHECK(!shortcut_active() && originals() && calls_are(1, 1, 0), "  the menu closes: restored");
}

/* Review Focus 2: a shortcut that fails after DBF opened the menu closes it, and every record and dword reads its
 * original afterwards. */
static void test_shortcut_fails_after_open(void)
{
    EntryJob job;
    uint8_t theirs[20];

    start();
    syn_input_on_call(hook_change_code);
    g_hook_call = 1;
    run_to_done(&job);
    CHECK(job_is(&job, ENTRY_FAILED, "code changed") && job.sent == 2 && !shortcut_active(),
          "the code changes after direction 2: failed before direction 3");
    CHECK(calls_are(1, 1, 1) && u8_at(syn_panel() + PANEL_OPEN) == 0, "  the menu DBF opened is closed");
    CHECK(originals() && actions_idle(), "  every record and dword original, the action bytes 0, the journal empty");

    start();
    syn_input_on_call(hook_ignore);
    g_hook_call = 0;
    run_to_done(&job);
    CHECK(job_is(&job, ENTRY_FAILED, "the game did not take the direction") && calls_are(1, 1, 1) && originals(),
          "the handler stops counting after direction 1: failed, closed, the originals back");

    start();
    menu_closes();
    syn_open_answers(1, false);
    CHECK(!shortcut(&job, 1, 70, false, 0) && reason_is("menu closed") && job_is(&job, ENTRY_FAILED, "menu closed")
              && calls_are(1, 0, 1) && originals() && !shortcut_active(),
          "open answers yes but the menu stays closed: refused, closed, the originals back");

    start();
    menu_closes();
    syn_open_answers(0, false);
    CHECK(!shortcut(&job, 1, 70, false, 0) && reason_is("the game did not open the menu") && calls_are(1, 0, 0)
              && originals(),
          "open answers no: refused, nothing to close, the originals back");

    start();
    menu_closes();
    syn_open_on_call(hook_new_session);
    CHECK(!shortcut(&job, 1, 70, false, 0) && reason_is("local player unavailable") && calls_are(1, 0, 0)
              && originals_but_old_trigger() && lines_with("left open") == 1,
          "a new session inside the open call: refused on the view read again, not closed (logged), the records back, "
          "the old player's dword left alone");

    start();
    menu_closes();
    syn_open_on_call(hook_respawn);
    CHECK(!shortcut(&job, 1, 70, false, 0) && reason_is("player changed") && calls_are(1, 0, 0)
              && originals_but_old_trigger() && lines_with("left open") == 1 && lines_with("trigger was left alone") == 1,
          "the player respawns with another key inside the open call: \"player changed\", not closed, the old "
          "player's dword left alone");

    start();
    menu_closes();
    syn_request_ignored(true);
    CHECK(!shortcut(&job, 1, 70, false, 0) && reason_is("the game did not select the stratagem slot")
              && calls_are(1, 1, 1) && originals(),
          "the slot request does not take: refused, closed, the originals back");

    start();
    menu_closes();
    syn_poke_u32(syn_local_weapon(), syn_local_key() ^ 1u);
    CHECK(!shortcut(&job, 1, 70, false, 0) && reason_is("weapon owner mismatch") && calls_are(1, 0, 1) && originals(),
          "a weapon block of another player: refused, closed, the originals back");
    for (uint32_t bad = 0; bad <= 8; bad += 8) {
        start();
        menu_closes();
        syn_poke_u32(syn_local_weapon() + WEAPON_SLOT, bad);
        CHECK(!shortcut(&job, 1, 70, false, 0) && reason_is("invalid weapon slot") && calls_are(1, 0, 1) && originals(),
              bad == 0 ? "a requested slot of 0: refused, closed" : "a requested slot of 8: refused, closed");
    }

    start();
    menu_closes();
    poke_record(syn_menu_bucket(), 0, SYN_MENU_RECORDS[1]);
    poke_record(syn_menu_bucket(), 2, SYN_MENU_RECORDS[1]);
    g_writes = 0;
    CHECK(!shortcut(&job, 1, 70, false, 0) && reason_is("no Hold mapping") && calls_are(0, 0, 0) && g_writes == 0
              && journal_is(0, 0),
          "no Hold binding: refused before the menu is opened, nothing written");

    /* Failures while the job runs. */
    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    tick(&job, 0, false, false);
    syn_poke_u32(syn_ui() + UI_OBSTRUCTION, 1);
    tick(&job, 70, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "UI obstructed") && job.sent == 1 && calls_are(1, 1, 1) && originals(),
          "the UI covered mid-code: failed, closed, the originals back");

    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    syn_poke_u8(syn_local_actions() + MENU_DOWN, 1);
    tick(&job, 0, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "menu key pressed") && job.sent == 0 && calls_are(1, 1, 1) && originals(),
          "the menu key pressed mid-code: failed, closed, the originals back");

    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    tick(&job, 0, false, false);
    memcpy(theirs, SYN_MENU_RECORDS[0], 20);
    theirs[4] = 0x5a;
    poke_record(syn_menu_bucket(), 0, theirs);
    tick(&job, 70, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "menu binding changed") && calls_are(1, 1, 1) && record_is(syn_menu_bucket(), 0, theirs)
              && record_is(syn_menu_bucket(), 2, SYN_MENU_RECORDS[2])
              && dword_is("the local trigger", syn_local_menu_trigger(), 2) && journal_is(0, 0) && !latch_held(),
          "the player rebinds the menu mid-code: failed, closed, their record kept and the rest original");

    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    tick(&job, 0, false, false);
    view();
    syn_change_peer(0x5151515151515151ull);
    tick(&job, 70, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "local player unavailable") && calls_are(1, 1, 0) && originals_but_old_trigger(),
          "a new session mid-code: failed, the records back, the old player's dword left alone (R46), no close");

    for (int which = 0; which < 3; which++) {
        GameView other;
        start();
        menu_closes();
        shortcut(&job, 1, 70, false, 0);
        tick(&job, 0, false, false);
        other = *view();
        if (which == 0) other.local.key ^= 1u;
        if (which == 1) other.local.manager += 0x1000u;
        if (which == 2) other.local.component += 0x1238u;
        entry_step_shortcut(&job, &other, 70, false, false);
        CHECK(job_is(&job, ENTRY_FAILED, "player changed") && calls_are(1, 1, 0) && originals_but_old_trigger(),
              which == 0   ? "another key mid-code (the menu still active): failed, the records back, the old player's "
                             "dword left alone, the old menu not closed"
              : which == 1 ? "another avatar manager mid-code: the same"
                           : "another input component mid-code: the same");
    }
    start();
    run_to_done(&job);
    {
        GameView other = *view();
        other.local.key ^= 1u;
        entry_step_shortcut(&job, &other, 300, false, false);
        CHECK(job_is(&job, ENTRY_FAILED, "player changed") && calls_are(1, 1, 0) && originals_but_old_trigger(),
              "another key after the code: cancelled, the records back, the old player's dword left alone, not closed");
    }
    start();
    run_to_done(&job);
    syn_change_peer(0x5151515151515151ull);
    tick(&job, 300, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "local player unavailable") && calls_are(1, 1, 0) && originals_but_old_trigger(),
          "a new session after the code: cancelled, the records back, the old player's dword left alone, not closed");

    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    tick(&job, 0, false, false);
    syn_poke_u64(SYN_GAME_BASE + RVA_CONTROLS, syn_controls() + 0x10000u); /* a new controls object */
    g_writes = 0;
    tick(&job, 70, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "controls changed") && g_writes == 0 && journal_is(0, 0) && !latch_held()
              && calls_are(1, 1, 1) && lines_with("controls object changed") == 1,
          "the controls object changes mid-code: failed, nothing written into the old object, the journal empty, one "
          "log line, the menu DBF opened closed");
    CHECK(record_is(syn_menu_bucket(), 0, HOLD_PATCHED) && record_is(syn_menu_bucket(), 2, LONG_HOLD_PATCHED)
              && dword_is("the old controls' trigger", syn_controls_menu_trigger(), 0)
              && dword_is("the local trigger", syn_local_menu_trigger(), 0),
          "  the old object keeps what the latch wrote there (R46 restores nothing then)");

    /* The game closes the menu inside a handler call of an Instant step: the failure is "menu inactive", and DBF does
     * not close a menu that is already closed (the tick's view still said it was open). */
    start();
    menu_closes();
    syn_input_on_call(hook_menu_closes);
    g_hook_call = 0;
    shortcut(&job, 1, 70, true, 0);
    tick(&job, 0, true, false);
    CHECK(job_is(&job, ENTRY_FAILED, "menu inactive") && job.sent == 1 && calls_are(1, 1, 0) && originals(),
          "Instant, the menu closed inside direction 1's call: failed, not closed, the originals back");

    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    tick(&job, 0, false, false);
    menu_closes(); /* the player closed the menu */
    tick(&job, 70, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "menu closed") && calls_are(1, 1, 0) && originals(),
          "the menu closed mid-code: failed, restored, nothing left to close");

    /* Failures after the job is done, with the menu still open. */
    start();
    run_to_done(&job);
    tick(&job, 210 + FINISH_MS, false, false);
    CHECK(job_is(&job, ENTRY_DONE, "") && shortcut_active(), "done: waiting up to 2000 ms for the menu to close");
    tick(&job, 211 + FINISH_MS, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "the menu did not close") && calls_are(1, 1, 1) && originals() && !shortcut_active(),
          "  2001 ms: cancelled, closed, the originals back");

    start();
    run_to_done(&job);
    menu_closes();
    tick(&job, 211 + FINISH_MS, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "the menu did not close") && calls_are(1, 1, 0) && originals(),
          "  the menu closing only after the deadline: still cancelled (R46 checks the deadline first), nothing to close");

    start();
    run_to_done(&job);
    syn_poke_u32(syn_local_component() + MATCHED_AT, 0);
    syn_poke_u32(syn_local_component() + QUEUED_AT, 118);
    tick(&job, 300, false, false);
    CHECK(job_is(&job, ENTRY_DONE, "") && shortcut_active(), "done: the kind moved to the queue is still the job's");
    syn_poke_u32(syn_local_component() + QUEUED_AT, 0);
    tick(&job, 310, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "the game dropped the stratagem") && calls_are(1, 1, 1) && originals(),
          "  neither matched nor queued any more: cancelled, closed, the originals back");

    start();
    run_to_done(&job);
    syn_poke_u32(syn_ui() + UI_OBSTRUCTION, 1);
    tick(&job, 300, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "UI obstructed") && calls_are(1, 1, 1) && originals(),
          "done, then the UI covered: cancelled, closed, the originals back");
}

static void test_shortcut_confirm(void)
{
    EntryJob job;
    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    tick(&job, 0, false, false);
    tick(&job, 70, false, true);
    CHECK(job_is(&job, ENTRY_FAILED, "Confirm pressed") && job.sent == 1 && !shortcut_active(),
          "Confirm during the code: cancelled after one direction");
    CHECK(calls_are(1, 1, 1) && originals() && actions_idle(), "  the menu DBF opened closed, the originals back");

    start();
    run_to_done(&job);
    tick(&job, 300, false, true);
    CHECK(job_is(&job, ENTRY_FAILED, "Confirm pressed") && calls_are(1, 1, 1) && originals(),
          "Confirm after the code, before the menu closed: cancelled (R46), closed, the originals back");

    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    entry_cancel_shortcut(&job, view(), "mission ended");
    CHECK(job_is(&job, ENTRY_FAILED, "mission ended") && calls_are(1, 1, 1) && originals() && !shortcut_active(),
          "entry_cancel_shortcut: cancelled with the reason, closed, the originals back");
    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    entry_cancel_shortcut(&job, NULL, "HUD gone");
    CHECK(job_is(&job, ENTRY_FAILED, "HUD gone") && calls_are(1, 1, 0) && originals_but_old_trigger(),
          "  with no view: no close, the records back, the actions dword left alone (no player to vouch for it)");
    start();
    run_to_done(&job);
    entry_cancel_shortcut(&job, view(), "mission ended");
    CHECK(job_is(&job, ENTRY_FAILED, "mission ended") && calls_are(1, 1, 1) && originals(),
          "  a done job waiting for the menu: failed with the reason, closed, restored");
    entry_cancel_shortcut(&job, view(), "again");
    CHECK(job_is(&job, ENTRY_FAILED, "mission ended"), "  no shortcut active: left alone");
    start();
    run_to_done(&job);
    entry_cancel_shortcut(&job, view(), NULL);
    CHECK(job_is(&job, ENTRY_FAILED, "cancelled") && originals(), "  a done job with no reason: \"cancelled\"");

    /* A job the caller cancelled with entry_cancel ends the shortcut on the next tick. */
    start();
    menu_closes();
    shortcut(&job, 1, 70, false, 0);
    entry_cancel(&job, "by the caller");
    tick(&job, 0, false, false);
    CHECK(job_is(&job, ENTRY_FAILED, "by the caller") && !shortcut_active() && calls_are(1, 1, 1) && originals(),
          "a job cancelled by the caller: the next tick ends the shortcut, closes and restores");

    start();
    memset(&job, 0, sizeof job);
    tick(&job, 0, false, true);
    CHECK(job.state == ENTRY_IDLE && calls_are(0, 0, 0) && g_writes == 0, "no shortcut active: a tick does nothing");
}

static bool refused_shortcut(int slot, const char* reason)
{
    EntryJob job;
    bool started;
    memset(&job, 0xa5, sizeof job);
    job.state = ENTRY_IDLE;
    g_writes = 0;
    started = shortcut(&job, slot, 70, false, 0);
    if (!started && reason_is(reason) && job_is(&job, ENTRY_FAILED, reason) && g_writes == 0 && calls_are(0, 0, 0)
        && syn_input_calls() == 0 && journal_is(0, 0) && !shortcut_active())
        return true;
    printf("  shortcut(%d): %d, %d writes\n", slot, started, g_writes);
    return false;
}

static void test_shortcut_refusals(void)
{
    EntryJob job, copy;
    char want[96];
    start();
    syn_poke_u32(payload() + PAYLOAD_COUNT, 7);
    CHECK(refused_shortcut(1, "equipped stratagems unavailable"), "seven payload entries: refused, nothing written or called");
    start();
    syn_poke_u32(payload() + PAYLOAD_COUNT, 33);
    CHECK(refused_shortcut(1, "equipped stratagems unavailable"), "33 payload entries: refused");
    start();
    CHECK(refused_shortcut(0, "invalid equipped slot") && refused_shortcut(5, "invalid equipped slot"),
          "slots 0 and 5: refused");
    start();
    syn_poke_u32(payload() + PAYLOAD_KINDS + PAYLOAD_STRIDE * (2u + SLOT_ENTRY_BASE), 0);
    CHECK(refused_shortcut(2, "equipped slot is empty"), "an empty equipped slot: refused");
    start();
    syn_poke_u32(payload() + PAYLOAD_KINDS + PAYLOAD_STRIDE * (2u + SLOT_ENTRY_BASE), 151);
    CHECK(refused_shortcut(2, "unknown stratagem kind"), "a kind without a code: codes' reason");
    start();
    syn_poke_u8(syn_local_actions() + MENU_DOWN, 1);
    CHECK(refused_shortcut(1, "menu key held"), "the menu key held: refused");
    start();
    syn_poke_u8(syn_local_actions() + MENU_DOWN, 2);
    CHECK(refused_shortcut(1, "invalid menu action"), "a menu action byte of 2: refused");
    start();
    syn_poke_u32(syn_ui() + UI_OBSTRUCTION, 1);
    syn_poke_u32(syn_local_component() + COUNT_AT, 1);
    CHECK(refused_shortcut(1, "UI obstructed"), "the UI obstructed (and the component dirty): refused, the UI first (R46)");
    start();
    syn_poke_u32(syn_local_component() + COUNT_AT, 1);
    CHECK(refused_shortcut(1, "close and reopen the menu"), "a direction already in the component: refused");
    start();
    syn_poke_u8(syn_local_actions() + ACTION_STRIDE * 3u, 1);
    CHECK(refused_shortcut(1, "manual direction input"), "a direction held: refused");
    start();
    view();
    syn_change_peer(0x5151515151515151ull);
    CHECK(refused_shortcut(1, "local player unavailable"), "no code-entry chain: refused");
    start();
    spoil_witness("input_handler");
    snprintf(want, sizeof want, "%s: witness input_handler differs", adm_feature_name(FEAT_ENTRY));
    CHECK(refused_shortcut(1, want), "ENTRY refused: refused with admission's reason");
    start();
    spoil_witness("wheel_action_sound");
    snprintf(want, sizeof want, "%s: witness wheel_action_sound differs", adm_feature_name(FEAT_LATCH));
    CHECK(refused_shortcut(1, want), "LATCH refused: refused with admission's reason, nothing written");

    start();
    CHECK(!entry_begin_shortcut(&job, NULL, 1, 70, false, 0, g_why, sizeof g_why) && reason_is("local player unavailable"),
          "a NULL view: refused");
    CHECK(!entry_begin_shortcut(NULL, view(), 1, 70, false, 0, NULL, 0), "a NULL job: refused");

    start();
    CHECK(shortcut(&job, 1, 70, false, 0), "a shortcut runs");
    copy = job;
    CHECK(!shortcut(&job, 2, 70, false, 0) && reason_is("a code is being entered") && memcmp(&copy, &job, sizeof job) == 0,
          "  another slot hotkey meanwhile: refused, the job left alone");
    {
        EntryJob other;
        memset(&other, 0, sizeof other);
        CHECK(!shortcut(&other, 2, 70, false, 0) && reason_is("a code is being entered") && other.state == ENTRY_IDLE,
              "  a second job while the shortcut is active: refused, left alone");
    }
    entry_cancel_shortcut(&job, view(), NULL);
    start();
    memset(&job, 0, sizeof job);
    CHECK(entry_begin(&job, view(), 118, 70, false, false, 0), "a List job runs");
    copy = job;
    CHECK(!shortcut(&job, 1, 70, false, 0) && reason_is("a code is being entered") && memcmp(&copy, &job, sizeof job) == 0
              && journal_is(0, 0) && calls_are(0, 0, 0),
          "  a slot hotkey meanwhile: refused, the job left alone, nothing latched");
}

int main(void)
{
    test_owner();
    CHECK(start(), "the synthetic image builds with eight payload entries and the binding map");
    test_acquire_and_release();
    test_refresh();
    test_release();
    test_acquire_refusals();
    test_shortcut_closed_menu();
    test_shortcut_open_menu();
    test_shortcut_slots();
    test_shortcut_instant();
    test_shortcut_fails_after_open();
    test_shortcut_confirm();
    test_shortcut_refusals();
    CHECK(syn_write_count() == 0, "nothing went through the refusing write port");
    syn_free();
    TEST_MAIN_END
}
