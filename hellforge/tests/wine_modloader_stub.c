/* wine_modloader_stub: a stand-in hellforge_modloader.dll for the Wine test (tests/wine_host.c). It exports
 * hellforge_lua_rewrites, as HellForge's loader does, answering 1 for a question about a span that holds a game.dll RVA the
 * host names with stub_set_rewritten and stub_add_rewritten, or that overlaps a range it names with stub_add_range (the
 * host's 12-byte stubs at the game functions DBF calls, reported as HellForge reports its hooks), and counting the
 * questions, so the host can prove DBF's admission asks it about the witness bytes it compares. stub_code_area is room
 * inside this DLL's own image, where the host puts a HellForge mod stratagem's code array, as HellForge keeps one in its
 * loader's image. Windows only; for the Wine test only.
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
#define MAX_RANGES 8
#define CODE_AREA 256

static uint32_t g_rva[MAX_RVAS];
static int g_count;
static uint32_t g_range_at[MAX_RANGES], g_range_size[MAX_RANGES];
static int g_ranges;
static int g_calls, g_byte_calls;
static uint64_t g_code_area[CODE_AREA / 8] = { 1 }; /* in the image's data, 8-aligned; its bytes are the host's */

int hellforge_lua_rewrites(uint32_t rva, uint32_t size) /* exported through the SDK's declaration */
{
    g_calls++;
    if (size == 1) g_byte_calls++;
    for (int i = 0; i < g_count; i++)
        if (g_rva[i] >= rva && g_rva[i] - rva < size) return 1;
    for (int i = 0; i < g_ranges; i++)
        if ((uint64_t)rva < (uint64_t)g_range_at[i] + g_range_size[i] && (uint64_t)rva + size > g_range_at[i]) return 1;
    return 0;
}

/* Adds the range [rva, rva + size) (up to MAX_RANGES). */
EXPORT void stub_add_range(uint32_t rva, uint32_t size)
{
    if (g_ranges < MAX_RANGES) {
        g_range_at[g_ranges] = rva;
        g_range_size[g_ranges] = size;
        g_ranges++;
    }
}

/* Questions about a single byte (size 1). */
EXPORT int stub_byte_calls(void) { return g_byte_calls; }

/* Room inside this DLL's image: its address, and its size in *size. */
EXPORT void* stub_code_area(uint32_t* size)
{
    if (size) *size = CODE_AREA;
    return g_code_area;
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
