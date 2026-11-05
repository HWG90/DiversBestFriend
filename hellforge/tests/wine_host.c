/* The real divers_best_friend.dll under Wine, loaded by a stand-in HellForge, as the Overlay Host tests itself
 * (overlay-host/test/host_test.cpp). build.sh wine-test builds this host, the stub Overlay Hosts of
 * tests/wine_overlay_stub.c and the stub loader export of tests/wine_modloader_stub.c, and runs one case per process (the
 * DLL keeps static state).
 *
 * The stand-in HfApi: log writes the line down, on keeps the listeners (HF_EVENT_GAME_LOADED is fired by hand),
 * on_game_thread keeps the callback and returns 1, module_base serves the synthetic 25480438 image of tests/synthetic.c
 * (game.dll and a minimal helldivers2.exe, both with 25480438's stamps, the image carrying the generated witness table,
 * the one the DLL is built with), read and read_code read that image and fail outside it, write refuses (and is counted:
 * the mod must write nothing). The rest of the HfApi is NULL: a mod calling it crashes the case.
 *
 * Cases (the second argument):
 *   no-host        no goose_overlay.dll loaded
 *   host-api3      a stub host older than 0.2.0: its ov_api serves nothing above 3
 *   host-api4      a stub Overlay Host 0.2.x: API 4, no on_game_thread
 *   host-api5      a stub Overlay Host 0.3.x: API 5 with on_game_thread; with a stub hellforge_modloader.dll whose
 *                  hellforge_lua_rewrites covers one witness byte the host changes
 *   no-tick        the API 4 stub, and HellForge refuses the game-thread slot: DBF logs it and stops (no window)
 *   retry          the API 4 stub; a witness byte is changed before the first tick (the features it gates wait), put back,
 *                  and a tick 1.1 s later admits them: admission retries once a second
 *   on-at-once     the API 4 stub; the stand-in `on` delivers HF_EVENT_GAME_LOADED before it returns, as a loader that has
 *                  already seen the game load might: the version line comes first and the window registers once
 *   late-module    the API 4 stub; module_base serves nothing on the first tick: that tick only publishes "game.dll not
 *                  loaded yet" and reads nothing, and admission starts (logging it, once) on the second
 *   second-loaded  the API 4 stub; HF_EVENT_GAME_LOADED comes three times: one window, one tick, one line saying so
 *   null-panel     the API 4 stub, whose register_panel returns NULL: DBF logs it and keeps ticking
 *   on-fails       the API 4 stub, and HellForge refuses the listener (hf->on fails): DBF logs it and registers nothing
 *   masked-log     the API 4 stub and a stub loader that rewrites several witness bytes, two witnesses' worth: the count
 *                  of masked bytes of each is logged once, however often the witness is read again
 * Checks of the first five: init returns 0, logs the version line, registers for HF_EVENT_GAME_LOADED and nothing else.
 * After the event: without a usable host (no-host, host-api3) the "running without a window" line, exactly once even after 3
 * ticks, and the tick on HellForge's on_game_thread; with one, one register_panel call for the Status window (id, title,
 * kind, hotkey 0, 640x520), the tick on the host's on_game_thread when it has one (API 5) and HellForge's otherwise, the
 * window drawing "starting" before the first tick, the menu open after the first, and, after 3 ticks (the menu closed in
 * the game before the last), the last published snapshot as the Status tab draws it: build OK, the three read features OK,
 * in a mission, the menu closed, no reader reason, four rows with the scene's names and codes. The snapshot is read as a
 * player sees it: the stub host calls the window's draw callback into tests/fake_ov.c's recording OvApi, so the DLL needs
 * no export for the test (and the host could not link the snapshot accessors: the DLL's snapshot lives in the DLL's own
 * statics).
 *
 * Usage: wine_host.exe <divers_best_friend.dll> <case> [<goose_overlay.dll> [<hellforge_modloader.dll>]] */
#define WIN32_LEAN_AND_MEAN
#define HF_MOD_LOADER /* this is the loader: hellforge_mod.h does not declare the mod's init here */
#include <windows.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "hellforge_mod.h"
#define DBF_ADDRESSES_DEFINE /* the generated witness table, as the DLL has it: the synthetic image carries its bytes */
#include "addresses_25480438.h"
#include "kind_names_25480438.h"
#include "synthetic.h"
#include "test.h"
#include "wine_overlay_stub.h"

#define VERSION_LINE "Diver's Best Friend R50-hellforge.1 (game 25480438)"
#define NO_HOST_LINE "No Overlay Host 0.2.0 or later: running without a window"
#define NO_TICK_LINE "Diver's Best Friend could not get a game-thread tick"
#define NO_PANEL_LINE "The Overlay Host did not take the Diver's Best Friend window (its log says why)"
#define LISTEN_FAILED_LINE "Diver's Best Friend could not listen for the game loading"
#define REPEATED_LINE "Diver's Best Friend ignored a repeated game-loaded event"
#define ADMISSION_LINE "game.dll found; admission starts"
#define REWRITES_FOUND_LINE "Admission skips the code HellForge rewrites (hellforge_lua_rewrites found)"
#define REWRITES_MISSING_LINE "No hellforge_lua_rewrites in hellforge_modloader.dll: admission compares every witness byte"
#define MASKED_TAIL " bytes rewritten by HellForge" /* every masked-witness line ends like this */
#define STARTING_TEXT "text:Diver's Best Friend is starting..."
#define PANEL_ID "goose.divers-best-friend"
#define PANEL_TITLE "Diver's Best Friend"
#define TICKS 3
#define MENU_OPEN_AT 0x38769u /* the menu-open byte in the stratagem panel (R46 native.lua:214), as tests/synthetic.c */
#define RETRY_WAIT_MS 1100u   /* admission retries what is pending once a second */
#define MAX_LINES 256
#define LINE_SIZE 512
#define MAX_LISTENERS 16
#define MAX_TICKERS 8

struct HfMod { const char* id; }; /* opaque to mods; the loader's own */
static struct HfMod g_mod = { "goose.divers-best-friend" };

/* --- the stand-in HfApi ---------------------------------------------------------------------------------------- */

static char g_lines[MAX_LINES][LINE_SIZE];
static int g_line_count;

static void api_log(HfMod* mod, const char* format, ...)
{
    char line[LINE_SIZE];
    va_list args;
    va_start(args, format);
    vsnprintf(line, sizeof line, format, args);
    va_end(args);
    printf("  [%s] %s\n", mod ? mod->id : "?", line);
    if (g_line_count < MAX_LINES) memcpy(g_lines[g_line_count++], line, sizeof line);
}

static int logged(const char* line)
{
    int n = 0;
    for (int i = 0; i < g_line_count; i++)
        if (strcmp(g_lines[i], line) == 0) n++;
    return n;
}

/* How many logged lines end with `tail`. */
static int logged_ending(const char* tail)
{
    size_t n = strlen(tail);
    int count = 0;
    for (int i = 0; i < g_line_count; i++) {
        size_t length = strlen(g_lines[i]);
        if (length >= n && strcmp(g_lines[i] + length - n, tail) == 0) count++;
    }
    return count;
}

typedef struct Listener {
    HfMod* mod;
    HfEvent event;
    HfEventCallback callback;
    void* user;
} Listener;
static Listener g_listeners[MAX_LISTENERS];
static int g_listener_count;
static int g_on_calls;

static int api_on(HfMod* mod, HfEvent event, HfEventCallback callback, void* user)
{
    g_on_calls++;
    if (g_listener_count >= MAX_LISTENERS) return 1;
    g_listeners[g_listener_count++] = (Listener){ mod, event, callback, user };
    return 0;
}

/* on-at-once: a loader that already saw the game load delivers the event before on returns. What the mod had logged by the
 * time it called on is written down first. */
static int g_version_lines_at_on = -1;
static int api_on_at_once(HfMod* mod, HfEvent event, HfEventCallback callback, void* user)
{
    int result;
    g_version_lines_at_on = logged(VERSION_LINE);
    result = api_on(mod, event, callback, user);
    if (result == 0) callback(mod, event, user);
    return result;
}

/* on-fails: HellForge takes no listener. */
static int api_on_fails(HfMod* mod, HfEvent event, HfEventCallback callback, void* user)
{
    g_on_calls++;
    return 1;
}

static void fire(HfEvent event)
{
    for (int i = 0; i < g_listener_count; i++)
        if (g_listeners[i].event == event) g_listeners[i].callback(g_listeners[i].mod, event, g_listeners[i].user);
}

typedef struct Ticker {
    HfMod* mod;
    HfTickCallback callback;
    void* user;
} Ticker;
static Ticker g_tickers[MAX_TICKERS];
static int g_ticker_count;

static int api_on_game_thread(HfMod* mod, HfTickCallback callback, void* user)
{
    if (callback == NULL || g_ticker_count >= MAX_TICKERS) return 0;
    g_tickers[g_ticker_count++] = (Ticker){ mod, callback, user };
    return 1;
}

/* no-tick: as HellForge's when the game's update could not be hooked. */
static int api_refuse_game_thread(HfMod* mod, HfTickCallback callback, void* user) { return 0; }

static void api_tick(void)
{
    for (int i = 0; i < g_ticker_count; i++) g_tickers[i].callback(g_tickers[i].mod, 1.0f / 60.0f, g_tickers[i].user);
}

static const char* api_build_id(void) { return "25480438"; }
static const char* api_mod_id(HfMod* mod) { return mod->id; }
static const char* api_mod_folder(HfMod* mod) { return "C:\\mods\\divers-best-friend"; }

/* The ticks the host has run, and what the mod asked of the game around them. module_base serves nothing until tick number
 * g_module_from_tick has started (late-module); 0 serves it always. */
static int g_tick_no;
static int g_module_from_tick;
static int g_module_base_calls;
static int g_read_calls;

static uintptr_t api_module_base(const char* module, size_t* size)
{
    g_module_base_calls++;
    if (g_tick_no < g_module_from_tick) return 0;
    return syn_adm_port()->module_base(module, size);
}

static int api_read(uintptr_t address, void* out, size_t size)
{
    g_read_calls++;
    return syn_read(address, out, size);
}

/* --- helpers --------------------------------------------------------------------------------------------------- */

static void* need(HMODULE module, const char* name)
{
    void* p = module ? (void*)GetProcAddress(module, name) : NULL;
    if (p == NULL) printf("  (%s is not exported)\n", name);
    return p;
}

static DWORD WINAPI watchdog(void* unused)
{
    Sleep(60000);
    puts("FAIL the case hung for 60 s");
    fflush(stdout);
    TerminateProcess(GetCurrentProcess(), 3);
    return 0;
}

/* "^ > v <" for a code, as the Status tab writes it. */
static void arrows(char* out, size_t size, const uint8_t* code, int n)
{
    static const char ARROWS[5] = { '?', '^', '>', 'v', '<' };
    size_t at = 0;
    for (int i = 0; i < n && at + 3 < size; i++) {
        if (i > 0) out[at++] = ' ';
        out[at++] = code[i] >= 1 && code[i] <= 4 ? ARROWS[code[i]] : '?';
    }
    out[at] = '\0';
}

static const DbfWitness* witness(const char* name)
{
    for (int i = 0; i < dbf_witness_count; i++)
        if (strcmp(dbf_witnesses[i].name, name) == 0) return &dbf_witnesses[i];
    return NULL;
}

/* The stub host's exports. */
static StubCountFn s_requests, s_panel_count, s_register_calls, s_game_thread_count, s_line_count, s_open, s_misuse;
static StubPanelFn s_panel;
static StubTickFn s_tick;
static StubDrawFn s_draw;
static StubLineFn s_line;
static StubTextFn s_count_prefix;
static StubSwitchFn s_refuse_panels;

static bool load_stub(HMODULE stub)
{
    s_requests = (StubCountFn)need(stub, "stub_requests");
    s_panel_count = (StubCountFn)need(stub, "stub_panel_count");
    s_register_calls = (StubCountFn)need(stub, "stub_register_calls");
    s_refuse_panels = (StubSwitchFn)need(stub, "stub_refuse_panels");
    s_panel = (StubPanelFn)need(stub, "stub_panel");
    s_game_thread_count = (StubCountFn)need(stub, "stub_game_thread_count");
    s_tick = (StubTickFn)need(stub, "stub_tick");
    s_draw = (StubDrawFn)need(stub, "stub_draw");
    s_line_count = (StubCountFn)need(stub, "stub_line_count");
    s_line = (StubLineFn)need(stub, "stub_line");
    s_count_prefix = (StubTextFn)need(stub, "stub_count_prefix");
    s_open = (StubCountFn)need(stub, "stub_open");
    s_misuse = (StubCountFn)need(stub, "stub_misuse");
    return s_requests && s_panel_count && s_register_calls && s_refuse_panels && s_panel && s_game_thread_count && s_tick
        && s_draw && s_line_count && s_line && s_count_prefix && s_open && s_misuse;
}

/* One game update: the stub host's slot when the case has a host that runs one (API 5), else HellForge's. */
static bool g_ticks_via_host;
static void do_tick(void)
{
    g_tick_no++;
    if (g_ticks_via_host) s_tick(1.0f / 60.0f);
    else api_tick();
}

static int find_line(const char* line)
{
    for (int i = 0; i < s_line_count(); i++)
        if (strcmp(s_line(i), line) == 0) return i;
    return -1;
}

static void print_drawing(void)
{
    for (int i = 0; i < s_line_count(); i++) printf("    | %s\n", s_line(i));
}

/* The window draws its panel (printing what it drew); false when it has none. */
static bool draw_window(void)
{
    bool drawn = s_draw(0) != 0;
    print_drawing();
    return drawn;
}

/* The Status tab's stratagem table: per row "row", "cell", "text:<name>", "cell", "text:<code>", in the scene's order. */
static bool rows_are(const SynScene* scene, int count)
{
    int at = find_line("headers");
    if (at < 0) return false;
    at++;
    for (int i = 0; i < count; i++, at += 5) {
        const SynStratagem* st = &scene->stratagems[i];
        char name[LINE_SIZE], code[LINE_SIZE], text[64];
        arrows(text, sizeof text, st->code, st->code_len);
        snprintf(name, sizeof name, "text:%s", dbf_kind_names[st->kind] ? dbf_kind_names[st->kind] : "?");
        snprintf(code, sizeof code, "text:%s", text);
        if (at + 4 >= s_line_count() || strcmp(s_line(at), "row") || strcmp(s_line(at + 1), "cell")
            || strcmp(s_line(at + 2), name) || strcmp(s_line(at + 3), "cell") || strcmp(s_line(at + 4), code)) {
            printf("  row %d: expected \"%s\" / \"%s\"\n", i, name, code);
            return false;
        }
    }
    return at < s_line_count() && strcmp(s_line(at), "end:table") == 0;
}

/* --- the process: one case ------------------------------------------------------------------------------------- */

typedef enum {
    C_NO_HOST, C_API3, C_API4, C_API5, C_NO_TICK, C_RETRY, C_ON_AT_ONCE, C_LATE_MODULE, C_SECOND_LOADED, C_NULL_PANEL,
    C_ON_FAILS, C_MASKED_LOG
} CaseId;

typedef struct CaseInfo {
    const char* name;
    const char* title;
    bool stub;   /* needs the stub Overlay Host (argument 3) */
    bool loader; /* needs the stub loader (argument 4) */
} CaseInfo;

static const CaseInfo CASES[] = {
    [C_NO_HOST] = { "no-host", "no Overlay Host", false, false },
    [C_API3] = { "host-api3", "an Overlay Host older than 0.2.0 (API 3)", true, false },
    [C_API4] = { "host-api4", "Overlay Host 0.2.x (API 4, no shared game-thread slot)", true, false },
    [C_API5] = { "host-api5", "Overlay Host 0.3.x (API 5) and HellForge's rewrite list", true, true },
    [C_NO_TICK] = { "no-tick", "Overlay Host 0.2.x, and HellForge gives no game-thread slot", true, false },
    [C_RETRY] = { "retry", "a changed witness byte is put back: admission retries after a second", true, false },
    [C_ON_AT_ONCE] = { "on-at-once", "HellForge delivers the game-loaded event before on returns", true, false },
    [C_LATE_MODULE] = { "late-module", "game.dll is not loaded on the first tick", true, false },
    [C_SECOND_LOADED] = { "second-loaded", "the game-loaded event comes three times", true, false },
    [C_NULL_PANEL] = { "null-panel", "the Overlay Host takes no window", true, false },
    [C_ON_FAILS] = { "on-fails", "HellForge refuses the game-loaded listener", true, false },
    [C_MASKED_LOG] = { "masked-log", "HellForge rewrites bytes of two witnesses", true, true },
};

static CaseId g_case;
static SynScene g_scene;
static HfApi g_api;
static HMODULE g_stub, g_loader;
static int (*g_init)(const HfApi*, HfMod*);

/* init, checked. */
static void run_init(void)
{
    CHECK(g_init(&g_api, &g_mod) == 0, "init returns 0");
}

/* The window shows four rows with the scene's names and codes, admitted features and a verified build. */
static void check_full_window(const char* after)
{
    char text[LINE_SIZE];
    snprintf(text, sizeof text, "%s: the window draws", after);
    CHECK(draw_window(), text);
    snprintf(text, sizeof text, "%s: build OK, the three read features OK", after);
    CHECK(find_line("text:Game build 25480438: OK") >= 0 && find_line("text:Selection state: OK") >= 0
              && find_line("text:Stratagems: OK") >= 0 && find_line("text:HUD reads: OK") >= 0,
          text);
    snprintf(text, sizeof text, "%s: in a mission, everything read, four rows with the scene's names and codes", after);
    CHECK(find_line("text:In a mission: yes") >= 0 && s_count_prefix("text:Reader:") == 0 && s_count_prefix("row") == 4
              && rows_are(&g_scene, 4),
          text);
    CHECK(s_open() == 0 && s_misuse() == 0, "every begin has its end");
}

/* --- the first five cases -------------------------------------------------------------------------------------- */

static void run_standard(void)
{
    const bool api4 = g_case == C_API4, api5 = g_case == C_API5, no_tick = g_case == C_NO_TICK, window = api4 || api5;
    const DbfWitness* rewritten = witness("hud_root"); /* a STATE and HUD_READ witness */
    uint32_t rewritten_rva = 0;
    void (*set_rewritten)(uint32_t) = NULL;
    int (*rewrite_calls)(void) = NULL;

    CHECK(rewritten != NULL, "the generated table has the hud_root witness");
    if (rewritten) rewritten_rva = rewritten->rva + 3u;
    if (api5) {
        uint8_t byte = 0;
        set_rewritten = (void (*)(uint32_t))need(g_loader, "stub_set_rewritten");
        rewrite_calls = (int (*)(void))need(g_loader, "stub_rewrite_calls");
        if (!set_rewritten || !rewrite_calls) return;
        set_rewritten(rewritten_rva);
        /* One byte of the witness differs from the table, and the loader says HellForge rewrites it. */
        CHECK(syn_read(SYN_GAME_BASE + rewritten_rva, &byte, 1) == 0
                  && syn_poke_u8(SYN_GAME_BASE + rewritten_rva, (uint8_t)(byte ^ 0xffu)),
              "a byte of the hud_root witness is changed, as HellForge rewrites it");
    }

    run_init();
    CHECK(logged(VERSION_LINE) == 1, "init logs \"" VERSION_LINE "\"");
    CHECK(g_listener_count == 1 && g_listeners[0].event == HF_EVENT_GAME_LOADED && g_listeners[0].mod == &g_mod,
          "init registers for HF_EVENT_GAME_LOADED only");
    CHECK(g_ticker_count == 0, "init takes no game-thread slot");
    if (g_stub)
        CHECK(s_requests() == 0 && s_panel_count() == 0 && s_game_thread_count() == 0,
              "init does not touch the Overlay Host");

    fire(HF_EVENT_GAME_LOADED);
    if (no_tick) {
        CHECK(logged(NO_TICK_LINE) == 1, "the \"" NO_TICK_LINE "\" line");
        CHECK(logged(NO_HOST_LINE) == 0 && s_requests() > 0, "the host was found (API 4)");
        CHECK(s_panel_count() == 0 && s_game_thread_count() == 0 && g_ticker_count == 0, "and DBF stops: no window");
        return;
    }
    CHECK(logged(NO_TICK_LINE) == 0, "the tick is registered");
    if (window) {
        const StubPanel* p = s_panel(0);
        CHECK(logged(NO_HOST_LINE) == 0, "with an Overlay Host 0.2.0 or later, no \"running without a window\" line");
        CHECK(s_panel_count() == 1 && p != NULL && strcmp(p->id, PANEL_ID) == 0, "one register_panel call, id " PANEL_ID);
        CHECK(p && p->size == sizeof(OvPanelDef) && strcmp(p->title, PANEL_TITLE) == 0 && p->kind == OV_PANEL_WINDOW
                  && p->hotkey == 0 && p->width == 640.0f && p->height == 520.0f && p->draw != NULL,
              "the panel is the window \"" PANEL_TITLE "\", no hotkey, 640x520, with a draw callback");
        if (api5)
            CHECK(s_game_thread_count() == 1 && g_ticker_count == 0,
                  "the tick goes through the Overlay Host's on_game_thread (API 5), not HellForge's");
        else
            CHECK(s_game_thread_count() == 0 && g_ticker_count == 1 && g_tickers[0].mod == &g_mod,
                  "an API 4 host has no shared slot: the tick goes through HellForge's on_game_thread");
        CHECK(s_draw(0) && s_line_count() == 1 && strcmp(s_line(0), STARTING_TEXT) == 0,
              "before the first tick the window says \"Diver's Best Friend is starting...\"");
    } else {
        CHECK(logged(NO_HOST_LINE) == 1, "the \"" NO_HOST_LINE "\" line");
        CHECK(g_ticker_count == 1 && g_tickers[0].mod == &g_mod, "the tick goes through HellForge's on_game_thread");
        if (g_stub)
            CHECK(s_requests() > 0 && s_panel_count() == 0 && s_game_thread_count() == 0,
                  "DBF asked the old host for its API, and registered nothing with it");
    }

    /* A tick, a draw, a tick, then the menu closes in the game before the last tick: the window must draw the last tick's
     * read. Its publish goes to the buffer the draw read, so a draw that kept its snapshot (no snap_release) or a tick
     * that did not publish leaves the window showing the menu open. */
    for (int i = 0; i < TICKS; i++) {
        if (i == 1 && window)
            CHECK(s_draw(0) && find_line("text:Stratagem menu: open") >= 0 && s_count_prefix("row") == 4,
                  "after the first tick the window shows the menu open and four rows");
        if (i == TICKS - 1)
            CHECK(syn_poke_u8(syn_panel() + MENU_OPEN_AT, 0), "the menu closes in the game before the last tick");
        do_tick();
    }
    CHECK(logged(VERSION_LINE) == 1, "after 3 ticks the version line is still logged once");
    CHECK(logged(NO_HOST_LINE) == (window ? 0 : 1),
          window ? "after 3 ticks still no \"running without a window\" line"
                 : "after 3 ticks the \"running without a window\" line is still logged exactly once");
    CHECK(logged(ADMISSION_LINE) == 1, "the first tick found game.dll and logged that admission starts, once");
    if (api5) {
        const DbfWitness* w = witness("hud_root");
        char masked[LINE_SIZE];
        CHECK(logged(REWRITES_FOUND_LINE) == 1 && logged(REWRITES_MISSING_LINE) == 0,
              "the tick found hellforge_lua_rewrites and logged it once");
        CHECK(rewrite_calls() > 0, "admission asked hellforge_lua_rewrites about the changed byte");
        snprintf(masked, sizeof masked, "witness hud_root: 1 of %u" MASKED_TAIL, w ? (unsigned)w->size : 0u);
        CHECK(logged(masked) == 1 && logged_ending(MASKED_TAIL) == 1,
              "and logged that one byte of hud_root is rewritten by HellForge, once and for no other witness");
    } else {
        CHECK(logged(REWRITES_MISSING_LINE) == 1 && logged(REWRITES_FOUND_LINE) == 0,
              "the tick found no hellforge_lua_rewrites and logged it once");
        CHECK(logged_ending(MASKED_TAIL) == 0, "and logged no masked witness");
    }
    CHECK(syn_write_count() == 0, "the mod wrote nothing to the game");

    if (window) {
        char host_line[64];
        snprintf(host_line, sizeof host_line, "text:Overlay Host API %d", api5 ? 5 : 4);
        CHECK(s_draw(0), "the window draws after 3 ticks");
        print_drawing();
        CHECK(find_line("text:Game build 25480438: OK") >= 0, "the last snapshot has build_ok");
        CHECK(find_line("text:Selection state: OK") >= 0 && find_line("text:Stratagems: OK") >= 0
                  && find_line("text:HUD reads: OK") >= 0,
              api5 ? "Selection state, Stratagems and HUD reads are admitted (the rewritten byte is skipped)"
                   : "Selection state, Stratagems and HUD reads are admitted");
        CHECK(find_line(host_line) >= 0, "the snapshot carries the host's API version");
        CHECK(find_line("text:In a mission: yes") >= 0 && find_line("text:Stratagem menu: closed") >= 0
                  && s_count_prefix("text:Reader:") == 0,
              "the last tick's read: in a mission, the menu closed, everything read");
        CHECK(s_count_prefix("row") == 4 && rows_are(&g_scene, 4), "four rows, with the scene's names and codes in list order");
        CHECK(s_open() == 0 && s_misuse() == 0, "every begin has its end");
    }
}

/* --- retry ----------------------------------------------------------------------------------------------------- */

/* A byte of hud_root (a STATE and HUD_READ witness) is wrong when admission first looks: the features wait, and the Status
 * tab says why. The game puts it right; a second later admission looks again and admits them. */
static void run_retry(void)
{
    const DbfWitness* w = witness("hud_root");
    uintptr_t at = w ? SYN_GAME_BASE + w->rva + 3u : 0;
    uint8_t byte = 0;
    const char* reason = "witness hud_root differs (retrying)";
    char selection[LINE_SIZE], hud[LINE_SIZE];

    CHECK(w != NULL && syn_read(at, &byte, 1) == 0 && syn_poke_u8(at, (uint8_t)(byte ^ 0xffu)),
          "a byte of the hud_root witness is wrong before the first tick");
    run_init();
    fire(HF_EVENT_GAME_LOADED);
    CHECK(s_panel_count() == 1 && g_ticker_count == 1, "the window and the tick are registered");

    do_tick();
    CHECK(draw_window(), "the window draws after the first tick");
    snprintf(selection, sizeof selection, "text:Selection state: Waiting (%s)", reason);
    snprintf(hud, sizeof hud, "text:HUD reads: Waiting (%s)", reason);
    CHECK(find_line(selection) >= 0 && find_line(hud) >= 0, "Selection state and HUD reads wait, with the witness named");
    CHECK(find_line("text:Game build 25480438: OK") >= 0 && find_line("text:Stratagems: OK") >= 0,
          "the build is verified and Stratagems, which do not rest on hud_root, are admitted");
    CHECK(s_count_prefix("row") == 0 && find_line("text:In a mission: yes") < 0, "and nothing is read from the game meanwhile");
    CHECK(logged(ADMISSION_LINE) == 1, "admission started once");

    CHECK(syn_poke_u8(at, byte), "the byte is put right");
    Sleep(RETRY_WAIT_MS);
    do_tick();
    check_full_window("a second after the byte was put right");
    CHECK(logged(ADMISSION_LINE) == 1 && logged(VERSION_LINE) == 1, "admission was not started again, only retried");
    CHECK(syn_write_count() == 0, "the mod wrote nothing to the game");
}

/* --- on-at-once ------------------------------------------------------------------------------------------------ */

static void run_on_at_once(void)
{
    const StubPanel* p;
    run_init();
    CHECK(g_on_calls == 1 && g_listener_count == 1 && g_listeners[0].event == HF_EVENT_GAME_LOADED
              && g_listeners[0].mod == &g_mod,
          "init registers for HF_EVENT_GAME_LOADED only, once");
    CHECK(g_version_lines_at_on == 1, "the version line was already logged when init called on");
    CHECK(g_line_count > 0 && strcmp(g_lines[0], VERSION_LINE) == 0 && logged(VERSION_LINE) == 1,
          "the version line is the first line logged, and logged once");
    p = s_panel(0);
    CHECK(s_register_calls() == 1 && s_panel_count() == 1 && p != NULL && strcmp(p->id, PANEL_ID) == 0,
          "the event delivered inside on registered the window, once");
    CHECK(g_ticker_count == 1 && g_tickers[0].mod == &g_mod && s_game_thread_count() == 0,
          "and the tick, through HellForge's on_game_thread (the API 4 host has no slot)");
    CHECK(logged(NO_HOST_LINE) == 0 && logged(NO_TICK_LINE) == 0 && logged(NO_PANEL_LINE) == 0, "with nothing refused");
    CHECK(s_draw(0) && s_line_count() == 1 && strcmp(s_line(0), STARTING_TEXT) == 0,
          "before the first tick the window says \"Diver's Best Friend is starting...\"");

    for (int i = 0; i < TICKS; i++) do_tick();
    CHECK(logged(VERSION_LINE) == 1 && s_panel_count() == 1 && s_register_calls() == 1 && g_ticker_count == 1,
          "after 3 ticks still one version line, one window and one tick");
    CHECK(logged(ADMISSION_LINE) == 1, "admission started once");
    check_full_window("after 3 ticks");
    CHECK(syn_write_count() == 0, "the mod wrote nothing to the game");
}

/* --- late-module ----------------------------------------------------------------------------------------------- */

static void run_late_module(void)
{
    g_module_from_tick = 2; /* nothing on the first tick, game.dll and the exe from the second */
    run_init();
    fire(HF_EVENT_GAME_LOADED);

    do_tick();
    CHECK(g_module_base_calls > 0, "the first tick asked for game.dll");
    CHECK(logged(ADMISSION_LINE) == 0 && logged(REWRITES_FOUND_LINE) == 0 && logged(REWRITES_MISSING_LINE) == 0,
          "game.dll is not there: admission has not started, and says nothing");
    CHECK(g_read_calls == 0 && syn_write_count() == 0, "and the tick read nothing from the game");
    CHECK(draw_window(), "the window draws after the first tick");
    CHECK(find_line("text:Game build: game.dll not loaded yet") >= 0, "the snapshot's build reason says game.dll is not loaded yet");
    CHECK(find_line("text:Selection state: Waiting (game.dll not loaded yet)") >= 0
              && find_line("text:Stratagems: Waiting (game.dll not loaded yet)") >= 0
              && find_line("text:HUD reads: Waiting (game.dll not loaded yet)") >= 0,
          "the read features wait for it");
    CHECK(s_count_prefix("row") == 0 && find_line("text:In a mission: no") >= 0 && s_count_prefix("text:Reader:") == 0,
          "no rows, no mission");

    do_tick();
    CHECK(logged(ADMISSION_LINE) == 1, "on the second tick game.dll is found and admission starts, with one line saying so");
    CHECK(logged(REWRITES_MISSING_LINE) == 1, "and the rewrite list is looked up then (none in this case), once");
    CHECK(g_read_calls > 0, "and the game is read");
    check_full_window("on the second tick");

    do_tick();
    CHECK(logged(ADMISSION_LINE) == 1 && logged(REWRITES_MISSING_LINE) == 1, "a third tick starts nothing again");
    check_full_window("after the third tick");
    CHECK(syn_write_count() == 0, "the mod wrote nothing to the game");
}

/* --- second-loaded --------------------------------------------------------------------------------------------- */

static void run_second_loaded(void)
{
    int requests;
    run_init();
    fire(HF_EVENT_GAME_LOADED);
    CHECK(s_panel_count() == 1 && g_ticker_count == 1 && logged(REPEATED_LINE) == 0,
          "the first event registers the window and the tick, and logs no repeat");
    requests = s_requests();
    fire(HF_EVENT_GAME_LOADED);
    CHECK(logged(REPEATED_LINE) == 1, "the second event is logged: \"" REPEATED_LINE "\"");
    fire(HF_EVENT_GAME_LOADED);
    CHECK(logged(REPEATED_LINE) == 1, "a third one is not logged again");
    CHECK(s_register_calls() == 1 && s_panel_count() == 1 && g_ticker_count == 1 && s_game_thread_count() == 0,
          "and neither registered another window or tick");
    CHECK(s_requests() == requests, "nor asked the Overlay Host for its API again");
    CHECK(logged(NO_HOST_LINE) == 0 && logged(NO_TICK_LINE) == 0 && logged(NO_PANEL_LINE) == 0, "nothing was refused");

    for (int i = 0; i < TICKS; i++) do_tick();
    CHECK(logged(REPEATED_LINE) == 1 && logged(VERSION_LINE) == 1 && logged(ADMISSION_LINE) == 1,
          "after 3 ticks: one repeat line, one version line, admission started once");
    check_full_window("after 3 ticks");
    CHECK(syn_write_count() == 0, "the mod wrote nothing to the game");
}

/* --- null-panel ------------------------------------------------------------------------------------------------ */

static void run_null_panel(void)
{
    s_refuse_panels(1);
    run_init();
    fire(HF_EVENT_GAME_LOADED);
    CHECK(s_register_calls() == 1 && s_panel_count() == 0, "DBF asked the Overlay Host for its window once, and got none");
    CHECK(logged(NO_PANEL_LINE) == 1, "and logged \"" NO_PANEL_LINE "\" once");
    CHECK(logged(NO_HOST_LINE) == 0 && logged(NO_TICK_LINE) == 0, "the host was found and the tick registered");
    CHECK(g_ticker_count == 1 && g_tickers[0].mod == &g_mod, "the tick goes through HellForge's on_game_thread");
    CHECK(s_draw(0) == 0, "there is no window to draw");

    for (int i = 0; i < TICKS; i++) do_tick();
    CHECK(logged(NO_PANEL_LINE) == 1 && s_register_calls() == 1, "the ticks ask nothing more of the host");
    CHECK(logged(ADMISSION_LINE) == 1 && g_read_calls > 0, "the ticks still run: admission started and the game was read");
    CHECK(syn_write_count() == 0, "the mod wrote nothing to the game");
}

/* --- on-fails -------------------------------------------------------------------------------------------------- */

static void run_on_fails(void)
{
    run_init();
    CHECK(g_on_calls == 1 && g_listener_count == 0, "HellForge was asked for a listener once and took none");
    CHECK(logged(LISTEN_FAILED_LINE) == 1, "DBF logged \"" LISTEN_FAILED_LINE "\" once");
    CHECK(g_line_count == 2 && strcmp(g_lines[0], VERSION_LINE) == 0 && strcmp(g_lines[1], LISTEN_FAILED_LINE) == 0,
          "its log is the version line, then that line, and nothing else");
    fire(HF_EVENT_GAME_LOADED);
    CHECK(s_requests() == 0 && s_panel_count() == 0 && s_register_calls() == 0 && s_game_thread_count() == 0
              && g_ticker_count == 0,
          "nothing is registered with the Overlay Host or HellForge");
    CHECK(g_read_calls == 0 && g_module_base_calls == 0 && syn_write_count() == 0, "and the game is left alone");
}

/* --- masked-log ------------------------------------------------------------------------------------------------ */

/* HellForge rewrites three bytes of hud_root and one of owner_map_value. One hud_root byte of the three differs, and so
 * does another byte, which nothing rewrites, so the witness stays pending and is read again; the owner_map_value byte
 * matches. Each witness' count (all its rewritten bytes, matching or not) is logged once, however often it is read. */
static void run_masked_log(void)
{
    const DbfWitness* a = witness("hud_root");
    const DbfWitness* b = witness("owner_map_value");
    void (*set_rewritten)(uint32_t) = (void (*)(uint32_t))need(g_loader, "stub_set_rewritten");
    void (*add_rewritten)(uint32_t) = (void (*)(uint32_t))need(g_loader, "stub_add_rewritten");
    int (*rewrite_calls)(void) = (int (*)(void))need(g_loader, "stub_rewrite_calls");
    uintptr_t masked_change, plain_change;
    uint8_t byte_masked = 0, byte_plain = 0;
    char a_line[LINE_SIZE], b_line[LINE_SIZE], selection[LINE_SIZE];

    CHECK(a != NULL && b != NULL && b->size > 8 && set_rewritten && add_rewritten && rewrite_calls,
          "the table has hud_root and owner_map_value, and the stub loader takes several rewritten bytes");
    if (!a || !b || !set_rewritten || !add_rewritten || !rewrite_calls) return;
    snprintf(a_line, sizeof a_line, "witness hud_root: 3 of %u" MASKED_TAIL, (unsigned)a->size);
    snprintf(b_line, sizeof b_line, "witness owner_map_value: 1 of %u" MASKED_TAIL, (unsigned)b->size);
    snprintf(selection, sizeof selection, "text:Selection state: Waiting (witness hud_root differs (retrying))");
    set_rewritten(a->rva + 3u);
    add_rewritten(a->rva + 4u);
    add_rewritten(a->rva + 5u);
    add_rewritten(b->rva + 7u);
    masked_change = SYN_GAME_BASE + a->rva + 3u; /* rewritten, and different */
    plain_change = SYN_GAME_BASE + a->rva + 10u; /* different, and nothing rewrites it */
    CHECK(syn_read(masked_change, &byte_masked, 1) == 0 && syn_poke_u8(masked_change, (uint8_t)(byte_masked ^ 0xffu))
              && syn_read(plain_change, &byte_plain, 1) == 0 && syn_poke_u8(plain_change, (uint8_t)(byte_plain ^ 0xffu)),
          "hud_root has a rewritten byte and an unrewritten byte that differ from the table");

    run_init();
    fire(HF_EVENT_GAME_LOADED);
    do_tick();
    CHECK(rewrite_calls() > 0, "admission asked the loader about witness bytes");
    CHECK(logged(a_line) == 1, "hud_root: its three rewritten bytes are logged, once");
    CHECK(logged(b_line) == 1, "owner_map_value: its one rewritten byte, which matched, is logged, once");
    CHECK(logged_ending(MASKED_TAIL) == 2, "and no other witness is logged");
    CHECK(draw_window() && find_line(selection) >= 0, "hud_root differs where nothing rewrites it: Selection state waits");

    Sleep(RETRY_WAIT_MS);
    do_tick();
    CHECK(draw_window() && find_line(selection) >= 0, "a second later hud_root still differs");
    CHECK(logged(a_line) == 1 && logged(b_line) == 1 && logged_ending(MASKED_TAIL) == 2,
          "read again, it logs nothing more");

    CHECK(syn_poke_u8(plain_change, byte_plain), "the unrewritten byte is put right (the rewritten one stays changed)");
    Sleep(RETRY_WAIT_MS);
    do_tick();
    check_full_window("a second after the unrewritten byte was put right");
    CHECK(logged(a_line) == 1 && logged(b_line) == 1 && logged_ending(MASKED_TAIL) == 2,
          "admitted, the counts were logged once each");
    CHECK(syn_write_count() == 0, "the mod wrote nothing to the game");
}

/* --- main ------------------------------------------------------------------------------------------------------ */

int main(int argc, char** argv)
{
    const char* name;
    HMODULE dll;
    bool known = false;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 3) {
        puts("usage: wine_host.exe <divers_best_friend.dll> <case> [<goose_overlay.dll> [<hellforge_modloader.dll>]]\n"
             "cases: no-host host-api3 host-api4 host-api5 no-tick retry on-at-once late-module second-loaded null-panel"
             " on-fails masked-log");
        return 2;
    }
    name = argv[2];
    for (size_t i = 0; i < sizeof CASES / sizeof CASES[0]; i++)
        if (strcmp(name, CASES[i].name) == 0) {
            g_case = (CaseId)i;
            known = true;
        }
    if (!known || (CASES[g_case].stub && argc < 4) || (CASES[g_case].loader && argc < 5)) {
        printf("FAIL unknown case \"%s\" or a missing stub\n", name);
        return 2;
    }
    printf("== %s\n", CASES[g_case].title);
    CreateThread(NULL, 0, watchdog, NULL, 0, NULL);

    syn_default(&g_scene);
    CHECK(syn_build(&g_scene), "the synthetic 25480438 image builds, with the generated witness table");

    g_api.version = HF_MOD_SDK_VERSION;
    g_api.size = sizeof g_api;
    g_api.log = api_log;
    g_api.build_id = api_build_id;
    g_api.mod_id = api_mod_id;
    g_api.mod_folder = api_mod_folder;
    g_api.on = g_case == C_ON_AT_ONCE ? api_on_at_once : g_case == C_ON_FAILS ? api_on_fails : api_on;
    g_api.module_base = api_module_base;
    g_api.read = api_read;
    g_api.write = syn_write;
    g_api.on_game_thread = g_case == C_NO_TICK ? api_refuse_game_thread : api_on_game_thread;
    g_api.read_code = api_read;
    g_ticks_via_host = g_case == C_API5;

    /* The stubs first, so DBF finds them by name as it finds the real ones (GetModuleHandleA). */
    if (CASES[g_case].stub) {
        bool exports;
        g_stub = LoadLibraryA(argv[3]);
        CHECK(g_stub != NULL && GetModuleHandleA("goose_overlay.dll") == g_stub,
              "the stub Overlay Host loads as goose_overlay.dll");
        exports = load_stub(g_stub);
        CHECK(exports, "the stub exports what the host reads");
        if (!g_stub || !exports) return 1;
    } else {
        CHECK(GetModuleHandleA("goose_overlay.dll") == NULL, "no goose_overlay.dll is loaded");
    }
    if (CASES[g_case].loader) {
        g_loader = LoadLibraryA(argv[4]);
        CHECK(g_loader != NULL && GetModuleHandleA("hellforge_modloader.dll") == g_loader,
              "the stub loader loads as hellforge_modloader.dll");
        if (!g_loader) return 1;
    } else {
        CHECK(GetModuleHandleA("hellforge_modloader.dll") == NULL, "no hellforge_modloader.dll is loaded");
    }

    dll = LoadLibraryA(argv[1]);
    g_init = dll ? (int (*)(const HfApi*, HfMod*))need(dll, "hellforge_mod_init") : NULL;
    CHECK(dll != NULL && g_init != NULL, "divers_best_friend.dll loads and exports hellforge_mod_init");
    if (!g_init) return 1;

    switch (g_case) {
    case C_RETRY: run_retry(); break;
    case C_ON_AT_ONCE: run_on_at_once(); break;
    case C_LATE_MODULE: run_late_module(); break;
    case C_SECOND_LOADED: run_second_loaded(); break;
    case C_NULL_PANEL: run_null_panel(); break;
    case C_ON_FAILS: run_on_fails(); break;
    case C_MASKED_LOG: run_masked_log(); break;
    default: run_standard(); break;
    }

    printf("== %s: %d failure(s)\n", name, test_failures());
    fflush(stdout);
    TEST_MAIN_END
}
