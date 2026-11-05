/* wine_modloader_stub: a stand-in hellforge_modloader.dll for the Wine test (tests/wine_host.c). It exports
 * hellforge_lua_rewrites, as HellForge's loader does (hellforge_lua.h), answering 1 for the one game.dll RVA the host
 * names with stub_set_rewritten and counting the questions, so the host can prove DBF's admission asks it about a
 * witness byte that differs. Windows only; for the Wine test only. */
#include <stdint.h>

#define EXPORT __declspec(dllexport)

static uint32_t g_rva = 0xffffffffu;
static int g_calls;

EXPORT int hellforge_lua_rewrites(uint32_t rva, uint32_t size)
{
    g_calls++;
    return g_rva >= rva && g_rva - rva < size;
}

EXPORT void stub_set_rewritten(uint32_t rva) { g_rva = rva; }
EXPORT int stub_rewrite_calls(void) { return g_calls; }
