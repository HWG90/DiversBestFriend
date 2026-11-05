/* wine_modloader_stub: a stand-in hellforge_modloader.dll for the Wine test (tests/wine_host.c). It exports
 * hellforge_lua_rewrites, as HellForge's loader does, answering 1 for the game.dll RVAs the host names with
 * stub_set_rewritten and stub_add_rewritten and counting the questions, so the host can prove DBF's admission asks it about
 * the witness bytes it compares. Windows only; for the Wine test only.
 *
 * The function is defined against the SDK's own prototype (hellforge_lua.h, with HF_LUA_API as the dllexport the loader
 * builds it with: build.sh passes -DHF_LUA_API=__declspec(dllexport)), so a prototype that changes in the SDK, or a stub
 * that drifts from it, does not compile; and DBF's pointer type for the function comes from the same declaration. */
#define HF_MOD_LOADER /* this is the loader: hellforge_mod.h does not declare a mod's init here */
#include <stdint.h>
#include "hellforge_lua.h"

#ifndef HF_LUA_API
#error "build with -DHF_LUA_API=__declspec(dllexport): the loader's exports are what the stub imitates"
#endif

#define EXPORT __declspec(dllexport)
#define MAX_RVAS 8

static uint32_t g_rva[MAX_RVAS];
static int g_count;
static int g_calls;

int hellforge_lua_rewrites(uint32_t rva, uint32_t size) /* exported through the SDK's declaration */
{
    g_calls++;
    for (int i = 0; i < g_count; i++)
        if (g_rva[i] >= rva && g_rva[i] - rva < size) return 1;
    return 0;
}

/* Replaces the list with this one RVA. */
EXPORT void stub_set_rewritten(uint32_t rva)
{
    g_rva[0] = rva;
    g_count = 1;
}

/* Adds an RVA to the list (up to MAX_RVAS). */
EXPORT void stub_add_rewritten(uint32_t rva)
{
    if (g_count < MAX_RVAS) g_rva[g_count++] = rva;
}

EXPORT int stub_rewrite_calls(void) { return g_calls; }
