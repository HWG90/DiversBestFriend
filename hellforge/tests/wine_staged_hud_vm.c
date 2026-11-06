/* Exercise the launcher-selected production DLL in the pinned game's Lua VM.
 * The SDK shim records each requested detour. Calls below dispatch through the
 * recorded chain; this does not install a machine-code hook or launch the game. */
#define WIN32_LEAN_AND_MEAN
#define HF_MOD_LOADER
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include "hellforge_mod.h"

typedef struct lua_State lua_State;
__declspec(dllimport) lua_State *luaL_newstate(void);
__declspec(dllimport) void luaL_openlibs(lua_State *);
__declspec(dllimport) int luaL_loadfile(lua_State *, const char *);
__declspec(dllimport) int luaL_loadstring(lua_State *, const char *);
__declspec(dllimport) int lua_pcall(lua_State *, int, int, int);
__declspec(dllimport) void lua_close(lua_State *);
__declspec(dllimport) const char *lua_tolstring(lua_State *, int, size_t *);
__declspec(dllimport) void lua_getfield(lua_State *, int, const char *);
__declspec(dllimport) void lua_pushnumber(lua_State *, double);
__declspec(dllimport) int lua_gettop(lua_State *);

__declspec(dllimport) void lua_settop(lua_State *, int);
__declspec(dllimport) int lua_type(lua_State *, int);

static int (*dispatch)(lua_State *, int, int, int);
static void (*close_state)(lua_State *);
static HfTickCallback tick;
static void *tick_user;
static int attaches;

static void fail(const char *why) { fprintf(stderr, "stage VM: %s\n", why); exit(1); }
static void log_line(HfMod *mod, const char *format, ...)
{
    char line[512];
    va_list ap;
    va_start(ap, format);
    vsnprintf(line, sizeof line, format, ap);
    va_end(ap);
    puts(line);
    if (strstr(line, "Private HUD attached to engine update")) ++attaches;
}
static int listen(HfMod *mod, HfEvent event, HfEventCallback cb, void *user)
{
    if (event != HF_EVENT_GAME_LOADED) return 1;
    cb(mod, event, user);
    return 0;
}
static int on_tick(HfMod *mod, HfTickCallback cb, void *user) { tick = cb; tick_user = user; return 1; }
static const char *build(void) { return "25480438"; }
static uintptr_t base(const char *name, size_t *size) { if (size) *size = 0; return 0; }
static int hook(HfMod *mod, uintptr_t target, void *detour, void **original)
{
    HMODULE vm = GetModuleHandleA("lua51.dll");
    if (target == (uintptr_t)GetProcAddress(vm, "lua_pcall") && !dispatch) dispatch = detour;
    else if (target == (uintptr_t)GetProcAddress(vm, "lua_close") && !close_state) close_state = detour;
    else return 1;
    *original = (void *)target;
    return 0;
}
static void checked(lua_State *L, int status)
{
    if (status) fail(lua_tolstring(L, -1, NULL));
}
static void script(lua_State *L, const char *body)
{
    checked(L, luaL_loadstring(L, body));
    checked(L, dispatch(L, 0, 0, 0));
}
int main(int argc, char **argv)
{
    if (!freopen("vm-stage.log", "w", stdout)) return 1;
    if (!freopen("vm-error.log", "w", stderr)) return 1;
    setvbuf(stdout, NULL, _IONBF, 0);
    if (!SetEnvironmentVariableA("LOCALAPPDATA", ".")) fail("could not isolate DBF settings");
    if (!LoadLibraryA("./hellforge_modloader.dll")) fail("could not load SDK bridge stub");
    HMODULE dll = LoadLibraryA("./divers_best_friend.dll");
    int (*init)(const HfApi *, HfMod *) = (void *)GetProcAddress(dll, "hellforge_mod_init");
    HfApi api = {.size = sizeof api, .version = HF_MOD_SDK_VERSION, .log = log_line, .on = listen,
                 .on_game_thread = on_tick, .module_base = base, .build_id = build, .hook = hook};
    int handle;
    HfMod *mod = (void *)&handle;
    if (!init || init(&api, mod) || !tick) fail("DBF initialization failed");
    tick(mod, 1.f/60, tick_user);
    if (!dispatch || !close_state) fail("missing production VM hook");
    for (int cycle = 0; cycle < 2; ++cycle) {
        lua_State *L = luaL_newstate();
        if (!L) fail("VM creation failed");
        luaL_openlibs(L);
        script(L, "stingray={Application={worlds=function() return {} end}, Gui={}}; "
                  "frames=0; function update(dt) assert(dt>0); frames=frames+1; return nil, 'stock result' end; function shutdown() end");
        if (argc > 1) {
            checked(L, luaL_loadfile(L, argv[1]));
            checked(L, dispatch(L, 0, 0, 0));
        }
        script(L, "original_update=update; assert(not DBF_HellForge_HUD_Owner)");
        for (int frame = 0; frame < 3; ++frame) {
            tick(mod, 1.f/60, tick_user);
            lua_getfield(L, -10002, "update");
            lua_pushnumber(L, 1.0/60);
            checked(L, dispatch(L, 1, -1, 0));
            if (lua_gettop(L) != 2 || lua_type(L, 1) != 0 ||
                lua_type(L, 2) != 4 || strcmp(lua_tolstring(L, 2, NULL), "stock result"))
                fail("DBF changed the original update results");
            lua_settop(L, 0);
            if (!frame)
                script(L, "local r=assert(DBF_HellForge_HUD_Owner); local prev=r.on_update; dbf_frames=0; "
                          "r.on_update=function(dt) dbf_frames=dbf_frames+1; return prev(dt) end");
            script(L, "assert(DBF_HellForge_HUD_Owner and original_update==update); "
                      "owner=owner or DBF_HellForge_HUD_Owner; assert(owner==DBF_HellForge_HUD_Owner)");
        }
        script(L, "assert(frames==3 and dbf_frames==2); if dbf_test_after_frames then dbf_test_after_frames() end");
        if (!cycle) {
            lua_getfield(L, -10002, "shutdown");
            checked(L, dispatch(L, 0, -1, 0));
            script(L, "assert(not DBF_HellForge_HUD_Owner)");
        }
        close_state(L);
    }
    if (attaches != 2) fail("expected one DBF attachment per VM lifetime");
    puts("PASS staged HUD VM: one production attachment per VM, 2 VM lifetimes, 6 chained updates");
    return 0;
}
