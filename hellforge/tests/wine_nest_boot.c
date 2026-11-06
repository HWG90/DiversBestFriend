/* Production DBF + NEST initialization in an isolated process per scenario.
 * Usage in scratch root: wine_nest_boot.exe bundled|existing|late|legacy|planned */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include "hellforge_mod.h"
#include "goose_overlay.h"

typedef int (*Init)(const HfApi*, HfMod*);
struct HfMod { const char* id; char folder[MAX_PATH]; };
static struct HfMod dbf = {.id = "goose.divers-best-friend"}, host = {.id = "goose.overlay-host"};
static struct Listener { HfMod* mod; HfEvent event; HfEventCallback fn; void* user; } listeners[16];
static int listener_count, slots, panels, migration, deferred;
static int planned, inactive;
static void check(int ok, const char* message)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", message);
    if (!ok) exit(1);
}
static void log_line(HfMod* mod, const char* fmt, ...)
{
    char line[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf(line, sizeof line, fmt, args);
    va_end(args);
    printf("[%s] %s\n", mod->id, line);
    if (strstr(line, "panel goose.divers-best-friend") && strstr(line, "registered")) ++panels;
    if (strstr(line, "Disable it and restart")) ++migration;
    if (strstr(line, "bundled NEST deferred")) ++deferred;
}
static const char* folder(HfMod* mod) { return mod->folder; }
static const char* id(HfMod* mod) { return mod->id; }
static const char* build(void) { return "25480438"; }
static int listen(HfMod* mod, HfEvent event, HfEventCallback fn, void* user)
{
    check(listener_count < 16, "listener capacity");
    listeners[listener_count++] = (struct Listener){mod, event, fn, user};
    return 0;
}
static int on_tick(HfMod* mod, HfTickCallback fn, void* user) { ++slots; return 1; }
static int mods(HfMod* mod, uint32_t index, HfModInfo* out)
{
    if (!planned || index) return 0;
    *out = (HfModInfo){.size = sizeof *out, .kind = HF_MOD_CODE, .id = host.id,
                       .folder = host.folder, .loaded = inactive};
    return 1;
}
static void fire_loaded(void)
{
    int count = listener_count;
    for (int i = 0; i < count; ++i)
        if (listeners[i].event == HF_EVENT_GAME_LOADED)
            listeners[i].fn(listeners[i].mod, HF_EVENT_GAME_LOADED, listeners[i].user);
}
static HMODULE load(const char* path)
{
    HMODULE module = LoadLibraryExA(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    check(module != NULL, path);
    return module;
}
static void init(HMODULE module, HfApi* api, HfMod* mod)
{
    Init fn = (Init)(void*)GetProcAddress(module, "hellforge_mod_init");
    check(fn && fn(api, mod) == 0, "production DLL initialization succeeds");
}
static void draw(const OvFrame* frame, void* user) {}

int main(int argc, char** argv)
{
    check(argc == 2, "scenario supplied");
    char cwd[MAX_PATH], path[MAX_PATH];
    check(GetCurrentDirectoryA(sizeof cwd, cwd) > 0, "scratch directory");
    snprintf(dbf.folder, sizeof dbf.folder, "%s\\dbf", cwd);
    snprintf(host.folder, sizeof host.folder, "%s\\standalone", cwd);
    check(SetEnvironmentVariableA("LOCALAPPDATA", cwd), "isolated settings directory");
    HfApi api = {.size = sizeof api, .version = HF_MOD_SDK_VERSION, .log = log_line,
                 .mod_folder = folder, .mod_id = id, .build_id = build, .on = listen,
                 .on_game_thread = on_tick, .mods = mods};
    int existing = !strcmp(argv[1], "existing"), legacy = !strcmp(argv[1], "legacy");
    int late = !strcmp(argv[1], "late");
    inactive = !strcmp(argv[1], "inactive");
    planned = inactive || !strcmp(argv[1], "planned");
    HMODULE standalone = NULL;
    if (existing || legacy || inactive) {
        snprintf(path, sizeof path, "%s\\goose_overlay.dll", host.folder);
        standalone = load(path);
        if (!inactive) init(standalone, &api, &host);
    }
    snprintf(path, sizeof path, "%s\\divers_best_friend.dll", dbf.folder);
    HMODULE dll = load(path);
    init(dll, &api, &dbf);
    check(panels == 0, "DBF waits until planned modules have initialized");
    fire_loaded();
    int count = listener_count;
    check(panels == !planned && slots == 1, "one DBF panel and one game-thread slot");
    check((migration > 0) == legacy && (deferred > 0) == planned, "legacy migration and unresolved-plan handling");
    fire_loaded();
    check(listener_count == count && panels == !planned && slots == 1, "repeated game-loaded event is idempotent");
    if (planned) {
        snprintf(path, sizeof path, "%s\\goose_overlay.dll", dbf.folder);
        check(GetModuleHandleA(path) == NULL, "pending standalone prevents bundled startup");
        return 0;
    }
    HMODULE module = GetModuleHandleA("goose_overlay.dll");
    OvApiFn get = (OvApiFn)(void*)GetProcAddress(module, "ov_api");
    const OvApi* active = get ? get(8) : NULL;
    check(active != NULL, "real NEST API is active");
    check(!strcmp(active->host_folder(), existing || legacy ? host.folder : dbf.folder), "initial owner retains its folder");
    if (existing || legacy) {
        snprintf(path, sizeof path, "%s\\goose_overlay.dll", dbf.folder);
        check(GetModuleHandleA(path) == NULL, "standalone owner prevents bundled DLL activation");
    }
    OvPanelDef other = {sizeof other, "test.other-mod", "Other mod", OV_PANEL_WINDOW, 0, 0, 400, 300, draw, NULL};
    check(active->register_panel(&other) != NULL, "another mod shares the host");
    if (late) {
        snprintf(path, sizeof path, "%s\\goose_overlay.dll", host.folder);
        standalone = load(path);
        check(standalone != module, "two distinct DLL paths are mapped");
        init(standalone, &api, &host);
        init(standalone, &api, &host);
        OvApiFn second = (OvApiFn)(void*)GetProcAddress(standalone, "ov_api");
        check(second && second(8) == active, "later standalone shares the same API");
        check(listener_count == count && slots == 1 && panels == 1, "later host never duplicates callbacks or DBF panel");
        check(!strcmp(active->host_folder(), dbf.folder), "later init preserves original DBF host folder");
        check(second(8)->register_panel(&other) == NULL, "both DLL paths share the panel registry");
    }
    puts("PASS production DBF bundled NEST boot");
    return 0;
}
