/* flags: -DDBF_TEST_NATIVE_LIST */
#include "native_list.h"
#include "synthetic.h"
#include "test.h"
#include <string.h>

static const unsigned containers[] = {0x1f18, 0x24a8, 0x2870};
static const unsigned children[] = {0x2028, 0x25b8, 0x2980};
static const float scale[] = {1.0f, 2.0f}, style[] = {0.5f, 1.0f, 0.5f, 0.25f};
static GameView view;
static int calls, logs, reads;
static uintptr_t unreadable;

static int read_port(uintptr_t address, void* out, size_t size)
{
    ++reads;
    if (unreadable >= address && unreadable - address < size) return -1;
    return syn_read(address, out, size);
}

static void checkpoint(const char* s)
{
    if (!strncmp(s, "call widget_scale(0x", 20) || !strncmp(s, "call text_colour(0x", 19)) ++logs;
}

void list_test_set(uintptr_t widget, bool is_scale, const float* values)
{
    ++calls;
    if (calls != logs || !syn_poke(widget + (is_scale ? 0x14 : 0x48), values, (is_scale ? 2u : 3u) * sizeof(float)))
        ++g_test_failures;
}

static bool start(void)
{
    SynScene scene;
    syn_default(&scene);
    if (!syn_build(&scene)) return false;
    MemPort port = {read_port, syn_write};
    mem_init(&port);
    adm_init(syn_adm_port(), 0);
    game_init(SYN_GAME_BASE, SYN_IMAGE_SIZE);
    native_list_init(SYN_GAME_BASE, checkpoint);
    calls = logs = 0;
    unreadable = 0;
    for (int i = 0; i < 4; ++i) {
        uintptr_t card = syn_card(i);
        syn_poke(card + 0x14, scale, sizeof scale);
        syn_poke_u32(card + 0x3718 + 0x40, i == 3 ? 5 : 0);
        for (int j = 0; j < 3; ++j) {
            uintptr_t w = card + containers[j];
            syn_poke_u64(w + 0xf0, card + 0x400);
            syn_poke_u64(card + 0x400 + 0xf0, card);
            syn_poke_u64(card + children[j] + 0xf0, w);
            syn_poke(w + 0x44, style, sizeof style);
        }
    }
    game_read(&view);
    return view.row_count == 4 && view.rows[0].card == syn_card(0);
}

static float value(uintptr_t at)
{
    float f;
    return syn_read(at, &f, sizeof f) ? -10 : f;
}

static void styling(void)
{
    CHECK(start(), "real game reader supplies active native cards");
    native_list_update(&view, 0);
    CHECK(calls == 7 && value(syn_card(0)+0x14) == 1.1f && value(syn_card(0)+0x18) == 2.2f,
          "both selected scale axes use their originals; unavailable row excluded");
    for (int j = 0; j < 3; ++j) {
        uintptr_t w = syn_card(1) + containers[j];
        CHECK(value(w+0x44) == .5f && value(w+0x48) == .35f && value(w+0x4c) == .175f &&
              value(w+0x50) == .0875f, "native fade alpha preserved, each RGB channel multiplied");
    }
    native_list_update(&view, 0);
    CHECK(calls == 7, "unchanged tick performs zero setter calls");
    float fade = .875f, foreign = .9f;
    uintptr_t name = syn_card(1) + containers[0];
    syn_poke(name+0x44, &fade, sizeof fade);
    syn_poke(syn_card(2)+containers[1]+0x48, &foreign, sizeof foreign);
    native_list_update(&view, 1);
    CHECK(value(syn_card(0)+0x14) == 1 && value(name+0x48) == 1 && value(name+0x44) == fade &&
          value(syn_card(1)+0x14) == 1.1f, "selection move restores originals and preserves native fade");
    native_list_update(&view, -1);
    CHECK(value(syn_card(1)+0x14) == 1 && value(syn_card(2)+containers[1]+0x48) == foreign,
          "release restores owned scale and leaves a foreign RGB change alone");
}

static void transient(void)
{
    CHECK(start(), "start transient case");
    native_list_update(&view, 0);
    unreadable = syn_list()+0xf0;
    native_list_update(&view, -1);
    unreadable = 0;
    native_list_update(&view, 0);
    CHECK(calls == 7 && value(syn_card(0)+0x14) == 1.1f, "reopen after unreadable hierarchy does not compound");
    unreadable = syn_card(1)+children[2]+0xf0;
    native_list_update(&view, -1);
    CHECK(value(syn_card(1)+containers[0]+0x48) == .35f, "broken third child blocks all three text restores");
    unreadable = 0;
    native_list_update(&view, -1);
    CHECK(value(syn_card(1)+containers[0]+0x48) == 1, "retry after transient child read restores true original");
}

static void idle(void)
{
    CHECK(start(), "start closed menu case");
    view.menu_open = false;
    reads = 0;
    native_list_update(&view, 0);
    CHECK(reads == 0, "idle closed menu never reads game memory");
    view.menu_open = true;
    native_list_update(&view, 0);
    syn_poke_u8(syn_panel()+DBF_OFF_OPEN_BYTE_OFFSET, 0);
    view.menu_open = false;
    native_list_update(&view, -1);
    CHECK(calls == 14, "first closed tick restores all seven held properties");
    reads = 0;
    native_list_update(&view, -1);
    CHECK(reads == 0, "after cleanup the closed tick is idle again");
}

static void identity(void)
{
    CHECK(start(), "start identity case");
    native_list_update(&view, 0);
    syn_poke_u64(SYN_GAME_BASE+DBF_RVA_HUD_ROOT, view.hud + 0x1000000);
    native_list_update(&view, -1);
    CHECK(calls == 7, "old view cannot restore through a replaced HUD root");
    syn_poke_u64(SYN_GAME_BASE+DBF_RVA_HUD_ROOT, view.hud);
    native_list_update(&view, -1);
    CHECK(calls == 7, "return of old address after replacement never revives ownership");
    CHECK(start(), "start recycled row case");
    native_list_update(&view, 0);
    syn_poke_u32(syn_card(0)+0x3748, 13);
    native_list_update(&view, -1);
    CHECK(calls == 7, "stale entry in view prevents a write");
    view.rows[0].entry = 13;
    native_list_update(&view, -1);
    CHECK(value(syn_card(0)+0x14) == 1.1f, "replacement entry never inherits original scale ownership");
    CHECK(start(), "start malformed rows");
    view.rows[0].card += 8;
    native_list_update(&view, 0);
    CHECK(calls == 0, "off-stride card rejected");
}

static void guards(void)
{
    CHECK(start(), "start tween and admission case");
    uintptr_t card = syn_card(0);
    syn_poke_u32(card, 0x02000000);
    syn_poke_u64(card+0xa8, (uint64_t)37 << 33);
    native_list_update(&view, 0);
    CHECK(calls == 6 && value(card+0x14) == 1, "scale setter cannot cancel a running tween");
    syn_poke_u64(card+0xa8, 1); /* unrelated low slot */
    unreadable = card+0xa8;
    native_list_update(&view, 0);
    CHECK(calls == 6, "unreadable scale slot defers application");
    unreadable = 0;
    native_list_update(&view, 0);
    CHECK(calls == 7 && value(card+0x14) == 1.1f, "highlight retries once the scale slot is idle");
    unreadable = card;
    native_list_update(&view, -1);
    CHECK(value(card+0x14) == 1.1f, "restore also requires readable tween state");
    unreadable = 0;
    native_list_update(&view, -1);
    CHECK(value(card+0x14) == 1, "deferred restore retries");
    syn_poke_u8(SYN_GAME_BASE + DBF_FN_WIDGET_SCALE + 0xbe, 0);
    native_list_update(&view, 0);
    CHECK(value(card+0x14) == 1, "live tween instruction tamper after admission prevents scale call");
    adm_init(syn_adm_port(), 0);
    int before = calls;
    native_list_update(&view, 2);
    CHECK(calls == before, "pending list witness blocks all setters");
}

int main(void)
{
    styling();
    transient();
    identity();
    guards();
    idle();
    syn_free();
    TEST_MAIN_END
}
