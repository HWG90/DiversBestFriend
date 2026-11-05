/* wine_overlay_stub: see wine_overlay_stub.h. Built with -DSTUB_API=3, 4 or 5 and tests/fake_ov.c. */
#define Goose_OVERLAY_HOST /* goose_overlay.h then declares ov_api as this DLL's export */
#include <stddef.h>
#include <string.h>
#include "fake_ov.h"
#include "wine_overlay_stub.h"

#ifndef STUB_API
#error "build with -DSTUB_API=3, 4 or 5"
#endif
_Static_assert(STUB_API >= 3 && (STUB_API <= 5 || STUB_API == 8), "STUB_API is 3, 4 or 5");

#define EXPORT __declspec(dllexport)
#define MAX_PANELS 8
#define MAX_TICKS 8

static OvApi g_table;
static int g_ready;
static int g_requests;
static int g_register_calls;
static int g_refuse_panels;
static int g_capturing = -1; /* stub_set_capturing: -1 by the panel's kind */

static StubPanel g_panels[MAX_PANELS];
static int g_panel_count;

typedef struct Ticker {
    struct HfMod* mod;
    OvTickFn callback;
    void* user;
} Ticker;
static Ticker g_ticks[MAX_TICKS];
static int g_tick_count;

static void copy_text(char* dst, const char* src)
{
    size_t n = src ? strlen(src) : 0;
    if (n >= STUB_TEXT) n = STUB_TEXT - 1;
    if (n) memcpy(dst, src, n);
    dst[n] = '\0';
}

static OvPanel* stub_register_panel(const OvPanelDef* def)
{
    StubPanel* p;
    g_register_calls++;
    if (def == NULL || g_refuse_panels || g_panel_count >= MAX_PANELS) return NULL;
    p = &g_panels[g_panel_count++];
    p->size = def->size;
    copy_text(p->id, def->id);
    copy_text(p->title, def->title);
    p->kind = def->kind;
    p->hotkey = def->hotkey;
    p->window_flags = def->window_flags;
    p->width = def->width;
    p->height = def->height;
    p->draw = def->draw;
    p->user = def->user;
    return (OvPanel*)p;
}

#if STUB_API >= 5
static int stub_on_game_thread(struct HfMod* mod, OvTickFn callback, void* user)
{
    if (callback == NULL || g_tick_count >= MAX_TICKS) return 0;
    g_ticks[g_tick_count].mod = mod;
    g_ticks[g_tick_count].callback = callback;
    g_ticks[g_tick_count].user = user;
    g_tick_count++;
    return 1;
}
#endif

#if STUB_API >= 8
static int stub_input_captured(void) { return g_capturing > 0; }
#endif

EXPORT const OvApi* ov_api(uint32_t version)
{
    g_requests++;
    if (!g_ready) {
        g_table = *fake_ov_api(); /* the drawing calls; everything else stays NULL */
        g_table.version = STUB_API;
        g_table.register_panel = stub_register_panel;
#if STUB_API >= 8
        g_table.input_captured = stub_input_captured;
#endif
#if STUB_API >= 5
        g_table.size = sizeof(OvApi);
        g_table.on_game_thread = stub_on_game_thread;
#else
        g_table.size = offsetof(OvApi, on_game_thread); /* an API 4 (or older) table ends before on_game_thread */
        g_table.on_game_thread = NULL;
#endif
        g_ready = 1;
    }
    return version <= STUB_API ? &g_table : NULL;
}

EXPORT int stub_requests(void) { return g_requests; }
EXPORT int stub_panel_count(void) { return g_panel_count; }
EXPORT int stub_register_calls(void) { return g_register_calls; }
EXPORT void stub_refuse_panels(int on) { g_refuse_panels = on; }
EXPORT const StubPanel* stub_panel(int index) { return index >= 0 && index < g_panel_count ? &g_panels[index] : NULL; }
EXPORT int stub_game_thread_count(void) { return g_tick_count; }

EXPORT void stub_tick(float dt)
{
    for (int i = 0; i < g_tick_count; i++) g_ticks[i].callback(g_ticks[i].mod, dt, g_ticks[i].user);
}

EXPORT int stub_draw(int index)
{
    const StubPanel* p = stub_panel(index);
    /* An open window has the game's input (OvFrame.capturing); a HUD panel is drawn while no window is open. */
    OvFrame frame = { 3840.0f, 2160.0f, 1.0f / 60.0f, 1.0, 2.0f, 1 };
    if (p == NULL || p->draw == NULL) return 0;
    frame.capturing = g_capturing >= 0 ? g_capturing : p->kind == OV_PANEL_WINDOW;
    fake_ov_reset();
    p->draw(&frame, p->user);
    return 1;
}

/* The frames stub_draw passes say capturing (1) or not (0) whatever the panel; -1 goes back to the panel's kind. */
EXPORT void stub_set_capturing(int capturing) { g_capturing = capturing; }

EXPORT int stub_line_count(void) { return fake_ov_lines(); }
EXPORT const char* stub_line(int index) { return fake_ov_line(index); }
EXPORT int stub_count_prefix(const char* prefix) { return fake_ov_count_prefix(prefix); }
EXPORT int stub_open(void) { return fake_ov_open(); }
EXPORT int stub_misuse(void) { return fake_ov_misuse(); }
