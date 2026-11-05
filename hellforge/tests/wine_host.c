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
 *   no-host    no goose_overlay.dll loaded
 *   host-api3  a stub host older than 0.2.0: its ov_api serves nothing above 3
 *   host-api4  a stub Overlay Host 0.2.x: API 4, no on_game_thread
 *   host-api5  a stub Overlay Host 0.3.x: API 5 with on_game_thread; with a stub hellforge_modloader.dll whose
 *              hellforge_lua_rewrites covers one witness byte the host changes
 *   no-tick    the API 4 stub, and HellForge refuses the game-thread slot: DBF logs it and stops (no window)
 * Checks: init returns 0, logs the version line, registers for HF_EVENT_GAME_LOADED and nothing else. After the event:
 * without a usable host (no-host, host-api3) the "running without a window" line, exactly once even after 3 ticks, and the
 * tick on HellForge's on_game_thread; with one, one register_panel call for the Status window (id, title, kind, hotkey 0,
 * 640x520), the tick on the host's on_game_thread when it has one (API 5) and HellForge's otherwise, the window drawing
 * "starting" before the first tick, the menu open after the first, and, after 3 ticks (the menu closed in the game before
 * the last), the last published snapshot as the Status tab draws it: build OK, the three read features OK, in a mission,
 * the menu closed, no reader reason, four rows with the scene's names and codes. The snapshot is read as a player sees
 * it: the stub host calls the window's draw callback into tests/fake_ov.c's recording OvApi, so the DLL needs no export
 * for the test (and the host could not link the snapshot accessors: the DLL's snapshot lives in the DLL's own statics).
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
#define REWRITES_FOUND_LINE "Admission skips the code HellForge rewrites (hellforge_lua_rewrites found)"
#define REWRITES_MISSING_LINE "No hellforge_lua_rewrites in hellforge_modloader.dll: admission compares every witness byte"
#define STARTING_TEXT "text:Diver's Best Friend is starting..."
#define PANEL_ID "goose.divers-best-friend"
#define PANEL_TITLE "Diver's Best Friend"
#define TICKS 3
#define MENU_OPEN_AT 0x38769u /* the menu-open byte in the stratagem panel (R46 native.lua:214), as tests/synthetic.c */
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

typedef struct Listener {
    HfMod* mod;
    HfEvent event;
    HfEventCallback callback;
    void* user;
} Listener;
static Listener g_listeners[MAX_LISTENERS];
static int g_listener_count;

static int api_on(HfMod* mod, HfEvent event, HfEventCallback callback, void* user)
{
    if (g_listener_count >= MAX_LISTENERS) return 1;
    g_listeners[g_listener_count++] = (Listener){ mod, event, callback, user };
    return 0;
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
static uintptr_t api_module_base(const char* module, size_t* size) { return syn_adm_port()->module_base(module, size); }

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
static StubCountFn s_requests, s_panel_count, s_game_thread_count, s_line_count, s_open, s_misuse;
static StubPanelFn s_panel;
static StubTickFn s_tick;
static StubDrawFn s_draw;
static StubLineFn s_line;
static StubTextFn s_count_prefix;

static bool load_stub(HMODULE stub)
{
    s_requests = (StubCountFn)need(stub, "stub_requests");
    s_panel_count = (StubCountFn)need(stub, "stub_panel_count");
    s_panel = (StubPanelFn)need(stub, "stub_panel");
    s_game_thread_count = (StubCountFn)need(stub, "stub_game_thread_count");
    s_tick = (StubTickFn)need(stub, "stub_tick");
    s_draw = (StubDrawFn)need(stub, "stub_draw");
    s_line_count = (StubCountFn)need(stub, "stub_line_count");
    s_line = (StubLineFn)need(stub, "stub_line");
    s_count_prefix = (StubTextFn)need(stub, "stub_count_prefix");
    s_open = (StubCountFn)need(stub, "stub_open");
    s_misuse = (StubCountFn)need(stub, "stub_misuse");
    return s_requests && s_panel_count && s_panel && s_game_thread_count && s_tick && s_draw && s_line_count && s_line
        && s_count_prefix && s_open && s_misuse;
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

int main(int argc, char** argv)
{
    static HfApi api;
    SynScene scene;
    const char* name;
    bool no_host, api3, api4, api5, no_tick, window, exports;
    HMODULE stub = NULL, loader = NULL, dll;
    int (*init)(const HfApi*, HfMod*);
    const DbfWitness* rewritten = witness("hud_root"); /* a STATE and HUD_READ witness */
    uint32_t rewritten_rva = 0;
    void (*set_rewritten)(uint32_t) = NULL;
    int (*rewrite_calls)(void) = NULL;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 3) {
        puts("usage: wine_host.exe <divers_best_friend.dll> no-host|host-api3|host-api4|host-api5"
             " [<goose_overlay.dll> [<hellforge_modloader.dll>]]");
        return 2;
    }
    name = argv[2];
    no_host = !strcmp(name, "no-host");
    api3 = !strcmp(name, "host-api3");
    api4 = !strcmp(name, "host-api4");
    api5 = !strcmp(name, "host-api5");
    no_tick = !strcmp(name, "no-tick");
    window = api4 || api5;
    if (!(no_host || api3 || api4 || api5 || no_tick) || (!no_host && argc < 4) || (api5 && argc < 5)) {
        printf("FAIL unknown case \"%s\" or a missing stub\n", name);
        return 2;
    }
    printf("== %s\n", no_host ? "no Overlay Host"
                     : api3  ? "an Overlay Host older than 0.2.0 (API 3)"
                     : api4  ? "Overlay Host 0.2.x (API 4, no shared game-thread slot)"
                     : api5  ? "Overlay Host 0.3.x (API 5) and HellForge's rewrite list"
                             : "Overlay Host 0.2.x, and HellForge gives no game-thread slot");
    CreateThread(NULL, 0, watchdog, NULL, 0, NULL);

    syn_default(&scene);
    CHECK(syn_build(&scene), "the synthetic 25480438 image builds, with the generated witness table");
    CHECK(rewritten != NULL, "the generated table has the hud_root witness");
    if (rewritten) rewritten_rva = rewritten->rva + 3u;

    api.version = HF_MOD_SDK_VERSION;
    api.size = sizeof api;
    api.log = api_log;
    api.build_id = api_build_id;
    api.mod_id = api_mod_id;
    api.mod_folder = api_mod_folder;
    api.on = api_on;
    api.module_base = api_module_base;
    api.read = syn_read;
    api.write = syn_write;
    api.on_game_thread = no_tick ? api_refuse_game_thread : api_on_game_thread;
    api.read_code = syn_read;

    /* The stubs first, so DBF finds them by name as it finds the real ones (GetModuleHandleA). */
    if (!no_host) {
        stub = LoadLibraryA(argv[3]);
        CHECK(stub != NULL && GetModuleHandleA("goose_overlay.dll") == stub,
              "the stub Overlay Host loads as goose_overlay.dll");
        exports = load_stub(stub);
        CHECK(exports, "the stub exports what the host reads");
        if (!stub || !exports) return 1;
    } else {
        CHECK(GetModuleHandleA("goose_overlay.dll") == NULL, "no goose_overlay.dll is loaded");
    }
    if (api5) {
        uint8_t byte = 0;
        loader = LoadLibraryA(argv[4]);
        CHECK(loader != NULL && GetModuleHandleA("hellforge_modloader.dll") == loader,
              "the stub loader loads as hellforge_modloader.dll");
        set_rewritten = (void (*)(uint32_t))need(loader, "stub_set_rewritten");
        rewrite_calls = (int (*)(void))need(loader, "stub_rewrite_calls");
        if (!set_rewritten || !rewrite_calls) return 1;
        set_rewritten(rewritten_rva);
        /* One byte of the witness differs from the table, and the loader says HellForge rewrites it. */
        CHECK(syn_read(SYN_GAME_BASE + rewritten_rva, &byte, 1) == 0
                  && syn_poke_u8(SYN_GAME_BASE + rewritten_rva, (uint8_t)(byte ^ 0xffu)),
              "a byte of the hud_root witness is changed, as HellForge rewrites it");
    } else {
        CHECK(GetModuleHandleA("hellforge_modloader.dll") == NULL, "no hellforge_modloader.dll is loaded");
    }

    dll = LoadLibraryA(argv[1]);
    init = dll ? (int (*)(const HfApi*, HfMod*))need(dll, "hellforge_mod_init") : NULL;
    CHECK(dll != NULL && init != NULL, "divers_best_friend.dll loads and exports hellforge_mod_init");
    if (!init) return 1;

    CHECK(init(&api, &g_mod) == 0, "init returns 0");
    CHECK(logged(VERSION_LINE) == 1, "init logs \"" VERSION_LINE "\"");
    CHECK(g_listener_count == 1 && g_listeners[0].event == HF_EVENT_GAME_LOADED && g_listeners[0].mod == &g_mod,
          "init registers for HF_EVENT_GAME_LOADED only");
    CHECK(g_ticker_count == 0, "init takes no game-thread slot");
    if (stub)
        CHECK(s_requests() == 0 && s_panel_count() == 0 && s_game_thread_count() == 0,
              "init does not touch the Overlay Host");

    fire(HF_EVENT_GAME_LOADED);
    if (no_tick) {
        CHECK(logged(NO_TICK_LINE) == 1, "the \"" NO_TICK_LINE "\" line");
        CHECK(logged(NO_HOST_LINE) == 0 && s_requests() > 0, "the host was found (API 4)");
        CHECK(s_panel_count() == 0 && s_game_thread_count() == 0 && g_ticker_count == 0, "and DBF stops: no window");
        printf("== %s: %d failure(s)\n", name, test_failures());
        TEST_MAIN_END
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
        if (stub)
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
        if (api5) s_tick(1.0f / 60.0f);
        else api_tick();
    }
    CHECK(logged(VERSION_LINE) == 1, "after 3 ticks the version line is still logged once");
    CHECK(logged(NO_HOST_LINE) == (window ? 0 : 1),
          window ? "after 3 ticks still no \"running without a window\" line"
                 : "after 3 ticks the \"running without a window\" line is still logged exactly once");
    if (api5) {
        CHECK(logged(REWRITES_FOUND_LINE) == 1 && logged(REWRITES_MISSING_LINE) == 0,
              "the tick found hellforge_lua_rewrites and logged it once");
        CHECK(rewrite_calls() > 0, "admission asked hellforge_lua_rewrites about the changed byte");
    } else {
        CHECK(logged(REWRITES_MISSING_LINE) == 1 && logged(REWRITES_FOUND_LINE) == 0,
              "the tick found no hellforge_lua_rewrites and logged it once");
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
        CHECK(s_count_prefix("row") == 4 && rows_are(&scene, 4), "four rows, with the scene's names and codes in list order");
        CHECK(s_open() == 0 && s_misuse() == 0, "every begin has its end");
    }

    printf("== %s: %d failure(s)\n", name, test_failures());
    fflush(stdout);
    TEST_MAIN_END
}
