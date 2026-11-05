/* wine_overlay_stub: a stand-in Goose Overlay Host for the Wine test (tests/wine_host.c), built by build.sh wine-test as
 * goose_overlay.dll once per API version (STUB_API 3, 4 or 5), each in a folder of its own.
 *
 * Its ov_api(version) serves the stub's table when `version` is at most STUB_API, else NULL, as the real host does:
 *   3  an Overlay Host older than 0.2.0: DBF must get no API from it (it asks for 4)
 *   4  Overlay Host 0.2.x: the API without on_game_thread (size stops before it; the field is NULL)
 *   5  Overlay Host 0.3.x: on_game_thread stores the callback and returns 1
 * register_panel copies the definition it is given and returns a non-NULL handle. The draw calls are tests/fake_ov.c's,
 * which write down what was drawn; every other function is NULL, so a mod calling one crashes the test loudly.
 *
 * The exports below let the host see what the mod asked for and drive what the real host would drive: the game-thread
 * callbacks (stub_tick, as the host's own HellForge slot runs them) and a panel's draw (stub_draw, as the render thread
 * does). stub_refuse_panels(1) makes register_panel return NULL and keep nothing, as the real host does when it takes no
 * window; stub_register_calls counts the calls either way. Windows only; for the Wine test only. */
#ifndef DBF_WINE_OVERLAY_STUB_H
#define DBF_WINE_OVERLAY_STUB_H

#include <stdint.h>
#include "goose_overlay.h"

#define STUB_TEXT 128

/* A registered panel as the stub copied it. */
typedef struct StubPanel {
    uint32_t size;
    char id[STUB_TEXT];
    char title[STUB_TEXT];
    uint32_t kind, hotkey, window_flags;
    float width, height;
    OvDrawFn draw;
    void* user;
} StubPanel;

typedef int (*StubCountFn)(void);                     /* stub_requests, stub_panel_count, stub_register_calls,
                                                         stub_game_thread_count, stub_line_count, stub_open, stub_misuse */
typedef void (*StubSwitchFn)(int on);                 /* stub_refuse_panels */
typedef const StubPanel* (*StubPanelFn)(int index);   /* stub_panel: NULL out of range */
typedef void (*StubTickFn)(float dt);                 /* stub_tick: runs every stored game-thread callback once */
typedef int (*StubDrawFn)(int index);                 /* stub_draw: clears the drawing log, draws panel `index`;
                                                         0 when there is no such panel */
typedef const char* (*StubLineFn)(int index);         /* stub_line: a line of the drawing log, NULL out of range */
typedef int (*StubTextFn)(const char* text);          /* stub_count_prefix */

#endif
