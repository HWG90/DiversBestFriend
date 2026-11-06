#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>
#include "dbf_vm_win.h"
#include "dbf_hud_payload.h"
#include "hud_bridge.h"

typedef struct lua_State State;
typedef int (*LuaFn)(State*);
typedef int (*Pcall)(State*, int, int, int);
typedef void (*Close)(State*);
enum { REGISTRY = -10000, GLOBALS = -10002, NIL = 0, NUMBER = 3, TABLE = 5, FUNCTION = 6 };

static struct {
    int (*gettop)(State*);
    void (*settop)(State*, int);
    int (*type)(State*, int);
    double (*tonumber)(State*, int);
    int (*toboolean)(State*, int);
    void* (*touserdata)(State*, int);
    State* (*tothread)(State*, int);
    const void* (*topointer)(State*, int);
    const char* (*tolstring)(State*, int, size_t*);
    int (*checkstack)(State*, int);
    int (*pushthread)(State*);
    void (*pushlightuserdata)(State*, void*);
    void (*pushvalue)(State*, int);
    void (*pushstring)(State*, const char*);
    void (*pushnumber)(State*, double);
    void (*pushboolean)(State*, int);
    void (*rawget)(State*, int);
    void (*rawset)(State*, int);
    void (*call)(State*, int, int);
    int (*cpcall)(State*, LuaFn, void*);
    int (*loadbuffer)(State*, const char*, size_t, const char*);
} api;

static const HfApi* host;
static HfMod* mod;
/* The SDK may rewrite these slots when a later hook joins the chain. */
static Pcall volatile next_pcall;
static Close volatile next_close;
static volatile LONG game_thread, armed;
static PVOID volatile registry_id; /* identity only, never dereferenced */
static char record_key, main_key;
static bool busy, stopping;        /* used only by the game thread */
static ULONGLONG retry_at;

static void note(const char* message) { host->log(mod, "%s", message); }

static void field(State* L, int index, const char* key)
{
    api.pushstring(L, key);
    api.rawget(L, index < 0 && index > REGISTRY ? index - 1 : index);
}

static void get_private(State* L, void* key)
{
    api.pushlightuserdata(L, key);
    api.rawget(L, REGISTRY);
}

static void set_private(State* L, void* key, int value)
{
    api.pushlightuserdata(L, key);
    api.pushvalue(L, value < 0 ? value - 1 : value);
    api.rawset(L, REGISTRY);
}

static void* owner(void)
{
    return InterlockedCompareExchangePointer(&registry_id, NULL, NULL);
}

typedef struct { const void* function; bool shutdown, matches; } Probe;

static int match_callback(State* L)
{
    Probe* probe = api.touserdata(L, 1);
    if (!api.pushthread(L)) return 0; /* a coroutine shares its VM's globals */
    field(L, GLOBALS, probe->shutdown ? "shutdown" : "update");
    if (api.topointer(L, -1) != probe->function) return 0;
    void* active = owner();
    if (active && active != api.topointer(L, REGISTRY)) return 0;
    if (!active) {
        if (probe->shutdown) return 0;
        get_private(L, &record_key);
        if (api.type(L, -1) != NIL) return 0; /* retired or owned elsewhere */
        field(L, GLOBALS, "stingray");
        if (api.type(L, -1) != TABLE) return 0;
        field(L, -1, "Gui");
        if (api.type(L, -1) != TABLE) return 0;
        api.settop(L, api.gettop(L) - 1);
        field(L, -1, "Application");
        if (api.type(L, -1) != TABLE) return 0;
        field(L, -1, "worlds");
        if (api.type(L, -1) != FUNCTION) return 0;
    }
    probe->matches = true;
    return 0;
}

static void retire(State* L)
{
    api.pushboolean(L, 0);
    set_private(L, &record_key, -1);
    InterlockedExchangePointer(&registry_id, NULL);
    stopping = false;
}

static int disable_record(State* L)
{
    get_private(L, &record_key);
    if (api.type(L, -1) == TABLE) {
        field(L, -1, "on_disable");
        api.call(L, 0, 1);
        if (!api.toboolean(L, -1)) return 0; /* retry on subsequent frame or close */
    }
    retire(L);
    return 0;
}

static int drive_frame(State* L)
{
    double dt = *(double*)api.touserdata(L, 1);
    if (owner() && stopping) return disable_record(L);
    get_private(L, &record_key);
    if (api.type(L, -1) == NIL) {
        field(L, GLOBALS, "DBF_HellForge_HUD_Owner");
        if (api.type(L, -1) != NIL) {
            retire(L); /* another DBF record already runs this VM */
            note("Private HUD yielded to existing DBF owner");
            return 0;
        }
        if (api.loadbuffer(L, dbf_hud_payload, sizeof dbf_hud_payload, "@DBF/private_hud")) {
            const char* why = api.tolstring(L, -1, NULL);
            note(why ? why : "Private HUD chunk refused");
            retire(L);
            return 0;
        }
        api.call(L, 0, 1);
        field(L, -1, "on_enable");
        api.call(L, 0, 0);
        set_private(L, &record_key, -1);
        api.pushthread(L);
        set_private(L, &main_key, -1);
        api.settop(L, api.gettop(L) - 1);
        stopping = false;
        InterlockedExchangePointer(&registry_id, (PVOID)api.topointer(L, REGISTRY));
        note("Private HUD attached to engine update");
    }
    field(L, -1, "on_update");
    api.pushnumber(L, dt);
    api.call(L, 1, 0);
    return 0;
}

/* All Lua that can raise runs inside lua_cpcall. Restore the engine caller's
 * exact stack, including nil holes, error objects and multiple return values. */
static bool protected_call(State* L, LuaFn fn, void* arg)
{
    int top = api.gettop(L);
    int error = api.cpcall(L, fn, arg);
    if (error) {
        const char* why = api.type(L, -1) == 4 ? api.tolstring(L, -1, NULL) : NULL;
        note(why ? why : "Private HUD protected call failed");
        retry_at = GetTickCount64() + 1000;
    }
    api.settop(L, top);
    return !error;
}

static int pcall_hook(State* L, int args, int results, int error_fn)
{
    /* 25480438: EXE+689b6e pushes dt; +689b98 calls the named dispatcher,
     * which rawgets global update and calls lua_pcall(L,1,LUA_MULTRET,0)
     * through +1c579c. Identify the Lua function, not a native return address:
     * other SDK hook-chain members can legitimately be between us and the EXE. */
    if (!InterlockedCompareExchange(&armed, 0, 0) ||
        GetCurrentThreadId() != (DWORD)InterlockedCompareExchange(&game_thread, 0, 0) ||
        busy || error_fn || (args != 0 && args != 1) || results != -1)
        return next_pcall(L, args, results, error_fn);
    bool shutdown = args == 0;
    if ((shutdown && !owner()) || (!shutdown && api.type(L, -1) != NUMBER) ||
        api.type(L, -1 - args) != FUNCTION || (!shutdown && GetTickCount64() < retry_at))
        return next_pcall(L, args, results, error_fn);
    double dt = shutdown ? 0 : api.tonumber(L, -1);
    Probe probe = { .function = api.topointer(L, -1 - args), .shutdown = shutdown };
    busy = true;
    protected_call(L, match_callback, &probe);
    if (!probe.matches) {
        busy = false;
        return next_pcall(L, args, results, error_fn);
    }
    if (shutdown) {
        stopping = true;
        protected_call(L, disable_record, NULL);
    }
    int status = next_pcall(L, args, results, error_fn);
    if (!shutdown && status == 0) {
        hud_bridge_vm_context(api.topointer(L, REGISTRY));
        protected_call(L, drive_frame, &dt);
        hud_bridge_vm_context(NULL);
    }
    busy = false;
    return status;
}

static void close_hook(State* L)
{
    void* id = owner();
    if (id && id == api.topointer(L, REGISTRY)) {
        /* lua_close(coroutine) closes its entire VM. Resolve the main thread
         * from this still-live registry, never from a cached lua_State*. */
        if (GetCurrentThreadId() == (DWORD)InterlockedCompareExchange(&game_thread, 0, 0) &&
            !busy && api.checkstack(L, 2)) {
            int top = api.gettop(L);
            get_private(L, &main_key);
            State* main = api.tothread(L, -1);
            api.settop(L, top);
            busy = true;
            if (main) protected_call(main, disable_record, NULL);
            busy = false;
        }
        if (owner() == id) {
            hud_bridge_vm_lost(id);
            InterlockedCompareExchangePointer(&registry_id, NULL, id);
            note("Private HUD VM closed before orderly cleanup");
        }
    }
    next_close(L);
}

static bool install(const HfApi* hf, HfMod* m, HMODULE lua)
{
    host = hf;
    mod = m;
#define RESOLVE(member, symbol) do { \
    FARPROC proc = GetProcAddress(lua, symbol); \
    if (!proc) return false; \
    memcpy(&api.member, &proc, sizeof proc); \
} while (0)
    RESOLVE(gettop, "lua_gettop"); RESOLVE(settop, "lua_settop");
    RESOLVE(type, "lua_type"); RESOLVE(tonumber, "lua_tonumber");
    RESOLVE(toboolean, "lua_toboolean"); RESOLVE(topointer, "lua_topointer");
    RESOLVE(touserdata, "lua_touserdata"); RESOLVE(tothread, "lua_tothread");
    RESOLVE(tolstring, "lua_tolstring"); RESOLVE(checkstack, "lua_checkstack");
    RESOLVE(pushthread, "lua_pushthread"); RESOLVE(pushvalue, "lua_pushvalue");
    RESOLVE(pushlightuserdata, "lua_pushlightuserdata"); RESOLVE(pushstring, "lua_pushstring");
    RESOLVE(pushnumber, "lua_pushnumber"); RESOLVE(pushboolean, "lua_pushboolean");
    RESOLVE(rawget, "lua_rawget"); RESOLVE(rawset, "lua_rawset");
    RESOLVE(call, "lua_call"); RESOLVE(cpcall, "lua_cpcall"); RESOLVE(loadbuffer, "luaL_loadbuffer");
#undef RESOLVE
    FARPROC close = GetProcAddress(lua, "lua_close"), call = GetProcAddress(lua, "lua_pcall");
    if (!call || !close || !hf->hook) return false;
    if (!next_close && hf->hook(m, (uintptr_t)close, (void*)close_hook, (void**)&next_close)) return false;
    if (!next_close) return false;
    if (!next_pcall && hf->hook(m, (uintptr_t)call, (void*)pcall_hook, (void**)&next_pcall)) return false;
    return next_pcall != NULL;
}

void dbf_vm_tick(const HfApi* hf, HfMod* m)
{
    static ULONGLONG next_try;
    static bool warned;
    InterlockedExchange(&game_thread, (LONG)GetCurrentThreadId());
    if (InterlockedCompareExchange(&armed, 0, 0)) return;
    ULONGLONG now = GetTickCount64();
    if (now < next_try) return;
    next_try = now + 1000;
    HMODULE lua = GetModuleHandleW(L"lua51.dll");
    if (!lua) return;
    if (install(hf, m, lua)) {
        InterlockedExchange(&armed, 1);
        note("Private HUD waiting for the engine update");
    } else if (!warned) {
        warned = true;
        hf->log(m, "Private HUD VM hooks unavailable; retrying");
    }
}
#endif
