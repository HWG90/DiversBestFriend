/* Diver's Best Friend (goose.divers-best-friend), the native HellForge port for game build 25480438.
 *
 * The entry point, and the one unit that talks to HellForge (hellforge_mod.h) and the Goose Overlay Host
 * (goose_overlay.h); the portable units it wires together include neither. It needs SDK 13's read_code (the bytes of
 * game code as they were before any hook), so a HellForge older than that gets a line in the log and nothing registered.
 *
 * Who runs what:
 *   hellforge_mod_init (the loader's thread)  checks the SDK, prepares the snapshot, logs the version line, then listens
 *                                             for HF_EVENT_GAME_LOADED (the version line first: a loader may deliver the
 *                                             event from inside hf->on, and what that logs follows it).
 *   OnGameLoaded (the loader's watch thread)  connects to the Overlay Host (API 4 or later, else no window), registers the
 *                                             tick (through the host's shared slot when it has one, register_tick),
 *                                             then the Status window. A second event is ignored, with one line in the log.
 *   Tick (the game thread)                    until hf->module_base finds game.dll it only publishes a snapshot saying
 *                                             "game.dll not loaded yet". On the first tick that finds it, memory
 *                                             (hf->read, hf->write), admission (hf->module_base, hf->read_code,
 *                                             hellforge_lua_rewrites, the log) and the readers (game.dll) start together, so
 *                                             admission's grace period counts from the real module. Every tick after that
 *                                             runs admission, reads the game, publishes a snapshot and drains the UI queue.
 *   Draw (the render thread)                  draws the newest snapshot; it reads only the snapshot and constant names
 *                                             (adm_feature_name), never game memory or admission state.
 * The ports go straight to HellForge's functions: their signatures are the SDK's. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "hellforge_mod.h" /* before goose_overlay.h, as its ov_on_game_thread (not used here: see register_tick) wants */
#include "hellforge_lua.h" /* the prototype of hellforge_lua_rewrites; HF_LUA_API stays empty here: nothing links to it */
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
#define DBF_NO_GAME_DLL "game.dll not loaded yet" /* the reason the first snapshots carry */

/* hellforge_lua_rewrites' type, taken from the SDK's own declaration, so the function pointer GetProcAddress gives can
 * never be typed differently from the prototype the loader is built against. */
typedef __typeof__(hellforge_lua_rewrites)* RewritesFn;

static const HfApi* g_hf;
static HfMod* g_mod;
/* Set in OnGameLoaded before the tick and the window are registered, and never again: the game thread (Tick) and the
 * render thread (Draw) only read it. NULL: no window. */
static const OvApi* g_ov;
static bool g_loaded;        /* OnGameLoaded ran */
static bool g_loaded_again;  /* a repeated event was seen and logged */
static bool g_started;       /* Tick: game.dll was found; memory, admission and the readers are set up */
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

/* Admission's log lines (the count of witness bytes HellForge rewrites) go to the mod's log. */
static void adm_log(const char* line)
{
    g_hf->log(g_mod, "%s", line);
}

/* Starts memory, admission and the readers once hf->module_base finds game.dll (the game's code is unpacked and the module
 * is there by the time its update runs, but not necessarily on the first tick); until then it does nothing. Admission's
 * 30 s grace period for a differing witness counts from this call. */
static void start(uint64_t now_ms)
{
    size_t size = 0;
    uintptr_t game_dll = g_hf->module_base("game.dll", &size);
    if (game_dll == 0) return;
    MemPort mem = { g_hf->read, g_hf->write };
    AdmPort adm = { g_hf->module_base, g_hf->read_code, find_rewrites(), adm_log };
    g_hf->log(g_mod, "game.dll found; admission starts");
    if (adm.rewrites != NULL)
        g_hf->log(g_mod, "Admission skips the code HellForge rewrites (hellforge_lua_rewrites found)");
    else
        g_hf->log(g_mod, "No hellforge_lua_rewrites in hellforge_modloader.dll: admission compares every witness byte");
    mem_init(&mem);
    adm_init(&adm, now_ms);
    game_init(game_dll, (uint32_t)size);
    g_started = true;
}

/* The snapshot before game.dll is loaded: nothing read, every feature waiting, and the build's reason says why. */
static void fill_waiting(DbfSnapshot* s)
{
    s->build_ok = false;
    snap_copy_text(s->build_reason, sizeof s->build_reason, DBF_NO_GAME_DLL);
    for (int f = 0; f < FEAT_COUNT; f++) {
        s->admit[f] = ADMIT_PENDING;
        snap_copy_text(s->admit_reason[f], sizeof s->admit_reason[f], DBF_NO_GAME_DLL);
    }
}

static void Tick(HfMod* mod, float dt, void* user)
{
    static DbfSnapshot s; /* the game thread's only: snap_publish copies it */
    static UiEvent events[UI_QUEUE_SLOTS];
    uint64_t now_ms = GetTickCount64();
    if (!g_started) start(now_ms);
    memset(&s, 0, sizeof s);
    s.tick = ++g_ticks;
    if (g_started) {
        adm_tick(now_ms);
        game_read(&s.game);
        snap_fill_admission(&s);
    } else {
        fill_waiting(&s);
    }
    s.host_version = g_ov != NULL ? g_ov->version : 0;
    snap_publish(&s); /* every tick: a publish skipped while the window holds a buffer is made good by the next */
    (void)ui_drain(events, UI_QUEUE_SLOTS); /* the whole queue; nothing posts events yet */
}

/* The tick, through the host's shared game-thread slot when the table connect_overlay got has one (Overlay Host 0.3.0 and
 * later), else through HellForge's own. Not the header's ov_on_game_thread: that asks the host for OV_API_VERSION (7 since
 * the wheel total) and so uses HellForge's slot on every host older than 0.5.0, which DBF runs on as well. 1 registered,
 * 0 refused by both. */
static int register_tick(void)
{
    if (g_ov != NULL && g_ov->size >= offsetof(OvApi, on_game_thread) + sizeof g_ov->on_game_thread &&
        g_ov->on_game_thread != NULL && g_ov->on_game_thread(g_mod, Tick, NULL))
        return 1;
    return g_hf->size >= offsetof(HfApi, on_game_thread) + sizeof g_hf->on_game_thread && g_hf->on_game_thread != NULL &&
           g_hf->on_game_thread(g_mod, Tick, NULL);
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
    if (g_loaded) { /* the window and the tick are registered once, whatever the loader delivers */
        if (!g_loaded_again) g_hf->log(g_mod, DBF_TITLE " ignored a repeated game-loaded event");
        g_loaded_again = true;
        return;
    }
    g_loaded = true;
    ov = connect_overlay();
    if (ov == NULL) g_hf->log(g_mod, "No Overlay Host 0.2.0 or later: running without a window");
    g_ov = ov;
    if (!register_tick()) {
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
    hf->log(mod, DBF_TITLE " " DBF_VERSION " (game " DBF_GAME_BUILD ")"); /* before on: it may run OnGameLoaded at once */
    if (hf->on(mod, HF_EVENT_GAME_LOADED, OnGameLoaded, NULL) != 0) {
        hf->log(mod, DBF_TITLE " could not listen for the game loading");
        return 0;
    }
    return 0;
}
