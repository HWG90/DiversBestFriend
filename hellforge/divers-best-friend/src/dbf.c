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
 *   OnGameLoaded (the loader's watch thread)  reads %LOCALAPPDATA%\DBF\HellForge\settings.ini once (settings.h; the
 *                                             defaults when there is none), connects to the Overlay Host (API 4 or later,
 *                                             else no settings window), registers the tick (through the host's shared
 *                                             slot when it has one, register_tick), then the Status window. A second event is ignored, with one line in the log.
 *   Tick (the game thread)                    until hf->module_base finds game.dll it only publishes a snapshot saying
 *                                             "game.dll not loaded yet". On the first tick that finds it, memory,
 *                                             admission, native (the game functions at game.dll + DBF_FN_*), codes, the
 *                                             readers, the latch and the sounds start together, so admission's grace
 *                                             period counts from the real module. Every tick after that runs `run` (the
 *                                             order is written there), publishes a snapshot and drains the UI queue.
 *   Draw (the render thread)                  draws the Status window from the snapshot. The game renders its own
 *                                             stratagem HUD and the tick updates its native selection styling.
 * Every game read, write and call happens on the game thread. Nothing is restored from DllMain (there is none): no game
 * write runs under the loader lock. HellForge has no unload event, so a change the tick has not put back when the game
 * exits stays in the exiting game.
 *
 * With no Overlay Host (or one older than 0.2.0) DBF still enters codes from its key and controller bindings (List Select
 * with the game's own list on screen, and the slot hotkeys); its wheel bindings do nothing (the wheel comes from the
 * host), the capturing flag stays false, and one log line says so (Plan 2's ruling).
 *
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
#include "addresses_25480438.h"
#include "admission.h"
#include "bindings.h"
#include "codes.h"
#include "entry.h"
#include "game.h"
#include "latch.h"
#include "logic.h"
#include "memory.h"
#include "native.h"
#include "platform_win.h"
#include "settings.h"
#include "snapshot.h"
#include "sound.h"
#include "text.h"
#include "native_list.h"
#include "ui_settings.h"
#include "editor_shell.h"
#include "hud_bridge.h"
#include "settings_editor.h"
#include "hud_prefs.h"
#include "migration.h"

#define DBF_VERSION "R50-hellforge.6"
#define DBF_GAME_BUILD "25480438"
#define DBF_PANEL_ID "goose.divers-best-friend"
#define DBF_TITLE "Diver's Best Friend"
/* The Overlay Host API the window needs (Overlay Host 0.2.0). DBF asks the host for this version, not for
 * OV_API_VERSION as ov_connect does: a 0.2.x host serves 4 and refuses 5. A newer host serves 4 as well. */
#define DBF_OV_API_MIN 4u
#define DBF_NO_GAME_DLL "game.dll not loaded yet" /* the reason the first snapshots carry */
#define DBF_LOADER_DLL "hellforge_modloader.dll"
/* The settings file (Plan 2's Global Constraints: %LOCALAPPDATA%\DBF\HellForge\settings.ini, HellForge's prefix). */
#define DBF_SETTINGS_FOLDER L"\\DBF\\HellForge\\"
#define DBF_SETTINGS_NAME "settings.ini"
#define DBF_SETTINGS_NAME_W L"settings.ini"
/* DBF's own limits (no R46 line holds them): a hand-edited settings file is a few hundred bytes, so its first 64 KiB are
 * all of any real one; the problem text holds the first lines settings_parse lists; a LOCALAPPDATA path and the file's
 * part fit in PATH_CHARS. */
#define SETTINGS_MAX_BYTES 65536u
#define SETTINGS_PROBLEMS_SIZE 2048u
#define PATH_CHARS 600
#define SLOT_COUNT 4 /* the slot hotkeys: BIND_SLOT1 .. BIND_SLOT4 */
/* randomize_input_delay's generator: Marsaglia's xorshift32 ("Xorshift RNGs", 2003) with his shift triple 13, 17, 5;
 * its state must not be 0, so a zero seed takes RANDOM_NONZERO_STATE (2^32 / the golden ratio, any nonzero value does). */
#define XORSHIFT_A 13
#define XORSHIFT_B 17
#define XORSHIFT_C 5
#define RANDOM_NONZERO_STATE 0x9E3779B9u

/* hellforge_lua_rewrites' type, taken from the SDK's own declaration, so the function pointer GetProcAddress gives can
 * never be typed differently from the prototype the loader is built against. */
typedef __typeof__(hellforge_lua_rewrites)* RewritesFn;

static const HfApi* g_hf;
static HfMod* g_mod;
/* Set in OnGameLoaded before the tick and the panels are registered, and never again: the game thread (Tick) and the
 * render thread (Draw) only read it. NULL: no settings window. */
static const OvApi* g_ov;
static OvPanel* g_panel;
static bool g_loaded;        /* OnGameLoaded ran */
static bool g_loaded_again;  /* a repeated event was seen and logged */
static uint64_t g_ticks;

/* The settings: written by OnGameLoaded before the tick is registered, then read only by the game thread. */
static DbfSettings g_settings;
static int g_settings_problems;
static WCHAR g_settings_path[PATH_CHARS];
static bool g_settings_read; /* a file was read (else the defaults are in use) */
static char g_settings_text[SETTINGS_MAX_BYTES];
static char g_settings_problem_text[SETTINGS_PROBLEMS_SIZE];

/* The game thread's state. */
static bool g_started;            /* game.dll was found; every unit is set up */
/* The bindings' port: the platform's (platform_win.h), except that its foreground answer is the one sample the tick took
 * (g_front), so bind_poll's gate and the tick's own reason ("the game is not in front") always agree. */
static BindPort g_bind_port;
static bool (*g_platform_foreground)(void);
static bool g_bind_ready;
static bool g_front;
static ListState g_list;
static EntryJob g_job;            /* the one code entry: a List job, or a slot hotkey's while shortcut_active() */
static BindAction g_trigger;      /* the binding that started it (Instant waits for it to be up) */
static uintptr_t g_job_hud;       /* the HUD it began with (R46's HUD identity) */
static bool g_watching;           /* a job started and its end is not logged yet */
static bool g_pending_logged;     /* "not put back yet" was logged: "every change is put back" is due */
static bool g_slot_prev[SLOT_COUNT]; /* the slot hotkeys' levels at the last tick: a rising edge starts a shortcut */
static SoundState g_sound;
static uint32_t g_random;         /* xorshift32 state for randomize_input_delay */
static char g_bind_status[DBF_LIST_STATUS_SIZE];

/* --- small helpers ------------------------------------------------------------------------------------------------ */

static bool tick_foreground(void)
{
    return g_front;
}

/* One line in the mod's log: the units' log ports (admission, codes, native, latch, sound) and dbf.c's own lines. */
static void log_line(const char* line)
{
    g_hf->log(g_mod, "%s", line);
}

static uint64_t now_ms(void)
{
    return GetTickCount64();
}

/* randomize_input_delay's draw (R46 input.lua:12-14 used math.random; any spread does). */
static uint32_t next_random(void)
{
    uint32_t x = g_random != 0 ? g_random : RANDOM_NONZERO_STATE;
    x ^= x << XORSHIFT_A;
    x ^= x >> XORSHIFT_B;
    x ^= x << XORSHIFT_C;
    g_random = x;
    return x;
}

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
    HMODULE loader = GetModuleHandleA(DBF_LOADER_DLL);
    return loader != NULL ? (RewritesFn)(void*)GetProcAddress(loader, "hellforge_lua_rewrites") : NULL;
}

/* hellforge_modloader.dll's image in this process (its base and SizeOfImage, from its own PE header), where HellForge
 * keeps mod stratagems' code arrays (codes.h); 0 when it is not loaded or its header is not a 64-bit PE header. */
static uintptr_t loader_image(size_t* size)
{
    HMODULE loader = GetModuleHandleA(DBF_LOADER_DLL);
    const IMAGE_DOS_HEADER* dos = (const IMAGE_DOS_HEADER*)(void*)loader;
    const IMAGE_NT_HEADERS64* nt;
    *size = 0;
    if (loader == NULL || dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0) return 0;
    nt = (const IMAGE_NT_HEADERS64*)(const void*)((const uint8_t*)loader + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC) return 0;
    *size = nt->OptionalHeader.SizeOfImage;
    return (uintptr_t)loader;
}

/* --- the settings file -------------------------------------------------------------------------------------------- */

/* Appends `wide` to a log line as UTF-8. */
static void line_add_wide(DbfLine* l, const WCHAR* wide)
{
    char utf8[PATH_CHARS * 3];
    int n = WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8, (int)sizeof utf8, NULL, NULL);
    dbf_line_add(l, n > 0 ? utf8 : "(a path that cannot be shown)");
}

static void log_settings_failure(const char* what, const WCHAR* path)
{
    DbfLine l;
    dbf_line_begin(&l, what);
    line_add_wide(&l, path);
    dbf_line_add(&l, ": using the default settings");
    log_line(l.text);
}

/* Reads %LOCALAPPDATA%\DBF\HellForge\settings.ini into g_settings (settings.h), logging what it read and every problem;
 * the defaults when there is no file. The loader's watch thread, before the tick exists. */
static void load_settings(void)
{
    WCHAR path[PATH_CHARS];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", path, PATH_CHARS);
    size_t folder = sizeof DBF_SETTINGS_FOLDER / sizeof(WCHAR) - 1, name = sizeof DBF_SETTINGS_NAME_W / sizeof(WCHAR);
    HANDLE file;
    LARGE_INTEGER size;
    DWORD got = 0;
    DbfLine l;

    settings_defaults(&g_settings);
    g_settings_read = false;
    g_settings_problems = 0;
    if (n == 0) {
        log_line("LOCALAPPDATA is not set: using the default settings");
        return;
    }
    if ((size_t)n + folder + name > PATH_CHARS) { /* n is then the size the value needs */
        log_line("LOCALAPPDATA is too long for DBF's settings path: using the default settings");
        return;
    }
    memcpy(path + n, DBF_SETTINGS_FOLDER, folder * sizeof(WCHAR));
    memcpy(path + n + folder, DBF_SETTINGS_NAME_W, name * sizeof(WCHAR));
    memcpy(g_settings_path, path, (n + folder + name) * sizeof(WCHAR));
    file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                       FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) {
            log_settings_failure("Could not open ", path);
            return;
        }
        /* The path buffer begins with this process's LocalAppData. The full
         * destination is already retained separately for the settings writer. */
        path[n] = 0;
        MigrationResult imported = migration_first_start(path, g_settings_path);
        if (imported == MIGRATION_NONE) {
            log_settings_failure("No settings file at ", g_settings_path);
            return;
        }
        if (imported == MIGRATION_CREATED) log_line("Imported Lua DBF preferences into " DBF_SETTINGS_NAME);
        /* Also reopen on create failure: a concurrent writer may have won.
         * Apply only the published file, never uncommitted import state. */
        wcscpy(path, g_settings_path);
        file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (file == INVALID_HANDLE_VALUE) {
            log_settings_failure("Could not load first-start import at ", path);
            return;
        }
    }
    if (GetFileSizeEx(file, &size) && size.QuadPart > (LONGLONG)SETTINGS_MAX_BYTES)
        log_line(DBF_SETTINGS_NAME " is larger than 64 KiB: only its first 64 KiB are read");
    if (!ReadFile(file, g_settings_text, SETTINGS_MAX_BYTES, &got, NULL)) {
        CloseHandle(file);
        log_settings_failure("Could not read ", path);
        return;
    }
    CloseHandle(file);
    g_settings_problems = settings_parse(&g_settings, g_settings_text, got, g_settings_problem_text,
                                         sizeof g_settings_problem_text);
    g_settings_read = true;
    dbf_line_begin(&l, "Settings read from ");
    line_add_wide(&l, path);
    dbf_line_add(&l, " (");
    dbf_line_add_uint(&l, (uint32_t)g_settings_problems);
    dbf_line_add(&l, g_settings_problems == 1 ? " problem)" : " problems)");
    log_line(l.text);
    for (const char* p = g_settings_problem_text; *p != '\0';) { /* one log line per problem, "line N: ..." */
        const char* end = strchr(p, '\n');
        size_t len = end != NULL ? (size_t)(end - p) : strlen(p);
        dbf_line_begin(&l, DBF_SETTINGS_NAME " ");
        for (size_t i = 0; i < len && l.length < DBF_LINE_SIZE - 1; i++) l.text[l.length++] = p[i];
        l.text[l.length] = '\0';
        log_line(l.text);
        p += len + (end != NULL ? 1 : 0);
    }
}

/* --- start -------------------------------------------------------------------------------------------------------- */

/* Starts memory, admission, native, codes, the readers, the latch and the sounds once hf->module_base finds game.dll (the
 * game's code is unpacked and the module is there by the time its update runs, but not necessarily on the first tick);
 * until then it does nothing. Admission's 30 s grace period for a differing witness counts from this call. The real
 * NativePort is game.dll + each DBF_FN_* (Plan 2's ruling R3), called only through native.h's wrappers. */
static void start(uint64_t now)
{
    size_t size = 0, loader_size = 0;
    uintptr_t game_dll = g_hf->module_base("game.dll", &size), loader;
    if (game_dll == 0) return;
    loader = loader_image(&loader_size);
    {
        MemPort mem = { g_hf->read, g_hf->write };
        AdmPort adm = { g_hf->module_base, g_hf->read_code, find_rewrites(), log_line };
        NativePort nat = {
            (void (*)(uintptr_t))(game_dll + DBF_FN_INPUT_HANDLER),
            (uint8_t(*)(uintptr_t))(game_dll + DBF_FN_OPEN_INPUT),
            (void (*)(uintptr_t))(game_dll + DBF_FN_CLOSE_INPUT),
            (void (*)(uintptr_t, uint32_t))(game_dll + DBF_FN_REQUEST_SLOT),
            (void (*)(uintptr_t, uint32_t))(game_dll + DBF_FN_UI_SOUND),
            (uintptr_t(*)(uintptr_t, uint32_t*, uint32_t, uint32_t, uintptr_t, uintptr_t))(game_dll + DBF_FN_SCRAMBLE_QUERY),
            log_line,
            now_ms,
        };
        CodePort codes = { g_hf->stratagem_row, loader, loader_size, log_line };
        log_line("game.dll found; admission starts");
        if (adm.rewrites != NULL) log_line("Admission skips the code HellForge rewrites (hellforge_lua_rewrites found)");
        else log_line("No hellforge_lua_rewrites in hellforge_modloader.dll: admission compares every witness byte");
        if (loader == 0) log_line("No " DBF_LOADER_DLL " image: HellForge mod stratagems get no code");
        mem_init(&mem);
        adm_init(&adm, now);
        HudBridgePort bridge = {g_hf->read, g_hf->read_code, adm.rewrites, log_line};
        hud_bridge_init(game_dll, size, &bridge);
        native_init(&nat);
        native_set_base(game_dll);
        codes_init(&codes);
        game_init(game_dll, (uint32_t)size);
        latch_init(game_dll, log_line);
        native_list_init(game_dll, log_line);
    }
    sound_init(&g_sound, nat_ui_sound, log_line);
    memset(&g_job, 0, sizeof g_job);
    g_watching = false;
    g_random = (uint32_t)now ^ (uint32_t)(now >> 32); /* next_random takes RANDOM_NONZERO_STATE for a 0 */
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

/* --- the job ------------------------------------------------------------------------------------------------------ */

static bool job_active(void)
{
    return g_job.state == ENTRY_RUNNING || shortcut_active();
}

static int pending_changes(void)
{
    return mem_journal_count(MEM_OWNER_ENTRY) + mem_journal_count(MEM_OWNER_LATCH);
}

/* Shared by terminal and selector input. Only selection needs the HUD unobstructed. */
static const char* common_input_blocker(const GameView* v)
{
    if (!g_settings.enabled) return "DBF is off in its settings";
    if (g_ov != NULL) {
        if (g_ov->version < 8 || g_ov->size < offsetof(OvApi, input_captured) + sizeof g_ov->input_captured
            || !g_ov->input_captured) return "Overlay Host 0.6.0 required for input";
        if (g_ov->input_captured()) return "an Overlay Host window is open";
    }
    if (!v->local_ok) return "local player unavailable";
    return NULL;
}

static const char* input_blocked(const GameView* v)
{
    const char* reason = common_input_blocker(v);
    if (reason) return reason;
    return v->local.unobstructed ? NULL : "UI obstructed";
}

/* Why the running job (List or slot hotkey) must stop this tick before anything is sent, or NULL: the mission ended, the
 * HUD went away or is another one (R46's HUD identity: selection.lua:13, input.lua:367 and 382), the local player
 * changed, or DBF's input is not available (`blocked`; R46 gave no buttons then, entry.lua:258, and stopped both jobs,
 * selection.lua:12-16 and release.lua:25). entry and latch check everything else themselves. */
static const char* cancel_reason(const GameView* v, const char* blocked)
{
    if (!v->in_gameplay) return "the mission ended";
    if (!v->hud_ready) return "the HUD went away";
    if (v->hud != g_job_hud) return "the HUD changed";
    if (v->local_ok && (v->local.manager != g_job.identity_manager || v->local.key != g_job.identity_key
                        || v->local.component != g_job.component))
        return "player changed";
    return blocked;
}

/* R46 selection.lua:49-51: a List job stops when the list no longer offers its stratagem, that is when no row of the view
 * that may be chosen (logic_list_rows: not on a timer, not unavailable, not hidden) shows the job's kind. Not for a slot
 * hotkey's job, which R46's release path did not tie to the list. */
static bool card_gone(const GameView* v)
{
    bool eligible[LOGIC_LIST_ROWS];
    int n = logic_list_rows(v, &g_settings, NULL, eligible);
    for (int i = 0; i < n; i++)
        if (eligible[i] && v->rows[i].kind == g_job.kind) return false;
    return true;
}

/* Plan 2's restore ruling: the job ends through entry_cancel or entry_cancel_shortcut (which gives the latch back with
 * R46's owner checks), then whatever ENTRY still holds is put back. Never mem_restore_all: it skips the latch's checks. */
static void cancel_job(const GameView* v, const char* why)
{
    if (shortcut_active()) entry_cancel_shortcut(&g_job, v, why);
    else entry_cancel(&g_job, why);
    entry_retry_release(v);
}

/* Each tick, while their journals hold anything: a release the game did not take (ENTRY), and a latch release that left
 * entries (a failed write, or a controls pointer that could not be read), with avatar_valid when the view shows the player
 * the latch was taken for: latch.c's own owner (manager, key and component, R46 input.lua:376; false with no player),
 * whether the latch came from a slot hotkey that ran or from one refused after the latch was taken. */
static void retry_restores(const GameView* v)
{
    entry_retry_release(v);
    if (!latch_held() && mem_journal_count(MEM_OWNER_LATCH) > 0)
        (void)latch_release(v->local_ok && latch_owner_is(&v->local));
    if (g_pending_logged && pending_changes() == 0) {
        g_pending_logged = false;
        log_line("Every change DBF made to the game is put back");
    }
}

/* " (every change put back)" or " (<n> changes not put back yet: DBF tries again each tick)". */
static void add_restore_state(DbfLine* l)
{
    int pending = pending_changes();
    if (pending == 0) {
        dbf_line_add(l, " (every change put back)");
        return;
    }
    dbf_line_add(l, " (");
    dbf_line_add_uint(l, (uint32_t)pending);
    dbf_line_add(l, pending == 1 ? " change not put back yet" : " changes not put back yet");
    dbf_line_add(l, ": DBF tries again each tick)");
    g_pending_logged = true;
}

/* "<who> not entered: <why>", and, when the refusal left changes behind (a slot hotkey refused after it took the latch,
 * whose release could not write everything back), how many are still to be put back. */
static void log_refused(const char* who, const char* why)
{
    DbfLine l;
    dbf_line_begin(&l, who);
    dbf_line_add(&l, " not entered: ");
    dbf_line_add(&l, why);
    if (pending_changes() > 0) add_restore_state(&l);
    log_line(l.text);
}

static void log_started(const char* who, uint32_t interval)
{
    char name[DBF_LIST_NAME_SIZE];
    DbfLine l;
    dbf_kind_name_copy(g_job.kind, name, sizeof name);
    dbf_line_begin(&l, who);
    dbf_line_add(&l, ": entering ");
    dbf_line_add(&l, name);
    dbf_line_add(&l, " (");
    dbf_line_add_uint(&l, g_job.code.len);
    if (g_job.instant) {
        dbf_line_add(&l, " directions, Instant)");
    } else {
        dbf_line_add(&l, " directions, ");
        dbf_line_add_uint(&l, interval);
        dbf_line_add(&l, " ms apart)");
    }
    log_line(l.text);
}

/* After the steps: once a job that started is neither running nor an active shortcut, one line says how it ended. */
static void watch_job(void)
{
    char name[DBF_LIST_NAME_SIZE];
    DbfLine l;
    if (!g_watching || job_active()) return;
    g_watching = false;
    if (g_job.state == ENTRY_DONE) {
        dbf_kind_name_copy(g_job.kind, name, sizeof name);
        dbf_line_begin(&l, "Code entry done: ");
        dbf_line_add(&l, name);
    } else {
        dbf_line_begin(&l, "Code entry failed: ");
        dbf_line_add(&l, g_job.reason[0] != '\0' ? g_job.reason : "cancelled");
    }
    add_restore_state(&l);
    log_line(l.text);
}

/* A slot hotkey's rising edge (R46 entry.lua:399-406): slot `slot`, from the closed or the open menu. */
static bool begin_shortcut(const GameView* v, int slot, uint64_t now)
{
    char why[DBF_REASON_SIZE];
    uint32_t interval = logic_interval(&g_settings, next_random);
    DbfLine who;
    dbf_line_begin(&who, "Slot ");
    dbf_line_add_uint(&who, (uint32_t)slot);
    if (!entry_begin_shortcut(&g_job, v, slot, interval, g_settings.instant_stratagems, now, why, sizeof why)) {
        log_refused(who.text, why);
        return false;
    }
    g_trigger = (BindAction)(BIND_SLOT1 + slot - 1);
    g_job_hud = v->hud;
    g_watching = true;
    log_started(who.text, interval);
    return true;
}

/* List Select's Confirm on row `row` of the view (R46 selection.lua:87-94). */
static bool begin_list(const GameView* v, int row, uint64_t now)
{
    uint32_t interval = logic_interval(&g_settings, next_random), kind = v->rows[row].kind;
    if (!entry_begin(&g_job, v, kind, interval, g_settings.instant_stratagems, false, now)) {
        char name[DBF_LIST_NAME_SIZE];
        dbf_kind_name_copy(kind, name, sizeof name);
        log_refused(name, g_job.reason);
        return false;
    }
    g_trigger = BIND_CONFIRM;
    g_job_hud = v->hud;
    g_watching = true;
    log_started("List Select", interval);
    return true;
}

/* --- the tick ----------------------------------------------------------------------------------------------------- */

/* One tick with this tick's view (game_read, which runs codes_table, came first), in R46's frame order (entry.lua:254-
 * 420), adapted:
 *   1. the bindings, polled after the read so that `allowed` uses this tick's view (DBF on, no host window capturing,
 *      the local player there with the UI unobstructed); bind_poll checks the game's window is in front;
 *   2. the restores still owed: ENTRY, and LATCH while the latch is not held;
 *   3. a running job stops when the mission ended, the HUD went or was replaced, the player changed or the input went,
 *      and a List job when no row that may be chosen shows its stratagem any more ("card membership changed", R46);
 *   4. the slot hotkeys: a rising edge with no job running and no shortcut active starts one (Confirm cancels it, and the
 *      shortcut's step ends it once the game closes the menu, giving the latch back);
 *   5. List Select, which sees a closed list while a shortcut is active (no choice, no Confirm; its edges are still
 *      seen); LIST_CONFIRM starts a List job;
 *   6. the job's step, not on the tick it started (R46 sends the first direction on the next tick; a shortcut's view is
 *      stale on its first tick, latch.h);
 *   7. the sounds, while selection_sounds is on and SOUND is admitted (sound.h);
 *   8. one log line when a job ended, saying whether every change is back. */
static void run(const GameView* v, uint64_t now)
{
    bool levels[BIND_COUNT];
    const char* blocked = input_blocked(v);
    bool started = false;
    int row = -1;
    ListEvent event;

    bind_poll(levels, blocked == NULL, g_bind_status, sizeof g_bind_status); /* its foreground is g_front, below */
    if (blocked == NULL && !g_front) blocked = "the game is not in front";

    retry_restores(v);
    if (job_active()) {
        const char* why = cancel_reason(v, blocked);
        if (why == NULL && !shortcut_active() && g_job.state == ENTRY_RUNNING && card_gone(v)) why = "card membership changed";
        if (why != NULL) cancel_job(v, why);
    }

    for (int i = 0; i < SLOT_COUNT; i++) {
        bool down = levels[BIND_SLOT1 + i], edge = down && !g_slot_prev[i];
        g_slot_prev[i] = down;
        if (edge && !started && !job_active() && v->in_gameplay && v->hud_ready) /* every level is false while blocked */
            started = begin_shortcut(v, i + 1, now);
    }

    event = logic_list_step(&g_list, shortcut_active() ? NULL : v, &g_settings, levels, job_active(), &row);
    if (event == LIST_CONFIRM && !started && !job_active() && row >= 0 && row < v->row_count)
        started = begin_list(v, row, now);

    if (!started) {
        if (shortcut_active()) entry_step_shortcut(&g_job, v, now, levels[g_trigger], levels[BIND_CONFIRM]);
        else if (g_job.state == ENTRY_RUNNING) entry_step(&g_job, v, now, levels[g_trigger]);
    }
    if (g_settings.selection_sounds && adm_feature(FEAT_SOUND, NULL) == ADMIT_OK)
        sound_step(&g_sound, event, started, now);
    watch_job();
}

/* Before game.dll is found: the inputs are read with nothing allowed (a key held now must be let go first) and List
 * Select sees a closed list. */
static void run_waiting(void)
{
    bool levels[BIND_COUNT];
    bind_poll(levels, false, g_bind_status, sizeof g_bind_status);
    for (int i = 0; i < SLOT_COUNT; i++) g_slot_prev[i] = false;
    (void)logic_list_step(&g_list, NULL, &g_settings, levels, false, NULL);
}

/* The Lua update polls for a grant. Keep both input paths mutually exclusive
 * through the entire close/release transition, including failed-write retries. */
static void update_owners(DbfSnapshot* s, uint64_t now)
{
    static bool yielding;
    bool requested = hud_bridge_requested();
    int buttons = -1;
    bool terminal_allowed = false;
    if (requested != yielding) {
        bind_init(&g_bind_port, g_settings.bind);
        memset(&g_list, 0, sizeof g_list);
        g_list.chosen = -1;
        memset(g_slot_prev, 0, sizeof g_slot_prev);
        yielding = requested;
    }
    if (requested) {
        if (job_active()) cancel_job(&s->game, "native HUD activated");
        retry_restores(&s->game);
        watch_job();
        bool levels[BIND_COUNT];
        bool active = g_front && common_input_blocker(&s->game) == NULL;
        bool allowed = active && s->game.local.unobstructed;
        terminal_allowed = active && s->game.in_gameplay;
        bind_poll(levels, allowed, g_bind_status, sizeof g_bind_status);
        if (allowed) {
            buttons = 0;
            for (int i = 0; i < BIND_COUNT; ++i)
                if (levels[i]) buttons |= 1 << i;
        }
        if (!hud_bridge_owned()) native_list_update(&s->game, -1);
    } else {
        run(&s->game, now);
        native_list_update(&s->game, g_settings.enabled && !shortcut_active() ? g_list.chosen : -1);
    }
    bool ready = requested && !job_active() && !native_list_pending() && !pending_changes();
    hud_bridge_publish(&s->game, &g_settings, buttons, terminal_allowed, s->build_ok, ready);
    s->hud_owned = hud_bridge_owned();
    hud_bridge_status(s->hud_status, sizeof s->hud_status);
}

static bool settings_save_failed;

static void apply_settings(void)
{
    UiEvent events[UI_QUEUE_SLOTS];
    int count = ui_drain(events, UI_QUEUE_SLOTS);
    if (!count) return;
    DbfSettings updated = g_settings;
    bool changed = false;
    for (int i = 0; i < count; ++i) {
        if (editor_apply(&updated, &events[i])) changed = true;
    }
    if (!changed) return;
    settings_save_failed = !g_settings_path[0] || !hud_prefs_apply(g_settings_path, &g_settings, &updated);
    if (settings_save_failed) {
        log_line("Could not save settings to settings.ini; retained the previous settings");
        return;
    }
    bool rebind = false;
    for (int i = 0; i < BIND_COUNT; ++i)
        if (g_settings.bind[i].kind != updated.bind[i].kind || g_settings.bind[i].code != updated.bind[i].code)
            rebind = true;
    g_settings = updated;
    g_settings_read = true;
    if (rebind && g_bind_ready) bind_init(&g_bind_port, g_settings.bind);
}

static void Tick(HfMod* mod, float dt, void* user)
{
    static DbfSnapshot s; /* the game thread's only: snap_publish copies it */
    apply_settings();
    uint64_t now = GetTickCount64();
    if (!g_bind_ready) { /* the bindings need nothing of game.dll: from the first tick (platform_win.h: game thread) */
        g_bind_port = *dbf_bind_port(g_ov);
        g_platform_foreground = g_bind_port.foreground;
        g_bind_port.foreground = tick_foreground;
        bind_init(&g_bind_port, g_settings.bind);
        memset(&g_list, 0, sizeof g_list);
        g_list.chosen = -1;
        g_bind_ready = true;
    }
    g_front = g_platform_foreground != NULL && g_platform_foreground(); /* the tick's one look at the window in front */
    if (!g_started) start(now);
    memset(&s, 0, sizeof s);
    s.tick = ++g_ticks;
    if (g_started) {
        adm_tick(now);
        game_read(&s.game);
        snap_fill_admission(&s);
        update_owners(&s, now);
    } else {
        fill_waiting(&s);
        run_waiting();
    }
    snap_fill_list(&s, &s.game, &g_settings, &g_list, &g_job, g_bind_status, g_settings_read ? DBF_SETTINGS_NAME : NULL,
                   g_settings_problems);
    s.options = g_settings;
    s.settings_save_failed = settings_save_failed;
    if (g_front && g_bind_port.pad_buttons && g_ov && g_ov->version >= 8 &&
        g_ov->size >= offsetof(OvApi, input_captured) + sizeof g_ov->input_captured &&
        g_ov->input_captured && g_ov->input_captured())
        g_bind_port.pad_buttons(&s.editor_pad);
    s.host_version = g_ov != NULL ? g_ov->version : 0;
    snap_publish(&s); /* every tick: a publish skipped while the window holds a buffer is made good by the next */
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
    else if (editor_shell_available(g_ov))
        editor_shell_draw(g_ov, s, frame, g_panel);
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
    load_settings();
    ov = connect_overlay();
    if (ov == NULL)
        g_hf->log(g_mod, "No Overlay Host 0.2.0 or later: running without a settings window; key and controller "
                         "bindings still work, wheel bindings do nothing");
    else if (ov->version < 8)
        g_hf->log(g_mod, "Update Goose Overlay Host to 0.6.0 to use gameplay bindings while the host is loaded");
    g_ov = ov;
    if (!register_tick()) {
        g_hf->log(g_mod, DBF_TITLE " could not get a game-thread tick");
        return;
    }
    if (ov != NULL) {
        OvPanelDef panel = { sizeof panel, DBF_PANEL_ID, DBF_TITLE, OV_PANEL_WINDOW, 0 };
        bool editor = editor_shell_available(ov);
        panel.width = editor ? 1260.0f : 640.0f;
        panel.height = editor ? 930.0f : 520.0f;
        panel.window_flags = editor ? OV_WINDOW_NO_TITLE | OV_WINDOW_NO_SCROLLBAR : 0;
        panel.draw = Draw;
        g_panel = ov->register_panel(&panel);
        if (g_panel == NULL)
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
    settings_defaults(&g_settings);
    hf->log(mod, DBF_TITLE " " DBF_VERSION " (game " DBF_GAME_BUILD ")"); /* before on: it may run OnGameLoaded at once */
    if (hf->on(mod, HF_EVENT_GAME_LOADED, OnGameLoaded, NULL) != 0) {
        hf->log(mod, DBF_TITLE " could not listen for the game loading");
        return 0;
    }
    return 0;
}
