/* Diver's Best Friend (goose.divers-best-friend), the native HellForge port for game build 25480438.
 *
 * The entry point, and the one unit that talks to HellForge (hellforge_mod.h) and the Goose Overlay Host
 * (goose_overlay.h); the portable units it wires together include neither. It needs SDK 13's read_code (the bytes of
 * game code as they were before any hook), so a HellForge older than that gets a line in the log and nothing registered.
 *
 * Who runs what:
 *   hellforge_mod_init (the loader's thread)  checks the SDK, prepares the snapshot, listens for HF_EVENT_GAME_LOADED.
 *   OnGameLoaded (the loader's watch thread)  connects to the Overlay Host (API 4 or later, else no window), registers the
 *                                             tick (through the host's shared slot when it has one, ov_on_game_thread),
 *                                             then the Status window.
 *   Tick (the game thread)                    on the first tick sets up memory (hf->read, hf->write), admission
 *                                             (hf->module_base, hf->read_code, hellforge_lua_rewrites) and the readers
 *                                             (game.dll); every tick runs admission, reads the game, publishes a snapshot
 *                                             and drains the UI queue.
 *   Draw (the render thread)                  draws the newest snapshot; it never touches the game, admission or memory.
 * The ports go straight to HellForge's functions: their signatures are the SDK's. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "hellforge_mod.h" /* before goose_overlay.h, for its ov_on_game_thread */
#include "goose_overlay.h"
#include "admission.h"
#include "game.h"
#include "memory.h"
#include "snapshot.h"
#include "ui_settings.h"

#define DBF_VERSION "R50-hellforge.1"
#define DBF_GAME_BUILD "25480438"
#define DBF_PANEL_ID "goose.divers-best-friend"
#define DBF_TITLE "Diver's Best Friend"
/* The Overlay Host API the window needs (Overlay Host 0.2.0). DBF asks the host for this version, not for
 * OV_API_VERSION as ov_connect does: a 0.2.x host serves 4 and refuses 5. A newer host serves 4 as well. */
#define DBF_OV_API_MIN 4u

typedef int (*RewritesFn)(uint32_t rva, uint32_t size); /* hellforge_lua.h's hellforge_lua_rewrites */

static const HfApi* g_hf;
static HfMod* g_mod;
/* Set in OnGameLoaded before the tick and the window are registered, and never again: the game thread (Tick) and the
 * render thread (Draw) only read it. NULL: no window. */
static const OvApi* g_ov;
static bool g_loaded;    /* OnGameLoaded ran */
static bool g_started;   /* Tick: memory and admission are set up */
static bool g_game_init; /* Tick: game_init ran with game.dll's base */
static uint64_t g_ticks;

/* The Overlay Host's API, when it is loaded and serves version DBF_OV_API_MIN or later; else NULL. */
static const OvApi* connect_overlay(void)
{
    HMODULE host = GetModuleHandleA(OV_HOST_DLL);
    OvApiFn get = host != NULL ? (OvApiFn)(void*)GetProcAddress(host, "ov_api") : NULL;
    const OvApi* ov = get != NULL ? get(DBF_OV_API_MIN) : NULL;
    return ov != NULL && ov->version >= DBF_OV_API_MIN ? ov : NULL;
}

/* HellForge's list of the game code it rewrites, from its loader, or NULL. */
static RewritesFn find_rewrites(void)
{
    HMODULE loader = GetModuleHandleA("hellforge_modloader.dll");
    return loader != NULL ? (RewritesFn)(void*)GetProcAddress(loader, "hellforge_lua_rewrites") : NULL;
}

/* The first tick: the game's code is unpacked by the time its update runs, so admission starts here, not in init. */
static void start(uint64_t now_ms)
{
    MemPort mem = { g_hf->read, g_hf->write };
    AdmPort adm = { g_hf->module_base, g_hf->read_code, find_rewrites() };
    if (adm.rewrites != NULL)
        g_hf->log(g_mod, "Admission skips the code HellForge rewrites (hellforge_lua_rewrites found)");
    else
        g_hf->log(g_mod, "No hellforge_lua_rewrites in hellforge_modloader.dll: admission compares every witness byte");
    mem_init(&mem);
    adm_init(&adm, now_ms);
    g_started = true;
}

static void Tick(HfMod* mod, float dt, void* user)
{
    static DbfSnapshot s; /* the game thread's only: snap_publish copies it */
    static UiEvent events[UI_QUEUE_SLOTS];
    uint64_t now_ms = GetTickCount64();
    if (!g_started) start(now_ms);
    if (!g_game_init) { /* the first tick, unless game.dll was not loaded yet */
        size_t size = 0;
        uintptr_t game_dll = g_hf->module_base("game.dll", &size);
        if (game_dll != 0) {
            game_init(game_dll, (uint32_t)size);
            g_game_init = true;
        }
    }
    adm_tick(now_ms);
    memset(&s, 0, sizeof s);
    s.tick = ++g_ticks;
    game_read(&s.game);
    snap_fill_admission(&s);
    s.host_version = g_ov != NULL ? g_ov->version : 0;
    snap_publish(&s); /* every tick: a publish skipped while the window holds a buffer is made good by the next */
    (void)ui_drain(events, UI_QUEUE_SLOTS); /* the whole queue; nothing posts events yet */
}

static void Draw(const OvFrame* frame, void* user)
{
    const DbfSnapshot* s = snap_acquire();
    if (s == NULL)
        g_ov->text(DBF_TITLE " is starting..."); /* ASCII dots: the host's font has no ellipsis */
    else
        ui_settings_draw(g_ov, s);
    snap_release();
}

static void OnGameLoaded(HfMod* mod, HfEvent event, void* user)
{
    const OvApi* ov;
    if (g_loaded) return;
    g_loaded = true;
    ov = connect_overlay();
    if (ov == NULL) g_hf->log(g_mod, "No Overlay Host 0.2.0 or later: running without a window");
    g_ov = ov;
    if (!ov_on_game_thread(g_hf, g_mod, Tick, NULL)) {
        g_hf->log(g_mod, DBF_TITLE " could not get a game-thread tick");
        return;
    }
    if (ov != NULL) {
        OvPanelDef panel = { sizeof panel, DBF_PANEL_ID, DBF_TITLE, OV_PANEL_WINDOW, 0 };
        panel.width = 640.0f;
        panel.height = 520.0f;
        panel.draw = Draw;
        if (ov->register_panel(&panel) == NULL)
            g_hf->log(g_mod, "The Overlay Host did not take the " DBF_TITLE " window (its log says why)");
    }
}

HF_MOD_EXPORT int hellforge_mod_init(const HfApi* hf, HfMod* mod)
{
    if (hf->size < offsetof(HfApi, read_code) + sizeof hf->read_code) {
        hf->log(mod, DBF_TITLE " needs HellForge SDK 13 or later");
        return 0;
    }
    g_hf = hf;
    g_mod = mod;
    snap_init();
    if (hf->on(mod, HF_EVENT_GAME_LOADED, OnGameLoaded, NULL) != 0) {
        hf->log(mod, DBF_TITLE " could not listen for the game loading");
        return 0;
    }
    hf->log(mod, DBF_TITLE " " DBF_VERSION " (game " DBF_GAME_BUILD ")");
    return 0;
}
