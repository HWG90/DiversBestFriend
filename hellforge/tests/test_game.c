/* flags: -DDBF_TEST_WITNESSES -DDBF_TEST_LONG_WITNESS */
/* Tests for src/game.c, the read-only readers, against the synthetic 25480438 image of tests/synthetic.c. Admission runs
 * for real over that image with the small witness table of tests/test_witnesses.h (alpha gates STATE and HUD_READ,
 * bravo STRATAGEMS, charlie HUD_READ): a test refuses a feature by changing a byte of its witness and letting the 30 s
 * grace run out (DBF_TEST_LONG_WITNESS adds echo_…, a STRATAGEMS witness with a 200-byte name, for reason truncation).
 * game.c keeps state in statics, so every test starts with start(), which builds the scene and calls mem_init, adm_init
 * and game_init again; test_before_init must run first. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "game.h"
#include "memory.h"
#include "synthetic.h"
#include "test.h"

#define VANILLA_TABLE 0x37cb600u
#define GRACE_OVER 30000u
#define OTHER_PEER 0x22ff00eeddcc4455ull

static GameView g_view;

static bool start(const SynScene* s)
{
    bool built = syn_build(s);
    mem_init(syn_mem_port());
    adm_init(syn_adm_port(), 0);
    game_init(SYN_GAME_BASE, SYN_IMAGE_SIZE);
    return built;
}

static bool start_default(SynScene* s)
{
    syn_default(s);
    return start(s);
}

static const GameView* read_view(void)
{
    memset(&g_view, 0xa5, sizeof g_view); /* game_read must set every field */
    game_read(&g_view);
    return &g_view;
}

static bool reason_is(const GameView* v, const char* text)
{
    if (strcmp(v->reason, text) == 0) return true;
    printf("  reason was \"%s\", expected \"%s\"\n", v->reason, text);
    return false;
}

static bool code_is(const DbfRow* r, const uint8_t* code, int n)
{
    return r->code_len == n && memcmp(r->code, code, (size_t)n) == 0;
}

/* The row is list card `card`: its address and its list position (the second float at +0x3740). */
static bool card_is(const DbfRow* r, int card)
{
    return r->card == syn_card(card) && r->list_y == syn_list_y(card);
}

/* Row `r` is list card `card` showing payload entry `entry` of the scene, with its kind and code. */
static bool row_is(const DbfRow* r, int card, const SynScene* s, int entry)
{
    uint8_t timer[DBF_OFF_CARD_TIMER_SIZE];
    const SynStratagem* st = &s->stratagems[entry];
    syn_timer_bytes(card, (uint32_t)entry, st->kind, timer);
    return r->active && card_is(r, card) && r->entry == (uint32_t)entry && r->kind == st->kind
        && code_is(r, st->code, st->code_len) && memcmp(r->timer, timer, sizeof timer) == 0;
}

/* The same row read without kinds and codes. */
static bool bare_row_is(const DbfRow* r, int card, const SynScene* s, int entry)
{
    uint8_t timer[DBF_OFF_CARD_TIMER_SIZE];
    syn_timer_bytes(card, (uint32_t)entry, entry < s->stratagem_count ? s->stratagems[entry].kind : 0, timer);
    return r->active && card_is(r, card) && r->entry == (uint32_t)entry && r->kind == 0 && r->code_len == 0
        && memcmp(r->timer, timer, sizeof timer) == 0;
}

/* The same row read with its kind but without a code (the code-entry chain failed). */
static bool kind_row_is(const DbfRow* r, int card, const SynScene* s, int entry)
{
    uint8_t timer[DBF_OFF_CARD_TIMER_SIZE];
    const SynStratagem* st = &s->stratagems[entry];
    syn_timer_bytes(card, (uint32_t)entry, st->kind, timer);
    return r->active && card_is(r, card) && r->entry == (uint32_t)entry && r->kind == st->kind && r->code_len == 0
        && memcmp(r->timer, timer, sizeof timer) == 0;
}

static bool default_rows_without_codes(const GameView* v, const SynScene* s)
{
    if (v->row_count != 4) return false;
    for (int i = 0; i < 4; i++)
        if (!kind_row_is(&v->rows[i], i, s, i)) return false;
    return true;
}

static bool default_rows(const GameView* v, const SynScene* s)
{
    if (v->row_count != 4) return false;
    for (int i = 0; i < 4; i++)
        if (!row_is(&v->rows[i], i, s, i)) return false;
    return true;
}

static bool rest_is_zero(const GameView* v)
{
    static const DbfRow ZERO;
    if (v->row_count < 0 || v->row_count > (int)DBF_VAL_CARD_COUNT) return false;
    for (int i = v->row_count; i < (int)DBF_VAL_CARD_COUNT; i++)
        if (memcmp(&v->rows[i], &ZERO, sizeof ZERO) != 0) return false;
    return true;
}

static bool local_is_zero(const GameView* v)
{
    static const GameLocal ZERO;
    return memcmp(&v->local, &ZERO, sizeof ZERO) == 0;
}

static bool no_codes(const GameView* v)
{
    for (int i = 0; i < v->row_count; i++)
        if (v->rows[i].code_len != 0) return false;
    return true;
}

static const DbfWitness* witness(const char* name)
{
    for (int i = 0; i < dbf_witness_count; i++)
        if (strcmp(dbf_witnesses[i].name, name) == 0) return &dbf_witnesses[i];
    return NULL;
}

/* Changes a byte of the witness and restarts admission past the grace period, so its features are refused. */
static void refuse_witness(const char* name, bool past_grace)
{
    const DbfWitness* w = witness(name);
    if (!w) return;
    syn_poke_u8(SYN_GAME_BASE + w->rva, (uint8_t)(w->bytes[0] ^ 0x55u));
    adm_init(syn_adm_port(), 0);
    if (past_grace) adm_tick(GRACE_OVER);
}

/* --- tests ----------------------------------------------------------------------------------------------------- */

static void test_before_init(void)
{
    const GameView* v = read_view();
    CHECK(reason_is(v, "not initialised") && !v->build_ok && !v->in_gameplay && !v->hud_ready && !v->menu_open
              && !v->local_ok && !v->scramble_known && v->table_rva == 0 && v->row_count == 0 && rest_is_zero(v)
              && local_is_zero(v),
          "before game_init: nothing read, reason \"not initialised\", every field set");
    game_read(NULL);
    CHECK(1, "game_read(NULL) is ignored");
}

static void test_reads_the_mission(void)
{
    SynScene s;
    const GameView* v;
    CHECK(start_default(&s), "the default scene builds");
    v = read_view();
    CHECK(v->build_ok && v->in_gameplay && v->hud_ready && v->menu_open && v->local_ok,
          "gameplay, HUD ready, menu open, local player found");
    CHECK(reason_is(v, ""), "nothing is missing: reason is empty");
    CHECK(v->table_rva == VANILLA_TABLE, "the vanilla definition table");
    CHECK(!v->scramble_known, "scramble_known is false: codes are not remapped");
    CHECK(v->row_count == 4, "four active cards, four rows");
    for (int i = 0; i < v->row_count && i < 4; i++) {
        char text[96];
        snprintf(text, sizeof text, "row %d: card %d, entry %d, kind %u, its code and its timer block", i, i, i,
                 (unsigned)s.stratagems[i].kind);
        CHECK(row_is(&v->rows[i], i, &s, i), text);
    }
    CHECK(syn_definition(50) % 8 == 4 && v->rows[2].kind == 50 && v->rows[2].code_len == 6,
          "a definition 4 mod 8 is read (kind 50, as live)");
    CHECK(syn_definition(63) % 8 == 0 && v->rows[3].code_len == 5, "an 8-aligned definition is read (kind 63)");
    CHECK(rest_is_zero(v), "rows past row_count are zero");
    v = read_view();
    CHECK(reason_is(v, "") && default_rows(v, &s), "a second read gives the same rows");
}

static void test_menu_closed(void)
{
    SynScene s;
    const GameView* v;
    syn_default(&s);
    s.menu_open = 0;
    start(&s);
    v = read_view();
    CHECK(!v->menu_open && v->in_gameplay && v->local_ok, "menu closed: menu_open false");
    CHECK(default_rows(v, &s) && reason_is(v, ""), "menu closed: the rows are still read (cooldown display)");
}

static void test_invalid_menu_flag(void)
{
    SynScene s;
    const GameView* v;
    start_default(&s);
    syn_poke_u8(syn_panel() + DBF_OFF_OPEN_BYTE_OFFSET, 2);
    v = read_view();
    CHECK(!v->menu_open && reason_is(v, "invalid menu-open flag") && v->row_count == 0,
          "menu-open byte 2: invalid, no rows (R46 drops the snapshot)");
    CHECK(v->in_gameplay && v->hud_ready && v->local_ok, "the local player is still read");
}

static void test_cards_in_list_order(void)
{
    SynScene s;
    const GameView* v;
    syn_default(&s);
    for (int i = 0; i < 16; i++) s.card_entry[i] = SYN_INACTIVE;
    s.card_entry[1] = 3;
    s.card_entry[3] = 0;
    s.card_entry[15] = 1;
    start(&s);
    v = read_view();
    CHECK(v->row_count == 3 && row_is(&v->rows[0], 1, &s, 3) && row_is(&v->rows[1], 3, &s, 0)
              && row_is(&v->rows[2], 15, &s, 1) && reason_is(v, ""),
          "cards 1, 3 and 15 active: three rows in list order (entries 3, 0, 1), card 15 included");
}

/* Makes the two tables differ, so a read shows which one it used: the table at `moved_rva` points kind 118 at a second
 * definition with its own code (ALTERNATE), and the vanilla table loses its entry for kind 4. */
static const uint8_t ALTERNATE[4] = { 4, 4, 2, 1 };

static bool tell_tables_apart(uint32_t moved_rva)
{
    uintptr_t alternate = syn_alternate_definition(118, 4, ALTERNATE);
    return alternate != 0 && syn_poke_u64(SYN_GAME_BASE + moved_rva + 118u * DBF_OFF_DEFINITION_STRIDE, alternate)
        && syn_poke_u64(SYN_GAME_BASE + VANILLA_TABLE + 4u * DBF_OFF_DEFINITION_STRIDE, 0);
}

/* Read through the moved table: kind 118 has the alternate code, kinds 4, 50 and 63 their own. */
static bool rows_follow_moved(const GameView* v, const SynScene* s)
{
    return v->row_count == 4 && v->rows[0].kind == 118 && code_is(&v->rows[0], ALTERNATE, 4)
        && row_is(&v->rows[1], 1, s, 1) && row_is(&v->rows[2], 2, s, 2) && row_is(&v->rows[3], 3, s, 3);
}

/* Read through the vanilla table: kind 118 has its own code, kind 4 none (its entry is gone). */
static bool rows_follow_vanilla(const GameView* v, const SynScene* s)
{
    return v->row_count == 4 && row_is(&v->rows[0], 0, s, 0) && v->rows[1].kind == 4 && v->rows[1].code_len == 0
        && row_is(&v->rows[2], 2, s, 2) && row_is(&v->rows[3], 3, s, 3);
}

/* Review Focus 1: the definition table, vanilla or moved by HellForge, and the rule for accepting it. */
static void test_definition_table(void)
{
    SynScene s;
    const GameView* v;
    uint32_t moved = SYN_IMAGE_SIZE + 0x1000u;
    start_default(&s);
    v = read_view();
    CHECK(v->table_rva == VANILLA_TABLE && default_rows(v, &s), "vanilla table first");
    CHECK(syn_relocate_table(moved), "HellForge's move: table copied to image_size + 0x1000, displacement rewritten");
    v = read_view();
    CHECK(v->table_rva == moved && default_rows(v, &s) && reason_is(v, ""),
          "moved table: same codes, table_rva == image_size + 0x1000");
    CHECK(tell_tables_apart(moved), "the moved copy and the vanilla table made to differ");
    v = read_view();
    CHECK(v->table_rva == moved && rows_follow_moved(v, &s) && reason_is(v, ""),
          "moved table: the codes come from the copy, not from the vanilla table");
    syn_poke_u32(SYN_GAME_BASE + DBF_RVA_DEFINITION_DISPLACEMENT, 0x1234567u);
    v = read_view();
    CHECK(reason_is(v, "definition table unrecognised") && v->table_rva == 0 && no_codes(v),
          "displacement 0x1234567: \"definition table unrecognised\", no codes");
    CHECK(v->row_count == 4 && v->rows[0].kind == 118 && v->rows[3].kind == 63 && v->local_ok,
          "the rows and their kinds are still read");

    struct { uint32_t rva; const char* reason; const char* text; } cases[] = {
        { SYN_IMAGE_SIZE - 8u, "definition table unrecognised", "image_size - 8: below the reservation" },
        { SYN_IMAGE_SIZE + 0x1004u, "definition table unrecognised", "image_size + 0x1004: not 8-aligned" },
        { SYN_IMAGE_SIZE + 0x400000u, "definition table unrecognised", "image_size + 0x400000: past the reservation" },
        { VANILLA_TABLE + 8u, "definition table unrecognised", "0x37cb608: inside the image, not the vanilla table" },
        { SYN_IMAGE_SIZE + 0x3ffff8u, "definition table unreadable", "image_size + 0x3ffff8: accepted but unreadable" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        syn_poke_u32(SYN_GAME_BASE + DBF_RVA_DEFINITION_DISPLACEMENT, cases[i].rva);
        v = read_view();
        CHECK(reason_is(v, cases[i].reason) && v->table_rva == 0 && no_codes(v), cases[i].text);
    }
    syn_poke_u32(SYN_GAME_BASE + DBF_RVA_DEFINITION_DISPLACEMENT, moved);
    v = read_view();
    CHECK(v->table_rva == moved && rows_follow_moved(v, &s) && reason_is(v, ""),
          "back to the moved table: its codes again");
    syn_poke_u32(SYN_GAME_BASE + DBF_RVA_DEFINITION_DISPLACEMENT, VANILLA_TABLE);
    v = read_view();
    CHECK(v->table_rva == VANILLA_TABLE && rows_follow_vanilla(v, &s) && reason_is(v, "invalid definition"),
          "back to the vanilla table: followed at once (kind 118's own code, kind 4 gone)");

    syn_default(&s);
    s.table_rva = SYN_IMAGE_SIZE + 0x3ff000u;
    start(&s);
    CHECK(tell_tables_apart(SYN_IMAGE_SIZE + 0x3ff000u), "a scene built with a moved table, the tables made to differ");
    v = read_view();
    CHECK(v->table_rva == SYN_IMAGE_SIZE + 0x3ff000u && rows_follow_moved(v, &s) && reason_is(v, ""),
          "a table moved before the first read is followed (image_size + 0x3ff000)");
    syn_unmap(SYN_GAME_BASE + DBF_RVA_DEFINITION_DISPLACEMENT);
    v = read_view();
    CHECK(reason_is(v, "definition table unreadable") && v->table_rva == 0 && no_codes(v) && v->row_count == 4,
          "displacement unreadable: no codes, rows kept");
}

/* Review Focus 2: the local identity changes between two reads. */
static void test_local_payload_changed(void)
{
    SynScene s, moved;
    const GameView* v;
    start_default(&s);
    v = read_view();
    CHECK(v->local_ok && default_rows(v, &s), "first read: local payload found");
    CHECK(syn_change_peer(OTHER_PEER), "a new session: session, player and mission entry get a new peer");
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "local payload changed") && v->row_count == 0 && rest_is_zero(v),
          "session peer changed: local_ok false, \"local payload changed\", no rows");
    CHECK(v->in_gameplay && v->hud_ready && v->menu_open, "the state before the local player is still read");
    v = read_view();
    CHECK(v->local_ok && reason_is(v, "") && default_rows(v, &s), "the next read takes the new identity");

    syn_poke_u64(syn_session() + DBF_OFF_SESSION_PEER_OFFSET, OTHER_PEER + 1u);
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "local payload changed") && v->row_count == 0,
          "only the session's peer changed: \"local payload changed\" first");
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "local mission payload unavailable") && v->row_count == 0,
          "then no mission entry carries the session's peer: no payload, no rows");
    syn_poke_u64(syn_session() + DBF_OFF_SESSION_PEER_OFFSET, OTHER_PEER);
    v = read_view();
    CHECK(v->local_ok && default_rows(v, &s), "they agree again: rows again");

    moved = s;
    moved.peer = OTHER_PEER;
    moved.local_entry = 2;
    CHECK(syn_build(&moved), "same peer, payload in another mission entry (no game_init)");
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "local payload changed") && v->row_count == 0,
          "payload address changed: \"local payload changed\", no rows");
    v = read_view();
    CHECK(v->local_ok && default_rows(v, &moved), "then the new payload is read");

    syn_change_peer(OTHER_PEER + 2u);
    game_init(SYN_GAME_BASE, SYN_IMAGE_SIZE);
    v = read_view();
    CHECK(v->local_ok && default_rows(v, &moved), "game_init forgets the identity: no change reported");

    syn_poke_u32(syn_game_state() + DBF_OFF_GAME_MODE_OFFSET, 3);
    v = read_view();
    syn_poke_u32(syn_game_state() + DBF_OFF_GAME_MODE_OFFSET, 4);
    syn_change_peer(OTHER_PEER + 3u);
    v = read_view();
    CHECK(reason_is(v, "local payload changed") && v->row_count == 0,
          "a change across a read outside gameplay is still reported once");
}

/* Review Focus 5: not in gameplay, HUD not ready. */
static void test_not_in_gameplay(void)
{
    SynScene s;
    const GameView* v;
    syn_default(&s);
    s.game_mode = 3;
    start(&s);
    v = read_view();
    CHECK(!v->in_gameplay && reason_is(v, "not in gameplay") && v->row_count == 0 && !v->local_ok && !v->hud_ready
              && !v->menu_open && rest_is_zero(v),
          "game state 3: in_gameplay false, \"not in gameplay\", no rows");
    CHECK(v->build_ok, "build_ok is still reported");

    syn_default(&s);
    s.hud_ready = 0;
    start(&s);
    v = read_view();
    CHECK(v->in_gameplay && !v->hud_ready && reason_is(v, "HUD not ready") && v->row_count == 0 && !v->local_ok
              && !v->menu_open,
          "ready byte 0: \"HUD not ready\", no rows");
    syn_poke_u8(syn_hud_root() + DBF_OFF_HUD_READY_OFFSET, 2);
    v = read_view();
    CHECK(!v->hud_ready && reason_is(v, "HUD not ready"), "ready byte 2: not ready either");
    syn_poke_u64(SYN_GAME_BASE + DBF_RVA_HUD_ROOT, 0);
    v = read_view();
    CHECK(!v->hud_ready && reason_is(v, "HUD not ready"), "no HUD root: not ready");

    start_default(&s);
    syn_unmap(syn_game_state() + DBF_OFF_GAME_MODE_OFFSET);
    v = read_view();
    CHECK(!v->in_gameplay && reason_is(v, "game state unreadable") && v->row_count == 0, "game state unreadable");
}

static void test_card_links(void)
{
    SynScene s;
    const GameView* v;
    start_default(&s);
    syn_poke_u64(syn_card(1) + DBF_OFF_NODE_PARENT_OFFSET, syn_list() + 8u);
    v = read_view();
    CHECK(v->row_count == 3 && row_is(&v->rows[0], 0, &s, 0) && row_is(&v->rows[1], 2, &s, 2)
              && row_is(&v->rows[2], 3, &s, 3),
          "card 1's parent link is wrong: card 1 skipped, cards 0, 2 and 3 read");
    CHECK(reason_is(v, "card 1 parent mismatch") && rest_is_zero(v), "reason names the card");

    start_default(&s);
    syn_poke_u64(syn_card(9) + DBF_OFF_NODE_PARENT_OFFSET, 0);
    v = read_view();
    CHECK(default_rows(v, &s) && reason_is(v, "card 9 parent mismatch"), "an inactive card's wrong link is reported too");

    start_default(&s);
    syn_poke_u8(syn_card(2) + DBF_OFF_CARD_ACTIVE_OFFSET, 2);
    v = read_view();
    CHECK(v->row_count == 3 && row_is(&v->rows[1], 1, &s, 1) && row_is(&v->rows[2], 3, &s, 3)
              && reason_is(v, "card 2 state invalid"),
          "card 2's active byte is 2: skipped, the rest read");

    start_default(&s);
    syn_unmap(syn_card(7) + DBF_OFF_CARD_ACTIVE_OFFSET);
    v = read_view();
    CHECK(default_rows(v, &s) && reason_is(v, "card 7 unreadable"), "an unreadable card is skipped and named");

    {
        struct { uintptr_t node; const char* reason; } links[] = {
            { syn_panel(), "HUD hierarchy not recognized: panel parent mismatch" },
            { syn_hud_root() + DBF_OFF_HUD_CONTAINER_OFFSET, "HUD hierarchy not recognized: HUD container parent mismatch" },
            { syn_panel() + DBF_OFF_PANEL_FADE_OFFSET, "HUD hierarchy not recognized: fade container parent mismatch" },
            { syn_panel() + DBF_OFF_PANEL_CONTENT_OFFSET,
              "HUD hierarchy not recognized: content container parent mismatch" },
            { syn_list(), "HUD hierarchy not recognized: list parent mismatch" },
        };
        for (size_t i = 0; i < sizeof links / sizeof links[0]; i++) {
            start_default(&s);
            syn_poke_u64(links[i].node + DBF_OFF_NODE_PARENT_OFFSET, syn_hud_root());
            v = read_view();
            CHECK(v->row_count == 0 && reason_is(v, links[i].reason) && v->local_ok && v->menu_open, links[i].reason);
        }
    }
}

static void test_entries_and_kinds(void)
{
    SynScene s;
    const GameView* v;
    syn_default(&s);
    s.card_entry[2] = 7;
    start(&s);
    v = read_view();
    CHECK(v->row_count == 4 && bare_row_is(&v->rows[2], 2, &s, 7) && row_is(&v->rows[3], 3, &s, 3) && reason_is(v, ""),
          "a card showing entry 7 of 4: kind 0, no code, no reason (R46 leaves the kind unset)");

    syn_default(&s);
    s.stratagems[1].kind = 150;
    s.stratagems[2].kind = 0;
    start(&s);
    v = read_view();
    CHECK(v->row_count == 4 && v->rows[1].kind == 150 && v->rows[1].code_len == 0 && v->rows[2].kind == 0
              && v->rows[2].code_len == 0 && row_is(&v->rows[0], 0, &s, 0) && reason_is(v, ""),
          "kind 150 (a HellForge mod's) and kind 0: listed without a code or a reason");

    start_default(&s);
    syn_poke_u32(syn_payload(s.local_entry) + DBF_OFF_PAYLOAD_COUNT_OFFSET, 33);
    v = read_view();
    CHECK(v->row_count == 4 && reason_is(v, "invalid stratagem entry count") && v->rows[0].kind == 0 && no_codes(v),
          "payload count 33: no kinds, rows kept");
    start_default(&s);
    syn_poke_u32(syn_payload(s.local_entry) + DBF_OFF_PAYLOAD_COUNT_OFFSET, 2);
    v = read_view();
    CHECK(v->row_count == 4 && row_is(&v->rows[1], 1, &s, 1) && bare_row_is(&v->rows[2], 2, &s, 2)
              && reason_is(v, ""),
          "payload count 2: entries 2 and 3 are not in it");
}

static void test_codes(void)
{
    SynScene s;
    const GameView* v;
    uint8_t twelve[12] = { 1, 2, 3, 4, 4, 3, 2, 1, 1, 3, 2, 4 };

    syn_default(&s);
    s.stratagems[0].code_len = 12;
    memcpy(s.stratagems[0].code, twelve, sizeof twelve);
    start(&s);
    v = read_view();
    CHECK(default_rows(v, &s) && code_is(&v->rows[0], twelve, 12), "a 12-direction code is read whole");

    start_default(&s);
    syn_poke_u32(syn_definition(4), 5);
    v = read_view();
    CHECK(v->row_count == 4 && v->rows[1].kind == 4 && v->rows[1].code_len == 0 && row_is(&v->rows[2], 2, &s, 2)
              && reason_is(v, "invalid definition"),
          "definition of kind 4 says kind 5: no code for it, the others read");

    struct { int count; const char* text; } counts[] = {
        { 0, "code count 0: invalid code array" }, { 13, "code count 13: invalid code array" } };
    for (size_t i = 0; i < 2; i++) {
        start_default(&s);
        syn_poke_u32(syn_definition(118) + DBF_OFF_DEFINITION_CODE_COUNT_OFFSET, (uint32_t)counts[i].count);
        v = read_view();
        CHECK(v->rows[0].code_len == 0 && reason_is(v, "invalid code array") && row_is(&v->rows[1], 1, &s, 1),
              counts[i].text);
    }

    start_default(&s);
    syn_poke_u32(syn_code_array(63) + 2u * DBF_OFF_CODE_STRIDE, 5);
    v = read_view();
    CHECK(v->rows[3].kind == 63 && v->rows[3].code_len == 0 && reason_is(v, "invalid direction"),
          "a direction of 5: no code for that kind");
    syn_poke_u32(syn_code_array(63) + 2u * DBF_OFF_CODE_STRIDE, 0);
    v = read_view();
    CHECK(v->rows[3].code_len == 0 && reason_is(v, "invalid direction"), "a direction of 0: the same");

    start_default(&s);
    syn_poke_u64(syn_definition(50) + DBF_OFF_DEFINITION_CODE_OFFSET, syn_settings() + DBF_OFF_SETTINGS_SIZE - 8u);
    v = read_view();
    CHECK(v->rows[2].code_len == 0 && reason_is(v, "code array outside the settings block"),
          "a code array running past the settings block: no code (R46's HD2Runtime owner is not ported)");
    {
        uintptr_t at = syn_settings() + DBF_OFF_SETTINGS_SIZE - 6u * DBF_OFF_CODE_STRIDE;
        for (unsigned i = 0; i < 6; i++) syn_poke_u32(at + i * DBF_OFF_CODE_STRIDE, s.stratagems[2].code[i]);
        syn_poke_u64(syn_definition(50) + DBF_OFF_DEFINITION_CODE_OFFSET, at);
        v = read_view();
        CHECK(code_is(&v->rows[2], s.stratagems[2].code, 6) && reason_is(v, ""),
              "a code array ending exactly at the settings block's end is inside it");
    }

    start_default(&s);
    syn_poke_u64(SYN_GAME_BASE + VANILLA_TABLE + 118u * DBF_OFF_DEFINITION_STRIDE,
                 syn_settings() + DBF_OFF_SETTINGS_SIZE - 396u);
    v = read_view();
    CHECK(v->rows[0].code_len == 0 && reason_is(v, "invalid definition"), "a definition running past the settings block");
    syn_poke_u64(SYN_GAME_BASE + VANILLA_TABLE + 118u * DBF_OFF_DEFINITION_STRIDE, syn_settings() - 8u);
    v = read_view();
    CHECK(v->rows[0].code_len == 0 && reason_is(v, "invalid definition"), "a definition below the settings block");
    syn_poke_u64(SYN_GAME_BASE + VANILLA_TABLE + 118u * DBF_OFF_DEFINITION_STRIDE, syn_definition(118) + 2u);
    v = read_view();
    CHECK(v->rows[0].code_len == 0 && reason_is(v, "invalid definition"), "a definition pointer 2 mod 4");
}

static void test_admission_gates(void)
{
    SynScene s;
    const GameView* v;

    start_default(&s);
    refuse_witness("bravo", true);
    v = read_view();
    CHECK(reason_is(v, "Stratagems: witness bravo differs"), "Stratagems refused: reason carries admission's reason");
    CHECK(v->row_count == 4 && no_codes(v) && v->table_rva == 0 && bare_row_is(&v->rows[0], 0, &s, 0)
              && bare_row_is(&v->rows[3], 3, &s, 3),
          "Stratagems refused: no kinds, no codes, cards still read");
    CHECK(v->local_ok && v->in_gameplay && v->menu_open, "Stratagems refused: the state is still read");

    start_default(&s);
    refuse_witness("bravo", false);
    v = read_view();
    CHECK(reason_is(v, "Stratagems: witness bravo differs (retrying)") && no_codes(v),
          "Stratagems pending: no codes either");

    start_default(&s);
    refuse_witness("charlie", true);
    v = read_view();
    CHECK(reason_is(v, "HUD reads: witness charlie differs") && v->row_count == 0 && v->local_ok && v->menu_open
              && v->table_rva == VANILLA_TABLE,
          "HUD reads refused: no cards, the rest read");

    start_default(&s);
    refuse_witness("alpha", true);
    v = read_view();
    CHECK(reason_is(v, "Selection state: witness alpha differs") && !v->in_gameplay && !v->hud_ready && !v->local_ok
              && v->row_count == 0 && v->build_ok,
          "Selection state refused: nothing read");

    start_default(&s);
    syn_poke_u32(SYN_GAME_BASE + 0x80u + 8u, 0x6AE0E5FFu);
    adm_init(syn_adm_port(), 0);
    v = read_view();
    CHECK(!v->build_ok && reason_is(v, "Selection state: build 6ae0e5ff is not 25480438") && v->row_count == 0,
          "wrong build: build_ok false, nothing read");
}

/* The rows come from R46's display path (input.lua:218-234): the session's peer, the one mission entry carrying it, its
 * payload. The code-entry chain (input.lua:102-126) only decides local_ok and the codes. */
static void test_display_path(void)
{
    SynScene s;
    const GameView* v;
    start_default(&s);
    syn_poke_u32(syn_players() + DBF_OFF_PLAYERS_NETWORK_OFFSET, 4); /* no registry entry for the local player */
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "local ownership mapping unavailable"),
          "registry entry missing: local_ok false, reason names the failing step");
    CHECK(default_rows_without_codes(v, &s) && v->menu_open && v->in_gameplay && v->table_rva == VANILLA_TABLE,
          "registry entry missing: rows and kinds still served, no codes");

    start_default(&s);
    syn_poke_u64(syn_mission() + (uintptr_t)s.local_entry * DBF_OFF_MISSION_ENTRY_STRIDE, OTHER_PEER);
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "local mission payload unavailable") && v->row_count == 0 && rest_is_zero(v),
          "payload missing: no rows");

    start_default(&s);
    syn_poke_u32(syn_players() + DBF_OFF_PLAYERS_COUNT_OFFSET, 0);
    refuse_witness("bravo", true);
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "no local player") && v->row_count == 4 && no_codes(v)
              && bare_row_is(&v->rows[0], 0, &s, 0),
          "chain broken and Stratagems refused: rows without kinds, the chain's reason first");

    start_default(&s);
    syn_poke_u32(syn_players() + DBF_OFF_PLAYERS_COUNT_OFFSET, 0);
    v = read_view();
    CHECK(!v->local_ok && default_rows_without_codes(v, &s), "a read with the chain broken keeps the identity");
    syn_poke_u32(syn_players() + DBF_OFF_PLAYERS_COUNT_OFFSET, 2);
    syn_change_peer(OTHER_PEER);
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "local payload changed") && v->row_count == 0,
          "a new session after it is still reported once");
    v = read_view();
    CHECK(v->local_ok && default_rows(v, &s), "and then read whole");
}

static void test_local_player(void)
{
    SynScene s;
    const GameView* v;
    uintptr_t pm = syn_players(), m = syn_avatars();
    /* The code-entry chain fails: local_ok false, no codes, rows and kinds still served. */
    struct { uintptr_t at; int size; uint64_t value; const char* reason; } chain[] = {
        { pm + DBF_OFF_PLAYERS_COUNT_OFFSET, 4, 0, "no local player" },
        { pm + DBF_OFF_PLAYERS_NETWORK_OFFSET, 4, 0x7fff, "local network index unavailable" },
        { pm + DBF_OFF_PLAYERS_NETWORK_OFFSET, 4, 4, "local ownership mapping unavailable" },
        { syn_registry() + DBF_OFF_REGISTRY_LOOKUP_OFFSET + DBF_OFF_LOOKUP_CAPACITY_OFFSET, 4, 0,
          "invalid lookup capacity" },
        { syn_registry() + DBF_OFF_REGISTRY_LOOKUP_OFFSET + DBF_OFF_LOOKUP_CAPACITY_OFFSET, 4, 131072,
          "invalid lookup capacity" },
        { syn_registry() + DBF_OFF_REGISTRY_LOOKUP_OFFSET + DBF_OFF_LOOKUP_CAPACITY_OFFSET, 4, 48,
          "lookup capacity is not a power of two" },
        { m + DBF_OFF_AVATARS_COUNT_OFFSET, 4, 0, "invalid avatar count" },
        { m + DBF_OFF_AVATARS_COUNT_OFFSET, 4, 9, "invalid avatar count" },
        { m + DBF_OFF_AVATARS_COUNT_OFFSET, 4, 1, "lookup index out of bounds" },
        { syn_local_unit() + DBF_OFF_UNIT_KEY_OFFSET, 4, 0x1234, "avatar identity mismatch" },
        { syn_local_avatar() + DBF_OFF_AVATAR_COMPONENT_OFFSET + DBF_OFF_COMPONENT_OWNER_OFFSET, 4, 0x1234,
          "input owner mismatch" },
        { syn_local_avatar() + DBF_OFF_AVATAR_CONTEXT_OFFSET, 4, 0x77, "local ownership mapping unavailable" },
        { pm + DBF_OFF_PLAYERS_PEER_OFFSET + 2u * DBF_OFF_PLAYERS_PEER_STRIDE, 8, OTHER_PEER, "local peer mismatch" },
        /* R46 input.lua:126: a zero player-manager peer never matches, though the session's is not zero. */
        { pm + DBF_OFF_PLAYERS_PEER_OFFSET + 2u * DBF_OFF_PLAYERS_PEER_STRIDE, 8, 0, "local peer mismatch" },
    };
    /* The display path fails: no payload, no rows. */
    struct { uintptr_t at; int size; uint64_t value; const char* reason; } payload[] = {
        { syn_session() + DBF_OFF_SESSION_PEER_OFFSET, 8, OTHER_PEER, "local mission payload unavailable" },
        { syn_session() + DBF_OFF_SESSION_PEER_OFFSET, 8, 0, "local session unavailable" },
        { syn_mission() + DBF_OFF_MISSION_PEER_COUNT_OFFSET, 4, 33, "invalid mission peer count" },
        { syn_mission() + DBF_OFF_MISSION_PEER_COUNT_OFFSET, 4, 1, "local mission payload unavailable" },
        { syn_mission(), 8, 0x1100aabbccdd2233ull, "ambiguous local payload" },
        { syn_mission() + DBF_OFF_MISSION_ENTRY_STRIDE, 8, OTHER_PEER, "local mission payload unavailable" },
    };
    for (size_t i = 0; i < sizeof chain / sizeof chain[0]; i++) {
        char text[128];
        start_default(&s);
        if (chain[i].size == 4) syn_poke_u32(chain[i].at, (uint32_t)chain[i].value);
        else syn_poke_u64(chain[i].at, chain[i].value);
        v = read_view();
        snprintf(text, sizeof text, "code-entry chain: \"%s\" (case %u), rows and kinds kept, no codes", chain[i].reason,
                 (unsigned)i);
        CHECK(!v->local_ok && reason_is(v, chain[i].reason) && default_rows_without_codes(v, &s) && v->in_gameplay
                  && v->hud_ready && local_is_zero(v),
              text);
    }
    for (size_t i = 0; i < sizeof payload / sizeof payload[0]; i++) {
        char text[128];
        start_default(&s);
        if (payload[i].size == 4) syn_poke_u32(payload[i].at, (uint32_t)payload[i].value);
        else syn_poke_u64(payload[i].at, payload[i].value);
        v = read_view();
        snprintf(text, sizeof text, "display path: \"%s\" (case %u), no rows", payload[i].reason, (unsigned)i);
        CHECK(!v->local_ok && reason_is(v, payload[i].reason) && v->row_count == 0 && v->in_gameplay && v->hud_ready,
              text);
    }

    start_default(&s);
    syn_poke_u64(syn_session() + DBF_OFF_SESSION_PEER_OFFSET, 0);
    syn_poke_u64(pm + DBF_OFF_PLAYERS_PEER_OFFSET + 2u * DBF_OFF_PLAYERS_PEER_STRIDE, 0);
    syn_poke_u64(syn_mission() + (uintptr_t)s.local_entry * DBF_OFF_MISSION_ENTRY_STRIDE, 0);
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "local session unavailable") && v->row_count == 0, "a zero peer is no peer");

    start_default(&s);
    syn_unmap(syn_session() + DBF_OFF_SESSION_PEER_OFFSET);
    v = read_view();
    CHECK(!v->local_ok && reason_is(v, "session unreadable") && v->row_count == 0, "session unreadable");
}

static void test_first_reason_wins(void)
{
    SynScene s;
    const GameView* v;
    start_default(&s);
    syn_poke_u8(syn_panel() + DBF_OFF_OPEN_BYTE_OFFSET, 9);
    syn_poke_u32(syn_players() + DBF_OFF_PLAYERS_COUNT_OFFSET, 0);
    v = read_view();
    CHECK(reason_is(v, "invalid menu-open flag") && !v->local_ok, "the HUD's reason comes before the local player's");

    start_default(&s);
    syn_poke_u32(SYN_GAME_BASE + DBF_RVA_DEFINITION_DISPLACEMENT, 0x1234567u);
    syn_poke_u64(syn_card(0) + DBF_OFF_NODE_PARENT_OFFSET, 0);
    v = read_view();
    CHECK(reason_is(v, "definition table unrecognised") && v->row_count == 3,
          "the definitions' reason comes before the cards'");

    start_default(&s);
    syn_poke_u64(syn_card(0) + DBF_OFF_NODE_PARENT_OFFSET, 0);
    syn_poke_u32(syn_definition(63), 1);
    v = read_view();
    CHECK(reason_is(v, "card 0 parent mismatch") && v->row_count == 3 && v->rows[2].code_len == 0,
          "within the cards, list order decides");
}

/* GameView.local: R46's context (input.lua:114-137) when the code-entry chain holds, zero otherwise. */
static void test_local_context(void)
{
    SynScene s;
    const GameView* v;
    uintptr_t menu, ui_word;
    start_default(&s);
    v = read_view();
    CHECK(v->local_ok && reason_is(v, ""), "local context: the chain holds");
    CHECK(v->local.manager == syn_avatars() && v->local.avatar == syn_local_avatar()
              && v->local.component == syn_local_component() && v->local.actions == syn_local_actions()
              && v->local.input_owner == syn_local_input_owner() && v->local.payload == syn_payload(s.local_entry)
              && v->local.controls == syn_controls() && v->local.key == syn_local_key()
              && v->local.index == syn_local_index(),
          "local context: manager, avatar, component, actions, input owner, payload, controls, key and index are the "
          "synthetic layout's");
    CHECK(v->local.menu_active && v->local.unobstructed, "local context: menu active (word 0x205), unobstructed (UI word 0)");

    menu = syn_local_avatar() + DBF_OFF_AVATAR_MENU_OFFSET;
    syn_poke_u32(menu, 0xfffffdffu);
    v = read_view();
    CHECK(v->local_ok && !v->local.menu_active && reason_is(v, "") && default_rows(v, &s),
          "every bit but 9: menu_active false; the chain does not need it (R46's allow_closed)");
    syn_poke_u32(menu, 0x200u);
    v = read_view();
    CHECK(v->local_ok && v->local.menu_active, "bit 9 alone: menu_active true");

    ui_word = syn_ui() + DBF_OFF_UI_OBSTRUCTION_OFFSET + DBF_OFF_UI_OBSTRUCTION_WORD_OFFSET;
    syn_poke_u32(ui_word, 1);
    v = read_view();
    CHECK(v->local_ok && !v->local.unobstructed && reason_is(v, "") && default_rows(v, &s),
          "UI word 1: obstructed, nothing else changes");
    syn_poke_u32(ui_word, 0);
    v = read_view();
    CHECK(v->local.unobstructed, "UI word 0 again: unobstructed");

    syn_poke_u64(SYN_GAME_BASE + DBF_RVA_UI, 0);
    v = read_view();
    CHECK(v->local_ok && !v->local.unobstructed && reason_is(v, "UI unreadable") && default_rows(v, &s)
              && v->local.component == syn_local_component(),
          "no UI: obstructed, \"UI unreadable\", the chain and the codes still hold");

    start_default(&s);
    syn_poke_u64(SYN_GAME_BASE + DBF_RVA_CONTROLS, 0);
    v = read_view();
    CHECK(v->local_ok && v->local.controls == 0 && v->local.unobstructed && reason_is(v, "controls unreadable")
              && default_rows(v, &s) && v->local.actions == syn_local_actions(),
          "no controls: controls 0, \"controls unreadable\", the rest of the context filled");

    syn_default(&s);
    s.menu_open = 0;
    start(&s);
    v = read_view();
    CHECK(!v->menu_open && v->local_ok && v->local.menu_active, "the menu-active bit is read apart from the menu-open byte");

    start_default(&s);
    syn_poke_u32(syn_players() + DBF_OFF_PLAYERS_COUNT_OFFSET, 0);
    v = read_view();
    CHECK(!v->local_ok && local_is_zero(v), "chain broken: local is all zero");
}

/* Plan 1's final review: a lookup probes at most 256 slots (R46 walked the whole table, up to 65536 reads). */
static void test_lookup_probe_limit(void)
{
    SynScene s;
    const GameView* v;
    struct { uint32_t capacity; int position, empty_at; bool found; const char* reason; const char* text; } cases[] = {
        { 512, 255, -1, true, "", "512 full slots, the key at probe 255 (the 256th): found" },
        { 512, 256, -1, false, "lookup probe limit", "the key at probe 256 (the 257th): past the 256-probe limit" },
        { 512, 300, -1, false, "lookup probe limit", "300 full slots before the key, no empty slot: the limit" },
        { 512, -1, -1, false, "lookup probe limit", "512 full slots, no key, no empty slot: the limit" },
        { 256, -1, -1, false, "local ownership mapping unavailable", "256 full slots, no key: all probed, not found" },
        { 256, 255, -1, true, "", "256 slots, the key in the last of them: found" },
        { 64, 4, 3, false, "local ownership mapping unavailable", "the key placed after an empty slot: not found" },
        { 64, 3, 4, true, "", "the key placed before an empty slot: found" },
    };
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        bool laid;
        start_default(&s);
        laid = syn_registry_probe(cases[i].capacity, cases[i].position, cases[i].empty_at);
        v = read_view();
        CHECK(laid && v->local_ok == cases[i].found && reason_is(v, cases[i].reason)
                  && (cases[i].found ? default_rows(v, &s) : default_rows_without_codes(v, &s)),
              cases[i].text);
    }
}

/* game_lookup, exported for codes: the same lookup, without a reason. */
static void test_game_lookup(void)
{
    SynScene s;
    uint32_t index = 77;
    start_default(&s);
    CHECK(game_lookup(syn_avatars(), DBF_OFF_AVATARS_LOOKUP_OFFSET, syn_local_key(), DBF_VAL_AVATAR_MAX, &index)
              && index == syn_local_index(),
          "game_lookup finds the local avatar's index");
    index = 77;
    CHECK(!game_lookup(syn_avatars(), DBF_OFF_AVATARS_LOOKUP_OFFSET, syn_local_key(), syn_local_index(), &index)
              && index == 77,
          "an index at the limit fails and leaves the output alone");
    CHECK(!game_lookup(syn_avatars(), DBF_OFF_AVATARS_LOOKUP_OFFSET, 0x1234u, DBF_VAL_AVATAR_MAX, &index) && index == 77,
          "a missing key fails and leaves the output alone");
    CHECK(!game_lookup(syn_avatars(), DBF_OFF_AVATARS_LOOKUP_OFFSET, syn_local_key(), DBF_VAL_AVATAR_MAX, NULL),
          "a NULL output fails");
    CHECK(!game_lookup(syn_avatars() + 0x10u, DBF_OFF_AVATARS_LOOKUP_OFFSET, syn_local_key(), DBF_VAL_AVATAR_MAX, &index)
              && index == 77,
          "a table that is not there fails");
}

/* A definition the reader accepts lies in [settings, settings + 80280 - 400] (R46 input.lua:164): `at` gets kind 118's
 * definition (its kind, code array and count) and the table's entry for 118 points at it. */
static bool definition_at(uintptr_t at, const SynScene* s)
{
    return syn_poke_u32(at, 118) && syn_poke_u64(at + DBF_OFF_DEFINITION_CODE_OFFSET, syn_code_array(118))
        && syn_poke_u32(at + DBF_OFF_DEFINITION_CODE_COUNT_OFFSET, s->stratagems[0].code_len)
        && syn_poke_u64(SYN_GAME_BASE + VANILLA_TABLE + 118u * DBF_OFF_DEFINITION_STRIDE, at);
}

static void test_definition_bounds(void)
{
    SynScene s;
    const GameView* v;
    uintptr_t low = syn_settings(), high = syn_settings() + 80280u - 400u;
    struct { uintptr_t at; bool ok; const char* text; } at[] = {
        { low, true, "a definition starting exactly at the settings block is inside it" },
        { high, true, "a definition ending exactly at the block's end (settings + 80280 - 400) is inside it" },
        { low - 1u, false, "a definition one byte below the block is refused" },
        { high + 1u, false, "a definition one byte past settings + 80280 - 400 is refused" },
        { low - 4u, false, "a 4-aligned definition below the block is refused by the bound" },
        { high + 4u, false, "a 4-aligned definition running 4 bytes past the block is refused by the bound" },
    };
    for (size_t i = 0; i < sizeof at / sizeof at[0]; i++) {
        bool laid;
        start_default(&s);
        laid = definition_at(at[i].at, &s);
        v = read_view();
        if (at[i].ok)
            CHECK(laid && default_rows(v, &s) && reason_is(v, ""), at[i].text);
        else
            CHECK(laid && v->rows[0].kind == 118 && v->rows[0].code_len == 0 && reason_is(v, "invalid definition")
                      && row_is(&v->rows[1], 1, &s, 1),
                  at[i].text);
    }
}

/* Plan 1's final review: a reason longer than the buffer is cut, never overrun. */
static void test_reason_truncation(void)
{
    static struct { GameView view; unsigned char after[64]; } guarded;
    static const char START[] = "Stratagems: witness echo_a_witness_name_far_longer";
    SynScene s;
    const char* name = NULL;
    bool intact = true;
    for (int i = 0; i < dbf_witness_count; i++)
        if (strlen(dbf_witnesses[i].name) == 200) name = dbf_witnesses[i].name;
    CHECK(name != NULL, "the test table has a witness whose name is 200 bytes");
    if (!name) return;
    start_default(&s);
    refuse_witness(name, true);
    memset(&guarded, 0x5a, sizeof guarded);
    game_read(&guarded.view);
    for (size_t i = 0; i < sizeof guarded.after; i++)
        if (guarded.after[i] != 0x5a) intact = false;
    CHECK(strlen(guarded.view.reason) == DBF_REASON_SIZE - 1 && strncmp(guarded.view.reason, START, sizeof START - 1) == 0,
          "the 200-byte witness name: \"Stratagems: witness echo_…\" cut to DBF_REASON_SIZE - 1 bytes");
    CHECK(intact, "nothing past the GameView was written");
    CHECK(guarded.view.row_count == 4 && no_codes(&guarded.view) && guarded.view.local_ok,
          "the rows are still read, without codes");
}

/* DbfRow.list_y is the second float of the card's layout target (+0x3740, R46 native.lua:60, 274-276), and R46's pair()
 * (native.lua:71) refuses a NaN or a magnitude over 100000 in either float: that card is skipped. */
static void test_list_position(void)
{
    SynScene s;
    const GameView* v;
    union { uint32_t bits; float f; } nan = { 0x7fc00000u }, inf = { 0x7f800000u };
    struct { float x, y; bool ok; const char* text; } cases[] = {
        { 31.0f, 100000.0f, true, "list_y 100000: the largest R46 accepts" },
        { -100000.0f, -100000.0f, true, "both floats -100000: accepted" },
        { 31.0f, 100000.0078125f, false, "list_y just above 100000: card skipped" },
        { 31.0f, nan.f, false, "list_y NaN: card skipped" },
        { 31.0f, -inf.f, false, "list_y -infinity: card skipped" },
        { 200000.0f, 5.0f, false, "the first float out of range: card skipped (R46 checks both)" },
        { nan.f, 5.0f, false, "the first float NaN: card skipped" },
    };
    start_default(&s);
    v = read_view();
    CHECK(v->row_count == 4 && card_is(&v->rows[0], 0) && card_is(&v->rows[3], 3) && v->rows[0].list_y == 412.5f
              && v->rows[3].list_y == 270.75f,
          "each row carries its card's address and list position");
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++) {
        float pair[2] = { cases[i].x, cases[i].y };
        start_default(&s);
        syn_poke(syn_card(1) + DBF_OFF_CARD_TARGET_OFFSET, pair, sizeof pair);
        v = read_view();
        if (cases[i].ok)
            CHECK(v->row_count == 4 && v->rows[1].card == syn_card(1) && v->rows[1].list_y == cases[i].y
                      && v->rows[1].entry == 1 && reason_is(v, ""),
                  cases[i].text);
        else
            CHECK(v->row_count == 3 && row_is(&v->rows[1], 2, &s, 2) && reason_is(v, "card 1 layout unavailable"),
                  cases[i].text);
    }
}

static void test_reinit(void)
{
    SynScene s;
    const GameView* v;
    start_default(&s);
    game_init(0, SYN_IMAGE_SIZE);
    v = read_view();
    CHECK(reason_is(v, "not initialised") && v->row_count == 0, "game_init with base 0: not initialised");
    game_init(SYN_GAME_BASE, SYN_IMAGE_SIZE);
    v = read_view();
    CHECK(default_rows(v, &s) && reason_is(v, ""), "game_init again: reads again");
    game_init(SYN_GAME_BASE, 0);
    v = read_view();
    CHECK(reason_is(v, "not initialised") && !v->in_gameplay && !v->local_ok && v->row_count == 0 && local_is_zero(v)
              && v->table_rva == 0,
          "game_init with image size 0: not initialised, nothing read");
    game_init(SYN_GAME_BASE, SYN_IMAGE_SIZE);
    v = read_view();
    CHECK(default_rows(v, &s) && reason_is(v, ""), "game_init with the size again: reads again");
}

int main(void)
{
    test_before_init();
    test_reads_the_mission();
    test_menu_closed();
    test_invalid_menu_flag();
    test_cards_in_list_order();
    test_definition_table();
    test_local_payload_changed();
    test_not_in_gameplay();
    test_card_links();
    test_entries_and_kinds();
    test_codes();
    test_admission_gates();
    test_display_path();
    test_local_player();
    test_first_reason_wins();
    test_local_context();
    test_lookup_probe_limit();
    test_game_lookup();
    test_definition_bounds();
    test_reason_truncation();
    test_list_position();
    test_reinit();
    CHECK(syn_write_count() == 0, "no reader asked for a single write");
    syn_free();
    TEST_MAIN_END
}
