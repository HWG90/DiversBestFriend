/* The real divers_best_friend.dll under Wine, loaded by a stand-in HellForge, as the Overlay Host tests itself
 * (overlay-host/test/host_test.cpp). build.sh wine-test builds this host, the stub Overlay Hosts of
 * tests/wine_overlay_stub.c and the stub loader export of tests/wine_modloader_stub.c, and runs one case per process (the
 * DLL keeps static state).
 *
 * The stand-in HfApi: log writes the line down, on keeps the listeners (HF_EVENT_GAME_LOADED is fired by hand),
 * on_game_thread keeps the callback and returns 1, module_base serves the synthetic 25480438 image of tests/synthetic.c
 * (game.dll and a minimal helldivers2.exe, both with 25480438's stamps, the image carrying the generated witness table,
 * the one the DLL is built with), read and read_code read that image and fail outside it, write refuses (and is counted:
 * the mod must write nothing). The rest of the HfApi is NULL: a mod calling it crashes the case.
 *
 * Cases (the second argument):
 *   no-host        no goose_overlay.dll loaded
 *   host-api3      a stub host older than 0.2.0: its ov_api serves nothing above 3
 *   host-api4      a stub Overlay Host 0.2.x: API 4, no on_game_thread
 *   host-api5      a stub Overlay Host 0.3.x: API 5 with on_game_thread; with a stub hellforge_modloader.dll whose
 *                  hellforge_lua_rewrites covers one witness byte the host changes
 *   no-tick        the API 4 stub, and HellForge refuses the game-thread slot: DBF logs it and stops (no window)
 *   retry          the API 4 stub; a witness byte is changed before the first tick (the features it gates wait), put back,
 *                  and a tick 1.1 s later admits them: admission retries once a second
 *   on-at-once     the API 4 stub; the stand-in `on` delivers HF_EVENT_GAME_LOADED before it returns, as a loader that has
 *                  already seen the game load might: the version line comes first and the window registers once
 *   late-module    the API 4 stub; module_base serves nothing on the first tick: that tick only publishes "game.dll not
 *                  loaded yet" and reads nothing, and admission starts (logging it, once) on the second
 *   second-loaded  the API 4 stub; HF_EVENT_GAME_LOADED comes three times: one window, one tick, one line saying so
 *   null-panel     the API 4 stub, whose register_panel returns NULL: DBF logs it and keeps ticking
 *   on-fails       the API 4 stub, and HellForge refuses the listener (hf->on fails): DBF logs it and registers nothing
 *   masked-log     the API 4 stub and a stub loader that rewrites several witness bytes, two witnesses' worth: the count
 *                  of masked bytes of each is logged once, however often the witness is read again
 * The code-entry cases (Plan 2, Task 12), with the API 8 stub host and the stub loader (old-host-input: API 5; no-host-entry: the loader
 * alone), a settings.ini in a LOCALAPPDATA of their own, a writable image (hf->write writes into pages that exist), a
 * window of this process in front and DBF's keys pressed with keybd_event (F20 slot 1, F21 Next, F22 Previous, F23
 * Confirm), as a player would:
 *   list-confirm   menu open, Next once, Confirm: the fake handler gets the second row's code, paced 60 ms, the job is done,
 *                  the action bytes are 0, the move and confirm sounds played; the selected native card is enlarged
 *   instant        instant_stratagems: every direction but the last at once, the last once Confirm was up 100 ms
 *   menu-close     the game closes the menu after the first direction: failed, "menu closed", bytes 0, nothing left
 *   mission-end    the mission ends after the first direction: "the mission ended", bytes 0, nothing left
 *   shortcut       slot 1 from a closed menu: the latch, open and request_slot, the code, and the latch back once the
 *                  game closes the menu
 *   shortcut-hud   the HUD is replaced during a slot hotkey: cancelled ("the HUD changed"), the latch back, the menu DBF
 *                  opened closed
 *   mod-stratagem  a HellForge kind 151 (moved table, its code array inside the stub loader's own image) is entered
 *   scramble       the fake scramble query answers with an effect: the remapped kind's code is entered
 *   no-entry-admission  an ENTRY witness byte differs: Confirm sends nothing, and the Status tab says why
 *   old-host-input  API 5 registers a settings window but blocks Next and Confirm without a capture query
 *   no-host-entry  no Overlay Host: the keys still work and the code is entered; one log line says what is missing
 *   release-retry  the write that releases the first direction fails: the job fails, and the next tick puts it back
 *   card-gone      the stratagem's card turns unavailable during a code: "card membership changed" (R46)
 *   shortcut-blocked  a host window takes the input during a slot hotkey: cancelled, the latch back, the menu closed
 *   latch-retry    a latch release cannot be written, once after a refused slot hotkey (the tick retries it for the
 *                  latch's own player) and once after a done one with the player respawned (the old actions dword is
 *                  left alone)
 * Every case maps the synthetic game.dll's code pages into executable memory with a 12-byte stub (mov rax, imm64;
 * jmp rax) at each DBF_FN_* RVA, jumping to a C fake here (the input handler, open, close and request_slot over
 * tests/synthetic.c's fakes; the UI sound and the scramble query recorded). The stub's bytes are in the synthetic image
 * too (except the scale and RGB setters, modelled as native implementations with intact witnesses), so hf->read sees them as it would see a hook; read_code serves the original bytes from a shadow copy, as
 * HellForge's does, and in the code-entry cases the stub loader reports the stub ranges through
 * hellforge_lua_rewrites, as HellForge reports its hooks. The cases from no-host to masked-log may update card graphics but must send no gameplay input or sounds.
 * Checks of the first five: init returns 0, logs the version line, registers for HF_EVENT_GAME_LOADED and nothing else.
 * After the event: without a usable host (no-host, host-api3) the "running without a settings window" line, exactly once even after 3
 * ticks, and the tick on HellForge's on_game_thread; with one, one register_panel call for the Status window (id, title,
 * kind, hotkey F7, 640x520), the tick on the host's on_game_thread when it has one (API 5) and HellForge's otherwise, the
 * window drawing "starting" before the first tick, the menu open after the first, and, after 3 ticks (the menu closed in
 * the game before the last), the last published snapshot as the Status tab draws it: build OK, the three read features OK,
 * in a mission, the menu closed, no reader reason, four rows with the scene's names and codes. The snapshot is read as a
 * player sees it: the stub host calls the window's draw callback into tests/fake_ov.c's recording OvApi, so the DLL needs
 * no export for the test (and the host could not link the snapshot accessors: the DLL's snapshot lives in the DLL's own
 * statics).
 *
 * Usage: wine_host.exe <divers_best_friend.dll> <case> [<goose_overlay.dll>] [<hellforge_modloader.dll>] (each when the
 * case needs it) */
#define WIN32_LEAN_AND_MEAN
#define HF_MOD_LOADER /* this is the loader: hellforge_mod.h does not declare the mod's init here */
#include <windows.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "hellforge_mod.h"
#define DBF_ADDRESSES_DEFINE /* the generated witness table, as the DLL has it: the synthetic image carries its bytes */
#include "addresses_25480438.h"
#include "kind_names_25480438.h"
#include "synthetic.h"
#include "test.h"
#include "wine_overlay_stub.h"

#define VERSION_LINE "Diver's Best Friend R50-hellforge.10 (game 25480438)"
#define NO_HOST_LINE "No Overlay Host 0.2.0 or later: running without a settings window; key and controller " \
                     "bindings still work, wheel bindings do nothing"
#define NO_TICK_LINE "Diver's Best Friend could not get a game-thread tick"
#define NO_PANEL_LINE "The Overlay Host did not take the Diver's Best Friend window (its log says why)"
#define LISTEN_FAILED_LINE "Diver's Best Friend could not listen for the game loading"
#define REPEATED_LINE "Diver's Best Friend ignored a repeated game-loaded event"
#define ADMISSION_LINE "game.dll found; admission starts"
#define REWRITES_FOUND_LINE "Admission skips the code HellForge rewrites (hellforge_lua_rewrites found)"
#define REWRITES_MISSING_LINE "No hellforge_lua_rewrites in hellforge_modloader.dll: admission compares every witness byte"
#define MASKED_TAIL " bytes rewritten by HellForge" /* every masked-witness line ends like this */
#define STARTING_TEXT "text:Diver's Best Friend is starting..."
#define PANEL_ID "goose.divers-best-friend"
#define PANEL_TITLE "Diver's Best Friend"
#define TICKS 3
#define MENU_OPEN_AT 0x38769u /* the menu-open byte in the stratagem panel (R46 native.lua:214), as tests/synthetic.c */
#define RETRY_WAIT_MS 1100u   /* admission retries what is pending once a second */
#define MAX_LINES 2048
#define LINE_SIZE 512
#define MAX_LISTENERS 16
#define MAX_TICKERS 8

struct HfMod { const char* id; }; /* opaque to mods; the loader's own */
static struct HfMod g_mod = { "goose.divers-best-friend" };

/* --- the stand-in HfApi ---------------------------------------------------------------------------------------- */

static char g_lines[MAX_LINES][LINE_SIZE];
static int g_line_count;
static char g_last_line[LINE_SIZE]; /* the last line logged, kept however many there were */

static void api_log(HfMod* mod, const char* format, ...)
{
    char line[LINE_SIZE];
    va_list args;
    va_start(args, format);
    vsnprintf(line, sizeof line, format, args);
    va_end(args);
    printf("  [%s] %s\n", mod ? mod->id : "?", line);
    memcpy(g_last_line, line, sizeof line);
    if (g_line_count < MAX_LINES) memcpy(g_lines[g_line_count++], line, sizeof line);
}

static int logged(const char* line)
{
    int n = 0;
    for (int i = 0; i < g_line_count; i++)
        if (strcmp(g_lines[i], line) == 0) n++;
    return n;
}

/* How many logged lines end with `tail`. */
static int logged_ending(const char* tail)
{
    size_t n = strlen(tail);
    int count = 0;
    for (int i = 0; i < g_line_count; i++) {
        size_t length = strlen(g_lines[i]);
        if (length >= n && strcmp(g_lines[i] + length - n, tail) == 0) count++;
    }
    return count;
}

typedef struct Listener {
    HfMod* mod;
    HfEvent event;
    HfEventCallback callback;
    void* user;
} Listener;
static Listener g_listeners[MAX_LISTENERS];
static int g_listener_count;
static int g_on_calls;

static int api_on(HfMod* mod, HfEvent event, HfEventCallback callback, void* user)
{
    g_on_calls++;
    if (g_listener_count >= MAX_LISTENERS) return 1;
    g_listeners[g_listener_count++] = (Listener){ mod, event, callback, user };
    return 0;
}

/* on-at-once: a loader that already saw the game load delivers the event before on returns. What the mod had logged by the
 * time it called on is written down first. */
static int g_version_lines_at_on = -1;
static int api_on_at_once(HfMod* mod, HfEvent event, HfEventCallback callback, void* user)
{
    int result;
    g_version_lines_at_on = logged(VERSION_LINE);
    result = api_on(mod, event, callback, user);
    if (result == 0) callback(mod, event, user);
    return result;
}

/* on-fails: HellForge takes no listener. */
static int api_on_fails(HfMod* mod, HfEvent event, HfEventCallback callback, void* user)
{
    g_on_calls++;
    return 1;
}

static void fire(HfEvent event)
{
    for (int i = 0; i < g_listener_count; i++)
        if (g_listeners[i].event == event) g_listeners[i].callback(g_listeners[i].mod, event, g_listeners[i].user);
}

typedef struct Ticker {
    HfMod* mod;
    HfTickCallback callback;
    void* user;
} Ticker;
static Ticker g_tickers[MAX_TICKERS];
static int g_ticker_count;

static int api_on_game_thread(HfMod* mod, HfTickCallback callback, void* user)
{
    if (callback == NULL || g_ticker_count >= MAX_TICKERS) return 0;
    g_tickers[g_ticker_count++] = (Ticker){ mod, callback, user };
    return 1;
}

/* no-tick: as HellForge's when the game's update could not be hooked. */
static int api_refuse_game_thread(HfMod* mod, HfTickCallback callback, void* user) { return 0; }

static void api_tick(void)
{
    for (int i = 0; i < g_ticker_count; i++) g_tickers[i].callback(g_tickers[i].mod, 1.0f / 60.0f, g_tickers[i].user);
}

static const char* api_build_id(void) { return "25480438"; }
static const char* api_mod_id(HfMod* mod) { return mod->id; }
static const char* api_mod_folder(HfMod* mod) { return "C:\\mods\\divers-best-friend"; }

/* The ticks the host has run, and what the mod asked of the game around them. module_base serves nothing until tick number
 * g_module_from_tick has started (late-module); 0 serves it always. */
static int g_tick_no;
static int g_module_from_tick;
static int g_module_base_calls;
static int g_read_calls;

static uintptr_t api_module_base(const char* module, size_t* size)
{
    g_module_base_calls++;
    if (g_tick_no < g_module_from_tick) return 0;
    return syn_adm_port()->module_base(module, size);
}

static int api_read(uintptr_t address, void* out, size_t size)
{
    g_read_calls++;
    return syn_read(address, out, size);
}

/* hf->write in the code-entry cases: into the image's pages, except the one write g_fail_write names (release-retry). */
static int g_write_no, g_fail_write;
static int api_write(uintptr_t address, const void* data, size_t size)
{
    if (++g_write_no == g_fail_write) return -1;
    return syn_write_mapped(address, data, size);
}

/* --- the game functions: 12-byte stubs in executable memory ----------------------------------------------------- */

#define STUB_BYTES 12 /* mov rax, imm64 (48 B8 + 8 bytes); jmp rax (FF E0) */
enum { FN_INPUT, FN_OPEN, FN_CLOSE, FN_REQUEST, FN_SOUND, FN_SCRAMBLE, FN_HOOK_COUNT, FN_SCALE = FN_HOOK_COUNT, FN_RGB, FN_COUNT };
#define MAX_CALLS 64

static int g_calls[FN_HOOK_COUNT];
static int g_checkpoint_misses; /* calls of the four user-triggered functions whose checkpoint was not the last line */

/* native.h: the input handler, open, close and request_slot log "call <name>(" right before every call. */
static void checkpoint_before(const char* name)
{
    size_t n = strlen(name);
    if (strncmp(g_last_line, "call ", 5) != 0 || strncmp(g_last_line + 5, name, n) != 0 || g_last_line[5 + n] != '(')
        g_checkpoint_misses++;
}
static int g_handler_tick[MAX_CALLS];    /* the host's tick number at each input handler call */
static ULONGLONG g_handler_ms[MAX_CALLS]; /* and its GetTickCount64 */
static uint32_t g_sounds[MAX_CALLS];
static int g_sound_count;
static bool g_scramble_remap; /* the fake scramble query says an effect is on */

static int fn_calls(void)
{
    int n = 0;
    for (int i = 0; i < FN_HOOK_COUNT; i++) n += g_calls[i];
    return n;
}

static void host_input_handler(uintptr_t component)
{
    int n = g_calls[FN_INPUT]++;
    checkpoint_before("input_handler");
    if (n < MAX_CALLS) {
        g_handler_tick[n] = g_tick_no;
        g_handler_ms[n] = GetTickCount64();
    }
    syn_input_handler(component);
}

static uint8_t host_open_input(uintptr_t component)
{
    g_calls[FN_OPEN]++;
    checkpoint_before("open_input");
    return syn_open_input(component);
}

static void host_close_input(uintptr_t component)
{
    g_calls[FN_CLOSE]++;
    checkpoint_before("close_input");
    syn_close_input(component);
}

static void host_request_slot(uintptr_t weapon, uint32_t slot)
{
    g_calls[FN_REQUEST]++;
    checkpoint_before("request_slot");
    syn_request_slot(weapon, slot);
}

static void host_ui_sound(uintptr_t unused, uint32_t id)
{
    g_calls[FN_SOUND]++;
    if (g_sound_count < MAX_CALLS) g_sounds[g_sound_count++] = id;
}

/* The game writes its answer to *out; R46 reads anything but 0xffffffff as an effect being on (input.lua:156). */
static uintptr_t host_scramble_query(uintptr_t effects, uint32_t* out, uint32_t key, uint32_t kind, uintptr_t a5,
                                     uintptr_t a6)
{
    g_calls[FN_SCRAMBLE]++;
    if (g_scramble_remap && out != NULL) *out = 0;
    return 0;
}

/* The Windows x64 ABI passes R46's two-float NSR_vec2 by value. The RGB setter
 * takes a pointer and owns just the three channels after the native fade alpha. */
typedef struct ScalePair { float x, y; } ScalePair;
static void host_widget_scale(uintptr_t card, ScalePair scale)
{
    if (syn_write_mapped(card + 0x14u, &scale, sizeof scale) != 0)
        CHECK(false, "the widget scale setter received an unmapped card");
}

static void host_text_colour(uintptr_t widget, const float* rgb)
{
    if (!rgb || syn_write_mapped(widget + 0x48u, rgb, 3 * sizeof(float)) != 0)
        CHECK(false, "the widget colour setter received an unmapped container or missing RGB");
}

typedef struct GameFn {
    const char* name;
    uint32_t rva;
    void* fake;
    uint8_t original[STUB_BYTES]; /* the image's bytes under the stub: read_code serves them (the shadow copy) */
} GameFn;

static GameFn g_fns[FN_COUNT] = {
    [FN_INPUT] = { "input_handler", DBF_FN_INPUT_HANDLER, (void*)host_input_handler, { 0 } },
    [FN_OPEN] = { "open_input", DBF_FN_OPEN_INPUT, (void*)host_open_input, { 0 } },
    [FN_CLOSE] = { "close_input", DBF_FN_CLOSE_INPUT, (void*)host_close_input, { 0 } },
    [FN_REQUEST] = { "request_slot", DBF_FN_REQUEST_SLOT, (void*)host_request_slot, { 0 } },
    [FN_SOUND] = { "ui_sound", DBF_FN_UI_SOUND, (void*)host_ui_sound, { 0 } },
    [FN_SCRAMBLE] = { "scramble_query", DBF_FN_SCRAMBLE_QUERY, (void*)host_scramble_query, { 0 } },
    [FN_SCALE] = { "widget_scale", DBF_FN_WIDGET_SCALE, (void*)host_widget_scale, { 0 } },
    [FN_RGB] = { "text_colour", DBF_FN_TEXT_COLOUR, (void*)host_text_colour, { 0 } },
};

static void stub_bytes(const GameFn* f, uint8_t out[STUB_BYTES])
{
    uint64_t target = (uint64_t)(uintptr_t)f->fake;
    out[0] = 0x48;
    out[1] = 0xB8;
    memcpy(out + 2, &target, sizeof target);
    out[10] = 0xFF;
    out[11] = 0xE0;
}

/* game.dll's range reserved at SYN_GAME_BASE (first thing, so no DLL or heap lands there), its stub pages committed,
 * the stubs written and the pages made executable. */
static bool map_game_code(void)
{
    if (VirtualAlloc((void*)SYN_GAME_BASE, SYN_IMAGE_SIZE, MEM_RESERVE, PAGE_NOACCESS) != (void*)SYN_GAME_BASE) {
        printf("  game.dll's range at 0x%llx could not be reserved (error %lu)\n", (unsigned long long)SYN_GAME_BASE,
               (unsigned long)GetLastError());
        return false;
    }
    for (int i = 0; i < FN_COUNT; i++) {
        uintptr_t at = SYN_GAME_BASE + g_fns[i].rva, page = at & ~(uintptr_t)0xFFF;
        size_t span = ((at + STUB_BYTES + 0xFFF) & ~(uintptr_t)0xFFF) - page;
        uint8_t code[STUB_BYTES];
        if (VirtualAlloc((void*)page, span, MEM_COMMIT, PAGE_READWRITE) == NULL) return false;
        stub_bytes(&g_fns[i], code);
        memcpy((void*)at, code, sizeof code);
    }
    for (int i = 0; i < FN_COUNT; i++) {
        uintptr_t at = SYN_GAME_BASE + g_fns[i].rva, page = at & ~(uintptr_t)0xFFF;
        DWORD old;
        if (!VirtualProtect((void*)page, ((at + STUB_BYTES + 0xFFF) & ~(uintptr_t)0xFFF) - page, PAGE_EXECUTE_READ, &old))
            return false;
    }
    return FlushInstructionCache(GetCurrentProcess(), NULL, 0) != 0;
}

/* The input, sound and scramble stubs model hooks: the reader gets a shadow copy.
 * Scale and colour model the game's own setters and keep their intact admission witnesses. */
static bool place_stubs(void)
{
    bool ok = true;
    for (int i = 0; i < FN_HOOK_COUNT; i++) {
        uint8_t code[STUB_BYTES];
        stub_bytes(&g_fns[i], code);
        ok = ok && syn_read(SYN_GAME_BASE + g_fns[i].rva, g_fns[i].original, STUB_BYTES) == 0
            && syn_poke(SYN_GAME_BASE + g_fns[i].rva, code, STUB_BYTES);
    }
    return ok;
}

/* hf->read_code: the image as it was before any hook, the shadow copy under the stubs. */
static int api_read_code(uintptr_t address, void* out, size_t size)
{
    uint8_t* bytes = out;
    g_read_calls++;
    if (syn_read(address, out, size) != 0) return -1;
    for (int i = 0; i < FN_HOOK_COUNT; i++)
        for (unsigned b = 0; b < STUB_BYTES; b++) {
            uintptr_t at = SYN_GAME_BASE + g_fns[i].rva + b;
            if (at >= address && at - address < size) bytes[at - address] = g_fns[i].original[b];
        }
    return 0;
}

/* --- helpers --------------------------------------------------------------------------------------------------- */

static void* need(HMODULE module, const char* name)
{
    void* p = module ? (void*)GetProcAddress(module, name) : NULL;
    if (p == NULL) printf("  (%s is not exported)\n", name);
    return p;
}

static DWORD WINAPI watchdog(void* unused)
{
    Sleep(60000);
    puts("FAIL the case hung for 60 s");
    fflush(stdout);
    TerminateProcess(GetCurrentProcess(), 3);
    return 0;
}

/* "^ > v <" for a code, as the Status tab writes it. */
static void arrows(char* out, size_t size, const uint8_t* code, int n)
{
    static const char ARROWS[5] = { '?', '^', '>', 'v', '<' };
    size_t at = 0;
    for (int i = 0; i < n && at + 3 < size; i++) {
        if (i > 0) out[at++] = ' ';
        out[at++] = code[i] >= 1 && code[i] <= 4 ? ARROWS[code[i]] : '?';
    }
    out[at] = '\0';
}

static const DbfWitness* witness(const char* name)
{
    for (int i = 0; i < dbf_witness_count; i++)
        if (strcmp(dbf_witnesses[i].name, name) == 0) return &dbf_witnesses[i];
    return NULL;
}

/* The stub host's exports. */
static StubCountFn s_requests, s_panel_count, s_register_calls, s_game_thread_count, s_line_count, s_open, s_misuse;
static StubPanelFn s_panel;
static StubTickFn s_tick;
static StubDrawFn s_draw;
static StubLineFn s_line;
static StubTextFn s_count_prefix;
static StubSwitchFn s_refuse_panels, s_set_capturing;

static bool load_stub(HMODULE stub)
{
    s_requests = (StubCountFn)need(stub, "stub_requests");
    s_panel_count = (StubCountFn)need(stub, "stub_panel_count");
    s_register_calls = (StubCountFn)need(stub, "stub_register_calls");
    s_set_capturing = (StubSwitchFn)need(stub, "stub_set_capturing");
    s_refuse_panels = (StubSwitchFn)need(stub, "stub_refuse_panels");
    s_panel = (StubPanelFn)need(stub, "stub_panel");
    s_game_thread_count = (StubCountFn)need(stub, "stub_game_thread_count");
    s_tick = (StubTickFn)need(stub, "stub_tick");
    s_draw = (StubDrawFn)need(stub, "stub_draw");
    s_line_count = (StubCountFn)need(stub, "stub_line_count");
    s_line = (StubLineFn)need(stub, "stub_line");
    s_count_prefix = (StubTextFn)need(stub, "stub_count_prefix");
    s_open = (StubCountFn)need(stub, "stub_open");
    s_misuse = (StubCountFn)need(stub, "stub_misuse");
    return s_requests && s_panel_count && s_register_calls && s_refuse_panels && s_panel && s_game_thread_count && s_tick
        && s_set_capturing && s_draw && s_line_count && s_line && s_count_prefix && s_open && s_misuse;
}

/* One game update: the stub host's slot when the case has a host that runs one (API 5+), else HellForge's. */
static bool g_ticks_via_host;
static void do_tick(void)
{
    g_tick_no++;
    if (g_ticks_via_host) s_tick(1.0f / 60.0f);
    else api_tick();
}

static int find_line(const char* line)
{
    for (int i = 0; i < s_line_count(); i++)
        if (strcmp(s_line(i), line) == 0) return i;
    return -1;
}

static void print_drawing(void)
{
    for (int i = 0; i < s_line_count(); i++) printf("    | %s\n", s_line(i));
}

/* The window draws its panel (printing what it drew); false when it has none. */
static bool draw_window(void)
{
    bool drawn = s_draw(0) != 0;
    print_drawing();
    return drawn;
}

/* The Status tab's stratagem table: per row "row", "cell", "text:<name>", "cell", "text:<code>", in the scene's order. */
static bool rows_are(const SynScene* scene, int count)
{
    int at = find_line("headers");
    if (at < 0) return false;
    at++;
    for (int i = 0; i < count; i++, at += 5) {
        const SynStratagem* st = &scene->stratagems[i];
        char name[LINE_SIZE], code[LINE_SIZE], text[64];
        arrows(text, sizeof text, st->code, st->code_len);
        snprintf(name, sizeof name, "text:%s", dbf_kind_names[st->kind] ? dbf_kind_names[st->kind] : "?");
        snprintf(code, sizeof code, "text:%s", text);
        if (at + 4 >= s_line_count() || strcmp(s_line(at), "row") || strcmp(s_line(at + 1), "cell")
            || strcmp(s_line(at + 2), name) || strcmp(s_line(at + 3), "cell") || strcmp(s_line(at + 4), code)) {
            printf("  row %d: expected \"%s\" / \"%s\"\n", i, name, code);
            return false;
        }
    }
    return at < s_line_count() && strcmp(s_line(at), "end:table") == 0;
}

/* --- the process: one case ------------------------------------------------------------------------------------- */

typedef enum {
    C_NO_HOST, C_API3, C_API4, C_API5, C_NO_TICK, C_RETRY, C_ON_AT_ONCE, C_LATE_MODULE, C_SECOND_LOADED, C_NULL_PANEL,
    C_ON_FAILS, C_MASKED_LOG, C_LIST_CONFIRM, C_INSTANT, C_MENU_CLOSE, C_MISSION_END, C_SHORTCUT, C_SHORTCUT_HUD,
    C_MOD_STRATAGEM, C_SCRAMBLE, C_NO_ENTRY_ADMISSION, C_NO_HOST_ENTRY, C_RELEASE_RETRY, C_CARD_GONE, C_SHORTCUT_BLOCKED,
    C_LATCH_RETRY, C_OLD_HOST_INPUT
} CaseId;

typedef struct CaseInfo {
    const char* name;
    const char* title;
    bool stub;   /* needs the stub Overlay Host (argument 3) */
    bool loader; /* needs the stub loader (argument 4, or 3 without a host) */
    bool entry;  /* a code-entry case: settings.ini, a writable image, a window in front, keys */
} CaseInfo;

static const CaseInfo CASES[] = {
    [C_NO_HOST] = { "no-host", "no Overlay Host", false, false, false },
    [C_API3] = { "host-api3", "an Overlay Host older than 0.2.0 (API 3)", true, false, false },
    [C_API4] = { "host-api4", "Overlay Host 0.2.x (API 4, no shared game-thread slot)", true, false, false },
    [C_API5] = { "host-api5", "Overlay Host 0.3.x (API 5) and HellForge's rewrite list", true, true, false },
    [C_NO_TICK] = { "no-tick", "Overlay Host 0.2.x, and HellForge gives no game-thread slot", true, false, false },
    [C_RETRY] = { "retry", "a changed witness byte is put back: admission retries after a second", true, false, false },
    [C_ON_AT_ONCE] = { "on-at-once", "HellForge delivers the game-loaded event before on returns", true, false, false },
    [C_LATE_MODULE] = { "late-module", "game.dll is not loaded on the first tick", true, false, false },
    [C_SECOND_LOADED] = { "second-loaded", "the game-loaded event comes three times", true, false, false },
    [C_NULL_PANEL] = { "null-panel", "the Overlay Host takes no window", true, false, false },
    [C_ON_FAILS] = { "on-fails", "HellForge refuses the game-loaded listener", true, false, false },
    [C_MASKED_LOG] = { "masked-log", "HellForge rewrites bytes of two witnesses", true, true, false },
    [C_LIST_CONFIRM] = { "list-confirm", "List Select: Next once, Confirm, the code paced", true, true, true },
    [C_INSTANT] = { "instant", "List Select with Instant: the last direction once Confirm is up", true, true, true },
    [C_MENU_CLOSE] = { "menu-close", "the game closes the menu during a code", true, true, true },
    [C_MISSION_END] = { "mission-end", "the mission ends during a code", true, true, true },
    [C_SHORTCUT] = { "shortcut", "slot 1's hotkey from a closed menu, with the menu latch", true, true, true },
    [C_SHORTCUT_HUD] = { "shortcut-hud", "the HUD is replaced during a slot hotkey", true, true, true },
    [C_MOD_STRATAGEM] = { "mod-stratagem", "a HellForge stratagem (kind 151) with its code in the loader", true, true, true },
    [C_SCRAMBLE] = { "scramble", "a scramble effect: the remapped code is entered", true, true, true },
    [C_NO_ENTRY_ADMISSION] = { "no-entry-admission", "an ENTRY witness differs: Confirm does nothing", true, true, true },
    [C_OLD_HOST_INPUT] = { "old-host-input", "API 5 lacks direct input capture", true, true, true },
    [C_NO_HOST_ENTRY] = { "no-host-entry", "no Overlay Host: DBF's keys still enter codes", false, true, true },
    [C_RELEASE_RETRY] = { "release-retry", "a direction's release cannot be written: the tick retries it", true, true, true },
    [C_CARD_GONE] = { "card-gone", "the stratagem's card becomes unavailable during a code", true, true, true },
    [C_SHORTCUT_BLOCKED] = { "shortcut-blocked", "a host window opens during a slot hotkey", true, true, true },
    [C_LATCH_RETRY] = { "latch-retry", "a latch release cannot be written: the tick retries it for its owner", true, true,
                        true },
};

static CaseId g_case;
static SynScene g_scene;
static HfApi g_api;
static HMODULE g_stub, g_loader;
static int (*g_init)(const HfApi*, HfMod*);

/* init, checked. */
static void run_init(void)
{
    CHECK(g_init(&g_api, &g_mod) == 0, "init returns 0");
}

/* The window shows four rows with the scene's names and codes, admitted features and a verified build. */
static void check_full_window(const char* after)
{
    char text[LINE_SIZE];
    snprintf(text, sizeof text, "%s: the window draws", after);
    CHECK(draw_window(), text);
    snprintf(text, sizeof text, "%s: build OK, the three read features OK", after);
    CHECK(find_line("text:Game build 25480438: OK") >= 0 && find_line("text:Selection state: OK") >= 0
              && find_line("text:Stratagems: OK") >= 0 && find_line("text:HUD reads: OK") >= 0,
          text);
    snprintf(text, sizeof text, "%s: in a mission, everything read, four rows with the scene's names and codes", after);
    CHECK(find_line("text:In a mission: yes") >= 0 && s_count_prefix("text:Reader:") == 0 && s_count_prefix("row") == 4
              && rows_are(&g_scene, 4),
          text);
    CHECK(s_open() == 0 && s_misuse() == 0, "every begin has its end");
}

/* --- the first five cases -------------------------------------------------------------------------------------- */

static void run_standard(void)
{
    const bool api4 = g_case == C_API4, api5 = g_case == C_API5, no_tick = g_case == C_NO_TICK, window = api4 || api5;
    const DbfWitness* rewritten = witness("hud_root"); /* a STATE and HUD_READ witness */
    uint32_t rewritten_rva = 0;
    void (*set_rewritten)(uint32_t) = NULL;
    int (*rewrite_calls)(void) = NULL;

    CHECK(rewritten != NULL, "the generated table has the hud_root witness");
    if (rewritten) rewritten_rva = rewritten->rva + 3u;
    if (api5) {
        uint8_t byte = 0;
        set_rewritten = (void (*)(uint32_t))need(g_loader, "stub_set_rewritten");
        rewrite_calls = (int (*)(void))need(g_loader, "stub_rewrite_calls");
        if (!set_rewritten || !rewrite_calls) return;
        set_rewritten(rewritten_rva);
        /* One byte of the witness differs from the table, and the loader says HellForge rewrites it. */
        CHECK(syn_read(SYN_GAME_BASE + rewritten_rva, &byte, 1) == 0
                  && syn_poke_u8(SYN_GAME_BASE + rewritten_rva, (uint8_t)(byte ^ 0xffu)),
              "a byte of the hud_root witness is changed, as HellForge rewrites it");
    }

    run_init();
    CHECK(logged(VERSION_LINE) == 1, "init logs \"" VERSION_LINE "\"");
    CHECK(g_listener_count == 1 && g_listeners[0].event == HF_EVENT_GAME_LOADED && g_listeners[0].mod == &g_mod,
          "init registers for HF_EVENT_GAME_LOADED only");
    CHECK(g_ticker_count == 0, "init takes no game-thread slot");
    if (g_stub)
        CHECK(s_requests() == 0 && s_panel_count() == 0 && s_game_thread_count() == 0,
              "init does not touch the Overlay Host");

    fire(HF_EVENT_GAME_LOADED);
    if (no_tick) {
        CHECK(logged(NO_TICK_LINE) == 1, "the \"" NO_TICK_LINE "\" line");
        CHECK(logged(NO_HOST_LINE) == 0 && s_requests() > 0, "the host was found (API 4)");
        CHECK(s_panel_count() == 0 && s_game_thread_count() == 0 && g_ticker_count == 0, "and DBF stops: no window");
        return;
    }
    CHECK(logged(NO_TICK_LINE) == 0, "the tick is registered");
    if (window) {
        const StubPanel* p = s_panel(0);
        CHECK(logged(NO_HOST_LINE) == 0, "with an Overlay Host 0.2.0 or later, no \"running without a settings window\" line");
        CHECK(s_panel_count() == 1 && p != NULL && strcmp(p->id, PANEL_ID) == 0, "one settings window with id " PANEL_ID);
        CHECK(p && p->size == sizeof(OvPanelDef) && strcmp(p->title, PANEL_TITLE) == 0 && p->kind == OV_PANEL_WINDOW
                  && p->hotkey == VK_F7 && p->width == 640.0f && p->height == 520.0f && p->draw != NULL,
              "the panel is the window \"" PANEL_TITLE "\", F7 hotkey, 640x520, with a draw callback");
        if (api5)
            CHECK(s_game_thread_count() == 1 && g_ticker_count == 0,
                  "the tick goes through the Overlay Host's on_game_thread (API 5), not HellForge's");
        else
            CHECK(s_game_thread_count() == 0 && g_ticker_count == 1 && g_tickers[0].mod == &g_mod,
                  "an API 4 host has no shared slot: the tick goes through HellForge's on_game_thread");
        CHECK(s_draw(0) && s_line_count() == 1 && strcmp(s_line(0), STARTING_TEXT) == 0,
              "before the first tick the window says \"Diver's Best Friend is starting...\"");
    } else {
        CHECK(logged(NO_HOST_LINE) == 1, "the \"" NO_HOST_LINE "\" line");
        CHECK(g_ticker_count == 1 && g_tickers[0].mod == &g_mod, "the tick goes through HellForge's on_game_thread");
        if (g_stub)
            CHECK(s_requests() > 0 && s_panel_count() == 0 && s_game_thread_count() == 0,
                  "DBF asked the old host for its API, and registered nothing with it");
    }

    /* A tick, a draw, a tick, then the menu closes in the game before the last tick: the window must draw the last tick's
     * read. Its publish goes to the buffer the draw read, so a draw that kept its snapshot (no snap_release) or a tick
     * that did not publish leaves the window showing the menu open. */
    for (int i = 0; i < TICKS; i++) {
        if (i == 1 && window)
            CHECK(s_draw(0) && find_line("text:Stratagem menu: open") >= 0 && s_count_prefix("row") == 4,
                  "after the first tick the window shows the menu open and four rows");
        if (i == TICKS - 1)
            CHECK(syn_poke_u8(syn_panel() + MENU_OPEN_AT, 0), "the menu closes in the game before the last tick");
        do_tick();
    }
    CHECK(logged(VERSION_LINE) == 1, "after 3 ticks the version line is still logged once");
    CHECK(logged(NO_HOST_LINE) == (window ? 0 : 1),
          window ? "after 3 ticks still no \"running without a settings window\" line"
                 : "after 3 ticks the \"running without a settings window\" line is still logged exactly once");
    CHECK(logged(ADMISSION_LINE) == 1, "the first tick found game.dll and logged that admission starts, once");
    if (api5) {
        const DbfWitness* w = witness("hud_root");
        char masked[LINE_SIZE];
        CHECK(logged(REWRITES_FOUND_LINE) == 1 && logged(REWRITES_MISSING_LINE) == 0,
              "the tick found hellforge_lua_rewrites and logged it once");
        CHECK(rewrite_calls() > 0, "admission asked hellforge_lua_rewrites about the changed byte");
        snprintf(masked, sizeof masked, "witness hud_root: 1 of %u" MASKED_TAIL, w ? (unsigned)w->size : 0u);
        CHECK(logged(masked) == 1 && logged_ending(MASKED_TAIL) == 1,
              "and logged that one byte of hud_root is rewritten by HellForge, once and for no other witness");
    } else {
        CHECK(logged(REWRITES_MISSING_LINE) == 1 && logged(REWRITES_FOUND_LINE) == 0,
              "the tick found no hellforge_lua_rewrites and logged it once");
        CHECK(logged_ending(MASKED_TAIL) == 0, "and logged no masked witness");
    }
    CHECK(syn_write_count() == 0 && fn_calls() == 0, "no hf->write or gameplay, sound or scramble call");
    if (api5) {
        int (*byte_calls)(void) = (int (*)(void))need(g_loader, "stub_byte_calls");
        const DbfWitness* w = witness("hud_root");
        CHECK(byte_calls && w && byte_calls() == (int)w->size,
              "the loader was asked about single bytes of hud_root alone (whole witnesses first), once each");
    }

    if (window) {
        char host_line[64];
        snprintf(host_line, sizeof host_line, "text:Overlay Host API %d", api5 ? 5 : 4);
        CHECK(s_draw(0), "the window draws after 3 ticks");
        print_drawing();
        CHECK(find_line("text:Game build 25480438: OK") >= 0, "the last snapshot has build_ok");
        CHECK(find_line("text:Selection state: OK") >= 0 && find_line("text:Stratagems: OK") >= 0
                  && find_line("text:HUD reads: OK") >= 0,
              api5 ? "Selection state, Stratagems and HUD reads are admitted (the rewritten byte is skipped)"
                   : "Selection state, Stratagems and HUD reads are admitted");
        CHECK(find_line(host_line) >= 0, "the snapshot carries the host's API version");
        CHECK(find_line("text:In a mission: yes") >= 0 && find_line("text:Stratagem menu: closed") >= 0
                  && s_count_prefix("text:Reader:") == 0,
              "the last tick's read: in a mission, the menu closed, everything read");
        CHECK(s_count_prefix("row") == 4 && rows_are(&g_scene, 4), "four rows, with the scene's names and codes in list order");
        CHECK(s_open() == 0 && s_misuse() == 0, "every begin has its end");
    }
}

/* --- retry ----------------------------------------------------------------------------------------------------- */

/* A byte of hud_root (a STATE and HUD_READ witness) is wrong when admission first looks: the features wait, and the Status
 * tab says why. The game puts it right; a second later admission looks again and admits them. */
static void run_retry(void)
{
    const DbfWitness* w = witness("hud_root");
    uintptr_t at = w ? SYN_GAME_BASE + w->rva + 3u : 0;
    uint8_t byte = 0;
    const char* reason = "witness hud_root differs (retrying)";
    char selection[LINE_SIZE], hud[LINE_SIZE];

    CHECK(w != NULL && syn_read(at, &byte, 1) == 0 && syn_poke_u8(at, (uint8_t)(byte ^ 0xffu)),
          "a byte of the hud_root witness is wrong before the first tick");
    run_init();
    fire(HF_EVENT_GAME_LOADED);
    CHECK(s_panel_count() == 1 && g_ticker_count == 1, "the window and the tick are registered");

    do_tick();
    CHECK(draw_window(), "the window draws after the first tick");
    snprintf(selection, sizeof selection, "text:Selection state: Waiting (%s)", reason);
    snprintf(hud, sizeof hud, "text:HUD reads: Waiting (%s)", reason);
    CHECK(find_line(selection) >= 0 && find_line(hud) >= 0, "Selection state and HUD reads wait, with the witness named");
    CHECK(find_line("text:Game build 25480438: OK") >= 0 && find_line("text:Stratagems: OK") >= 0,
          "the build is verified and Stratagems, which do not rest on hud_root, are admitted");
    CHECK(s_count_prefix("row") == 0 && find_line("text:In a mission: yes") < 0, "and nothing is read from the game meanwhile");
    CHECK(logged(ADMISSION_LINE) == 1, "admission started once");

    CHECK(syn_poke_u8(at, byte), "the byte is put right");
    Sleep(RETRY_WAIT_MS);
    do_tick();
    check_full_window("a second after the byte was put right");
    CHECK(logged(ADMISSION_LINE) == 1 && logged(VERSION_LINE) == 1, "admission was not started again, only retried");
    CHECK(syn_write_count() == 0 && fn_calls() == 0, "no hf->write or gameplay, sound or scramble call");
}

/* --- on-at-once ------------------------------------------------------------------------------------------------ */

static void run_on_at_once(void)
{
    const StubPanel* p;
    run_init();
    CHECK(g_on_calls == 1 && g_listener_count == 1 && g_listeners[0].event == HF_EVENT_GAME_LOADED
              && g_listeners[0].mod == &g_mod,
          "init registers for HF_EVENT_GAME_LOADED only, once");
    CHECK(g_version_lines_at_on == 1, "the version line was already logged when init called on");
    CHECK(g_line_count > 0 && strcmp(g_lines[0], VERSION_LINE) == 0 && logged(VERSION_LINE) == 1,
          "the version line is the first line logged, and logged once");
    p = s_panel(0);
    CHECK(s_register_calls() == 1 && s_panel_count() == 1 && p != NULL && strcmp(p->id, PANEL_ID) == 0,
          "the event delivered inside on registered the window once");
    CHECK(g_ticker_count == 1 && g_tickers[0].mod == &g_mod && s_game_thread_count() == 0,
          "and the tick, through HellForge's on_game_thread (the API 4 host has no slot)");
    CHECK(logged(NO_HOST_LINE) == 0 && logged(NO_TICK_LINE) == 0 && logged(NO_PANEL_LINE) == 0, "with nothing refused");
    CHECK(s_draw(0) && s_line_count() == 1 && strcmp(s_line(0), STARTING_TEXT) == 0,
          "before the first tick the window says \"Diver's Best Friend is starting...\"");

    for (int i = 0; i < TICKS; i++) do_tick();
    CHECK(logged(VERSION_LINE) == 1 && s_panel_count() == 1 && s_register_calls() == 1 && g_ticker_count == 1,
          "after 3 ticks still one version line, one window and one tick");
    CHECK(logged(ADMISSION_LINE) == 1, "admission started once");
    check_full_window("after 3 ticks");
    CHECK(syn_write_count() == 0 && fn_calls() == 0, "no hf->write or gameplay, sound or scramble call");
}

/* --- late-module ----------------------------------------------------------------------------------------------- */

static void run_late_module(void)
{
    g_module_from_tick = 2; /* nothing on the first tick, game.dll and the exe from the second */
    run_init();
    fire(HF_EVENT_GAME_LOADED);

    do_tick();
    CHECK(g_module_base_calls > 0, "the first tick asked for game.dll");
    CHECK(logged(ADMISSION_LINE) == 0 && logged(REWRITES_FOUND_LINE) == 0 && logged(REWRITES_MISSING_LINE) == 0,
          "game.dll is not there: admission has not started, and says nothing");
    CHECK(g_read_calls == 0 && syn_write_count() == 0, "and the tick read nothing from the game");
    CHECK(draw_window(), "the window draws after the first tick");
    CHECK(find_line("text:Game build: game.dll not loaded yet") >= 0, "the snapshot's build reason says game.dll is not loaded yet");
    CHECK(find_line("text:Selection state: Waiting (game.dll not loaded yet)") >= 0
              && find_line("text:Stratagems: Waiting (game.dll not loaded yet)") >= 0
              && find_line("text:HUD reads: Waiting (game.dll not loaded yet)") >= 0,
          "the read features wait for it");
    CHECK(s_count_prefix("row") == 0 && find_line("text:In a mission: no") >= 0 && s_count_prefix("text:Reader:") == 0,
          "no rows, no mission");

    do_tick();
    CHECK(logged(ADMISSION_LINE) == 1, "on the second tick game.dll is found and admission starts, with one line saying so");
    CHECK(logged(REWRITES_MISSING_LINE) == 1, "and the rewrite list is looked up then (none in this case), once");
    CHECK(g_read_calls > 0, "and the game is read");
    check_full_window("on the second tick");

    do_tick();
    CHECK(logged(ADMISSION_LINE) == 1 && logged(REWRITES_MISSING_LINE) == 1, "a third tick starts nothing again");
    check_full_window("after the third tick");
    CHECK(syn_write_count() == 0 && fn_calls() == 0, "no hf->write or gameplay, sound or scramble call");
}

/* --- second-loaded --------------------------------------------------------------------------------------------- */

static void run_second_loaded(void)
{
    int requests;
    run_init();
    fire(HF_EVENT_GAME_LOADED);
    CHECK(s_panel_count() == 1 && g_ticker_count == 1 && logged(REPEATED_LINE) == 0,
          "the first event registers the window and the tick, and logs no repeat");
    requests = s_requests();
    fire(HF_EVENT_GAME_LOADED);
    CHECK(logged(REPEATED_LINE) == 1, "the second event is logged: \"" REPEATED_LINE "\"");
    fire(HF_EVENT_GAME_LOADED);
    CHECK(logged(REPEATED_LINE) == 1, "a third one is not logged again");
    CHECK(s_register_calls() == 1 && s_panel_count() == 1 && g_ticker_count == 1 && s_game_thread_count() == 0,
          "and neither registered another window or tick");
    CHECK(s_requests() == requests, "nor asked the Overlay Host for its API again");
    CHECK(logged(NO_HOST_LINE) == 0 && logged(NO_TICK_LINE) == 0 && logged(NO_PANEL_LINE) == 0, "nothing was refused");

    for (int i = 0; i < TICKS; i++) do_tick();
    CHECK(logged(REPEATED_LINE) == 1 && logged(VERSION_LINE) == 1 && logged(ADMISSION_LINE) == 1,
          "after 3 ticks: one repeat line, one version line, admission started once");
    check_full_window("after 3 ticks");
    CHECK(syn_write_count() == 0 && fn_calls() == 0, "no hf->write or gameplay, sound or scramble call");
}

/* --- null-panel ------------------------------------------------------------------------------------------------ */

static void run_null_panel(void)
{
    s_refuse_panels(1);
    run_init();
    fire(HF_EVENT_GAME_LOADED);
    CHECK(s_register_calls() == 1 && s_panel_count() == 0,
          "DBF asked the Overlay Host for its settings window once and was refused");
    CHECK(logged(NO_PANEL_LINE) == 1, "and logged the refusal once");
    CHECK(logged(NO_HOST_LINE) == 0 && logged(NO_TICK_LINE) == 0, "the host was found and the tick registered");
    CHECK(g_ticker_count == 1 && g_tickers[0].mod == &g_mod, "the tick goes through HellForge's on_game_thread");
    CHECK(s_draw(0) == 0, "there is no window to draw");

    for (int i = 0; i < TICKS; i++) do_tick();
    CHECK(logged(NO_PANEL_LINE) == 1 && s_register_calls() == 1, "the ticks ask nothing more of the host");
    CHECK(logged(ADMISSION_LINE) == 1 && g_read_calls > 0, "the ticks still run: admission started and the game was read");
    CHECK(syn_write_count() == 0 && fn_calls() == 0, "no hf->write or gameplay, sound or scramble call");
}

/* --- on-fails -------------------------------------------------------------------------------------------------- */

static void run_on_fails(void)
{
    run_init();
    CHECK(g_on_calls == 1 && g_listener_count == 0, "HellForge was asked for a listener once and took none");
    CHECK(logged(LISTEN_FAILED_LINE) == 1, "DBF logged \"" LISTEN_FAILED_LINE "\" once");
    CHECK(g_line_count == 2 && strcmp(g_lines[0], VERSION_LINE) == 0 && strcmp(g_lines[1], LISTEN_FAILED_LINE) == 0,
          "its log is the version line, then that line, and nothing else");
    fire(HF_EVENT_GAME_LOADED);
    CHECK(s_requests() == 0 && s_panel_count() == 0 && s_register_calls() == 0 && s_game_thread_count() == 0
              && g_ticker_count == 0,
          "nothing is registered with the Overlay Host or HellForge");
    CHECK(g_read_calls == 0 && g_module_base_calls == 0 && syn_write_count() == 0, "and the game is left alone");
}

/* --- masked-log ------------------------------------------------------------------------------------------------ */

/* HellForge rewrites three bytes of hud_root and one of owner_map_value. One hud_root byte of the three differs, and so
 * does another byte, which nothing rewrites, so the witness stays pending and is read again; the owner_map_value byte
 * matches. Each witness' count (all its rewritten bytes, matching or not) is logged once, however often it is read. */
static void run_masked_log(void)
{
    const DbfWitness* a = witness("hud_root");
    const DbfWitness* b = witness("owner_map_value");
    void (*set_rewritten)(uint32_t) = (void (*)(uint32_t))need(g_loader, "stub_set_rewritten");
    void (*add_rewritten)(uint32_t) = (void (*)(uint32_t))need(g_loader, "stub_add_rewritten");
    int (*rewrite_calls)(void) = (int (*)(void))need(g_loader, "stub_rewrite_calls");
    uintptr_t masked_change, plain_change;
    uint8_t byte_masked = 0, byte_plain = 0;
    char a_line[LINE_SIZE], b_line[LINE_SIZE], selection[LINE_SIZE];

    CHECK(a != NULL && b != NULL && b->size > 8 && set_rewritten && add_rewritten && rewrite_calls,
          "the table has hud_root and owner_map_value, and the stub loader takes several rewritten bytes");
    if (!a || !b || !set_rewritten || !add_rewritten || !rewrite_calls) return;
    snprintf(a_line, sizeof a_line, "witness hud_root: 3 of %u" MASKED_TAIL, (unsigned)a->size);
    snprintf(b_line, sizeof b_line, "witness owner_map_value: 1 of %u" MASKED_TAIL, (unsigned)b->size);
    snprintf(selection, sizeof selection, "text:Selection state: Waiting (witness hud_root differs (retrying))");
    set_rewritten(a->rva + 3u);
    add_rewritten(a->rva + 4u);
    add_rewritten(a->rva + 5u);
    add_rewritten(b->rva + 7u);
    masked_change = SYN_GAME_BASE + a->rva + 3u; /* rewritten, and different */
    plain_change = SYN_GAME_BASE + a->rva + 10u; /* different, and nothing rewrites it */
    CHECK(syn_read(masked_change, &byte_masked, 1) == 0 && syn_poke_u8(masked_change, (uint8_t)(byte_masked ^ 0xffu))
              && syn_read(plain_change, &byte_plain, 1) == 0 && syn_poke_u8(plain_change, (uint8_t)(byte_plain ^ 0xffu)),
          "hud_root has a rewritten byte and an unrewritten byte that differ from the table");

    run_init();
    fire(HF_EVENT_GAME_LOADED);
    do_tick();
    CHECK(rewrite_calls() > 0, "admission asked the loader about witness bytes");
    CHECK(logged(a_line) == 1, "hud_root: its three rewritten bytes are logged, once");
    CHECK(logged(b_line) == 1, "owner_map_value: its one rewritten byte, which matched, is logged, once");
    CHECK(logged_ending(MASKED_TAIL) == 2, "and no other witness is logged");
    CHECK(draw_window() && find_line(selection) >= 0, "hud_root differs where nothing rewrites it: Selection state waits");

    Sleep(RETRY_WAIT_MS);
    do_tick();
    CHECK(draw_window() && find_line(selection) >= 0, "a second later hud_root still differs");
    CHECK(logged(a_line) == 1 && logged(b_line) == 1 && logged_ending(MASKED_TAIL) == 2,
          "read again, it logs nothing more");

    CHECK(syn_poke_u8(plain_change, byte_plain), "the unrewritten byte is put right (the rewritten one stays changed)");
    Sleep(RETRY_WAIT_MS);
    do_tick();
    check_full_window("a second after the unrewritten byte was put right");
    CHECK(logged(a_line) == 1 && logged(b_line) == 1 && logged_ending(MASKED_TAIL) == 2,
          "admitted, the counts were logged once each");
    CHECK(syn_write_count() == 0 && fn_calls() == 0, "no hf->write or gameplay, sound or scramble call");
}

/* --- the code-entry cases (Plan 2, Task 12) --------------------------------------------------------------------- */

#define KEY_SLOT1 0x83   /* F20 */
#define KEY_NEXT 0x84    /* F21 */
#define KEY_PREVIOUS 0x85 /* F22 */
#define KEY_CONFIRM 0x86 /* F23 */
#define INTERVAL_MS 60u /* the settings' input_interval_ms in the paced cases */
#define SOUND_GAP_MS 80u /* more than sound.h's 60 ms between a sound and a move sound */
#define WAIT_MS 3000u   /* the longest a case waits for a code */
#define ENGINE_AT ((uintptr_t)0x2c100000000ull) /* the audio engine (native.lua:328-330), anywhere plausible */
#define EFFECTS_AT ((uintptr_t)0x2d000000000ull)

/* R46's settings for these cases (the [dbf] keys of each case follow; a later line wins). */
static const char BASE_SETTINGS[] =
    "; Diver's Best Friend for HellForge, written by wine_host.exe\n"
    "[dbf]\n"
    "input_interval_ms = 60 ; between directions\n"
    "[bindings]\n"
    "next = key:f21\n"
    "previous = key:f22\n"
    "confirm = key:f23 # Confirm\n"
    "slot1 = key:f20\n";

/* R46 input.lua:264: code direction d (1 up, 2 right, 3 down, 4 left) is entered as action ({3,2,4,1})[d]. */
static const int ACTION_OF[5] = { 0, 3, 2, 4, 1 };

typedef SHORT(WINAPI* KeyStateFn)(int);
typedef void(WINAPI* KeybdEventFn)(BYTE, BYTE, DWORD, ULONG_PTR);
typedef HWND(WINAPI* CreateWindowFn)(DWORD, LPCSTR, LPCSTR, DWORD, int, int, int, int, HWND, HMENU, HINSTANCE, LPVOID);
typedef BOOL(WINAPI* SetForegroundFn)(HWND);
typedef HWND(WINAPI* ForegroundFn)(void);
typedef BOOL(WINAPI* DestroyWindowFn)(HWND);
typedef BOOL(WINAPI* PeekMessageFn)(LPMSG, HWND, UINT, UINT, UINT);
typedef LRESULT(WINAPI* DispatchMessageFn)(const MSG*);

static KeyStateFn g_key_state;
static KeybdEventFn g_keybd_event;
static PeekMessageFn g_peek;
static DispatchMessageFn g_dispatch;
static DestroyWindowFn g_destroy;
static ForegroundFn g_foreground;
static HWND g_window;

static void pump(void)
{
    MSG msg;
    if (g_peek == NULL || g_dispatch == NULL) return;
    while (g_peek(&msg, NULL, 0, 0, PM_REMOVE)) g_dispatch(&msg);
}

static int g_keys_lost; /* key events GetAsyncKeyState did not show within KEY_WAIT_MS */
#define KEY_WAIT_MS 500u
#define PROBE_TRIES 50

static bool key_is(BYTE vk, bool down)
{
    return g_key_state != NULL && ((g_key_state(vk) & 0x8000) != 0) == down;
}

/* A key event, and a wait (pumping messages) until GetAsyncKeyState shows it: Wine may deliver the event a moment later,
 * and DBF reads the key state when its tick runs. */
static void key(BYTE vk, bool down)
{
    ULONGLONG until;
    if (g_keybd_event == NULL) return;
    g_keybd_event(vk, 0, down ? 0 : KEYEVENTF_KEYUP, 0);
    until = GetTickCount64() + KEY_WAIT_MS;
    pump();
    while (!key_is(vk, down) && GetTickCount64() < until) {
        Sleep(2);
        pump();
    }
    if (!key_is(vk, down)) g_keys_lost++;
}

static void release_keys(void)
{
    static const BYTE KEYS[] = { KEY_SLOT1, KEY_NEXT, KEY_PREVIOUS, KEY_CONFIRM };
    for (size_t i = 0; i < sizeof KEYS; i++) key(KEYS[i], false);
}

/* A window of this process in front and keybd_event reaching GetAsyncKeyState, as DBF's BindPort reads the keys (the
 * bind-port probe shows whether this Wine session can). User32 is found by name, as the DLL finds it. */
static bool keys_and_window(void)
{
    HMODULE user32 = GetModuleHandleA("user32.dll");
    CreateWindowFn create;
    SetForegroundFn set_foreground;
    ForegroundFn foreground;
    bool pressed;
    if (user32 == NULL) user32 = LoadLibraryA("user32.dll");
    if (user32 == NULL) return false;
    g_key_state = (KeyStateFn)(void*)GetProcAddress(user32, "GetAsyncKeyState");
    g_keybd_event = (KeybdEventFn)(void*)GetProcAddress(user32, "keybd_event");
    g_peek = (PeekMessageFn)(void*)GetProcAddress(user32, "PeekMessageA");
    g_dispatch = (DispatchMessageFn)(void*)GetProcAddress(user32, "DispatchMessageA");
    g_destroy = (DestroyWindowFn)(void*)GetProcAddress(user32, "DestroyWindow");
    create = (CreateWindowFn)(void*)GetProcAddress(user32, "CreateWindowExA");
    set_foreground = (SetForegroundFn)(void*)GetProcAddress(user32, "SetForegroundWindow");
    foreground = (ForegroundFn)(void*)GetProcAddress(user32, "GetForegroundWindow");
    g_foreground = foreground;
    if (!g_key_state || !g_keybd_event || !create || !set_foreground || !foreground) return false;
    release_keys();
    g_window = create(0, "STATIC", "DBF entry test", WS_POPUP | WS_VISIBLE, 0, 0, 64, 64, NULL, NULL,
                      GetModuleHandleA(NULL), NULL);
    if (g_window == NULL) return false;
    /* Wine may take a moment to hand a new window the foreground and the keyboard (the window manager decides; a window
     * of the case before may just have gone), so the probe is tried again for up to PROBE_TRIES * 100 ms. */
    pressed = false;
    for (int attempt = 0; attempt < PROBE_TRIES && !pressed; attempt++) {
        if (attempt > 0) Sleep(100);
        set_foreground(g_window);
        pump();
        if (foreground() != g_window) continue;
        key(KEY_NEXT, true);
        pressed = key_is(KEY_NEXT, true);
        key(KEY_NEXT, false);
        pressed = pressed && key_is(KEY_NEXT, false);
    }
    if (foreground() != g_window) printf("  the window did not get the foreground\n");
    if (!pressed) printf("  keybd_event did not reach GetAsyncKeyState\n");
    g_keys_lost = 0;
    return foreground() == g_window && pressed;
}

static void end_keys(void)
{
    CHECK(g_keys_lost == 0, "every key press and release reached GetAsyncKeyState");
    release_keys();
    if (g_window != NULL && g_destroy != NULL) g_destroy(g_window);
    g_window = NULL;
}

static void entry_tick(void)
{
    pump();
    do_tick();
}

/* A key pressed for one tick and let go for the next. */
static void tap(BYTE vk)
{
    key(vk, true);
    entry_tick();
    key(vk, false);
    entry_tick();
}

/* LOCALAPPDATA of this case, beside the host (build/wine/appdata-<case>), with settings.ini holding `settings` (NULL: no
 * file); DBF reads %LOCALAPPDATA%\DBF\HellForge\settings.ini at the game-loaded event. */
static bool prepare_appdata(const char* name, const char* settings)
{
    char dir[MAX_PATH], path[MAX_PATH + 64];
    char* slash;
    FILE* f;
    if (GetModuleFileNameA(NULL, dir, sizeof dir) == 0) return false;
    slash = strrchr(dir, '\\');
    if (slash == NULL) return false;
    *slash = '\0';
    snprintf(path, sizeof path, "%s\\appdata-%s", dir, name);
    CreateDirectoryA(path, NULL);
    if (!SetEnvironmentVariableA("LOCALAPPDATA", path)) return false;
    snprintf(path, sizeof path, "%s\\appdata-%s\\DBF", dir, name);
    CreateDirectoryA(path, NULL);
    snprintf(path, sizeof path, "%s\\appdata-%s\\DBF\\HellForge", dir, name);
    CreateDirectoryA(path, NULL);
    snprintf(path, sizeof path, "%s\\appdata-%s\\DBF\\HellForge\\settings.ini", dir, name);
    DeleteFileA(path);
    if (settings == NULL) return true;
    f = fopen(path, "wb");
    if (f == NULL) return false;
    fputs(settings, f);
    return fclose(f) == 0;
}

/* The audio and effects globals R46 reads before the UI sound and the scramble query (native.lua:325-332, input.lua:153). */
static bool poke_globals(void)
{
    uintptr_t state = 0;
    return syn_poke_u64(SYN_GAME_BASE + DBF_RVA_AUDIO, ENGINE_AT)
        && syn_poke_u64(ENGINE_AT + DBF_OFF_AUDIO_CALL_OFFSET, ENGINE_AT + 0x1000u)
        && syn_poke_u64(ENGINE_AT + DBF_OFF_AUDIO_TAIL_CALL_OFFSET, ENGINE_AT + 0x2000u)
        && syn_read(SYN_GAME_BASE + DBF_RVA_GAME_STATE, &state, sizeof state) == 0
        && syn_poke_u64(state + DBF_OFF_GAME_AUDIO_OFFSET, ENGINE_AT + 0x3000u)
        && syn_poke_u64(SYN_GAME_BASE + DBF_RVA_EFFECTS, EFFECTS_AT);
}

/* The menu as the game opens or closes it: the panel's menu-open byte and the avatar's menu-active bit. */
static bool set_menu_in_game(bool open)
{
    uint32_t word = 0;
    uintptr_t at = syn_local_avatar() + DBF_OFF_AVATAR_MENU_OFFSET;
    return syn_poke_u8(syn_panel() + MENU_OPEN_AT, open ? 1 : 0) && syn_read(at, &word, sizeof word) == 0
        && syn_poke_u32(at, open ? word | DBF_VAL_MENU_ACTIVE_MASK : word & ~(uint32_t)DBF_VAL_MENU_ACTIVE_MASK);
}

/* R46 native.lua: text targets and their checked children, relative to the card. */
static const struct { uint32_t container, child; } CARD_TEXT[] = {
    { 0x1f18u, 0x2028u }, { 0x24a8u, 0x25b8u }, { 0x2870u, 0x2980u }
};
static const float TEXT_STYLE[4] = { 0.625f, 0.875f, 0.5f, 0.25f };
static const float CARD_SCALE[2] = { 1.0f, 0.75f };

static bool build_card_graphics(uintptr_t card)
{
    if (!syn_poke(card + 0x14u, CARD_SCALE, sizeof CARD_SCALE)) return false;
    for (size_t j = 0; j < sizeof CARD_TEXT / sizeof CARD_TEXT[0]; j++) {
        uintptr_t widget = card + CARD_TEXT[j].container;
        if (!syn_poke_u64(widget + 0xf0u, card)
            || !syn_poke_u64(card + CARD_TEXT[j].child + 0xf0u, widget)
            || !syn_poke(widget + 0x44u, TEXT_STYLE, sizeof TEXT_STYLE)) return false;
    }
    return true;
}

static bool build_scene(const SynScene* scene)
{
    g_scene = *scene;
    if (!syn_build(scene) || !place_stubs()) return false;
    for (int i = 0; i < 16; i++)
        if (!build_card_graphics(syn_card(i))) return false;
    return true;
}

/* The witnesses a stub overlaps, and how many of their bytes it covers. */
static int overlap(const DbfWitness* w)
{
    int n = 0;
    for (int i = 0; i < FN_HOOK_COUNT; i++)
        for (unsigned b = 0; b < STUB_BYTES; b++) {
            uint32_t at = g_fns[i].rva + b;
            if (at >= w->rva && at - w->rva < w->size) n++;
        }
    return n;
}

static int (*s_byte_calls)(void);
static bool g_skipped; /* no window of this process can take the foreground, or keys do not reach the key state */

/* Everything a code-entry case starts with: the scene, the globals, settings.ini, the stub ranges reported, the fakes'
 * expectation, the window and keys; then init, the game-loaded event and two ticks (game.dll found, every key seen up).
 * False (with a FAIL) when the case cannot go on. */
static bool entry_prepare(const SynScene* scene, const char* settings, uint32_t kind, const uint8_t* code, int n)
{
    void (*add_range)(uint32_t, uint32_t) = (void (*)(uint32_t, uint32_t))need(g_loader, "stub_add_range");
    bool ready;
    s_byte_calls = (int (*)(void))need(g_loader, "stub_byte_calls");
    CHECK(build_scene(scene) && poke_globals(), "the scene is laid out, with the audio and effects globals");
    CHECK(add_range && s_byte_calls && prepare_appdata(CASES[g_case].name, settings),
          "settings.ini is written, and the stub loader takes the stubs' ranges");
    if (!add_range || !s_byte_calls) return false;
    for (int i = 0; i < FN_HOOK_COUNT; i++) add_range(g_fns[i].rva, STUB_BYTES);
    syn_input_reset();
    syn_input_expect(kind, code, n);
    syn_menu_reset();
    ready = keys_and_window();
    if (!ready) {
        g_skipped = true;
        printf("SKIP %s: no window of this process takes the foreground here, or keybd_event does not reach "
               "GetAsyncKeyState (the code-entry cases press keys as a player would)\n",
               CASES[g_case].name);
    }
    return ready;
}

static bool entry_go(void)
{
    run_init();
    fire(HF_EVENT_GAME_LOADED);
    entry_tick();
    entry_tick();
    CHECK(logged(ADMISSION_LINE) == 1, "game.dll found: admission started");
    return true;
}

static bool entry_start(const SynScene* scene, const char* settings, uint32_t kind, const uint8_t* code, int n)
{
    return entry_prepare(scene, settings, kind, code, n) && entry_go();
}

static bool settings_logged(void)
{
    char line[LINE_SIZE], appdata[MAX_PATH];
    if (GetEnvironmentVariableA("LOCALAPPDATA", appdata, sizeof appdata) == 0) return false; /* the CRT's getenv is a copy */
    snprintf(line, sizeof line, "Settings read from %s\\DBF\\HellForge\\settings.ini (0 problems)", appdata);
    return logged(line) == 1;
}

/* The local player's four direction action bytes are released (R46 input.lua:187-188). */
static bool actions_idle(void)
{
    for (uint32_t a = 1; a <= 4; a++) {
        uint8_t byte = 0xee;
        if (syn_read(syn_local_actions() + 32u * a, &byte, 1) != 0 || byte != 0) return false;
    }
    return true;
}

/* The handler took the directions of `code`, in order, each as R46's action. */
static bool handler_took(const uint8_t* code, int n)
{
    if (syn_input_calls() != n || g_calls[FN_INPUT] != n) {
        printf("  handler calls %d (fake %d), expected %d; the window %s in front\n", g_calls[FN_INPUT], syn_input_calls(), n,
               g_foreground != NULL && g_foreground() == g_window ? "is" : "is not");
        return false;
    }
    for (int i = 0; i < n; i++)
        if (syn_input_action(i) != ACTION_OF[code[i]]) {
            printf("  direction %d pressed action %d, expected %d\n", i + 1, syn_input_action(i), ACTION_OF[code[i]]);
            return false;
        }
    return true;
}

/* One direction per tick, at least the interval apart (by the same clock DBF paces with; 5 ms for the read order). */
static bool paced(int n, unsigned interval)
{
    for (int i = 1; i < n && i < MAX_CALLS; i++) {
        if (g_handler_tick[i] == g_handler_tick[i - 1] || g_handler_ms[i] - g_handler_ms[i - 1] + 5u < interval) {
            printf("  directions %d and %d: ticks %d and %d, %llu ms apart\n", i, i + 1, g_handler_tick[i - 1],
                   g_handler_tick[i], (unsigned long long)(g_handler_ms[i] - g_handler_ms[i - 1]));
            return false;
        }
    }
    return true;
}

/* Ticks (5 ms apart) until the handler had `n` calls, or WAIT_MS, then two more. */
static void tick_until_calls(int n)
{
    ULONGLONG until = GetTickCount64() + WAIT_MS;
    while (g_calls[FN_INPUT] < n && GetTickCount64() < until) {
        Sleep(5);
        entry_tick();
    }
    entry_tick();
    entry_tick();
}

static int count_lines_starting(const char* prefix)
{
    int n = 0;
    for (int i = 0; i < g_line_count; i++) n += strncmp(g_lines[i], prefix, strlen(prefix)) == 0;
    return n;
}

/* Every call of the input handler, open, close and request_slot came right after its own checkpoint line (native.h: the
 * last line of the log names the call in progress). */
static bool checkpoints(void)
{
    if (g_checkpoint_misses == 0) return true;
    printf("  %d calls without their checkpoint right before them\n", g_checkpoint_misses);
    return false;
}

/* R46 native.lua reads the widget scale as a float pair at +0x14. Using different X/Y
 * values also catches code that replaces both axes with a single absolute scale. */
static bool native_chosen(int selected)
{
    for (int i = 0; i < 16; i++) {
        float scale[2];
        float factor = i == selected ? 1.10f : 1.0f;
        if (syn_read(syn_card(i) + 0x14u, scale, sizeof scale) != 0) return false;
        for (int axis = 0; axis < 2; axis++) {
            float expected = CARD_SCALE[axis] * factor;
            if (!(scale[axis] >= expected - 0.00001f && scale[axis] <= expected + 0.00001f)) {
                printf("  card %d scale[%d] is %g, expected %g\n", i, axis, scale[axis], expected);
                return false;
            }
        }
        /* Empty cards have no row to dim. Closing the list or starting a slot hotkey
         * restores the same native style on every previously dimmed container. */
        bool dimmed = selected >= 0 && i != selected && g_scene.card_entry[i] != SYN_INACTIVE;
        for (size_t j = 0; j < sizeof CARD_TEXT / sizeof CARD_TEXT[0]; j++) {
            float style[4];
            if (syn_read(syn_card(i) + CARD_TEXT[j].container + 0x44u, style, sizeof style) != 0) return false;
            for (int k = 0; k < 4; k++) {
                float expected = TEXT_STYLE[k] * (dimmed && k != 0 ? 0.35f : 1.0f);
                if (!(style[k] >= expected - 0.00001f && style[k] <= expected + 0.00001f)) {
                    printf("  card %d container %x style[%d] is %g, expected %g\n", i, CARD_TEXT[j].container,
                           k, style[k], expected);
                    return false;
                }
            }
        }
    }
    return true;
}

static bool status_has(const char* line)
{
    if (!s_draw(0)) return false;
    if (find_line(line) >= 0) return true;
    print_drawing();
    return false;
}

static bool sounds_are(const uint32_t* ids, int n)
{
    if (g_sound_count != n) {
        printf("  %d sounds, expected %d\n", g_sound_count, n);
        return false;
    }
    for (int i = 0; i < n; i++)
        if (g_sounds[i] != ids[i]) return false;
    return true;
}

static bool ended(const char* line)
{
    if (logged(line) == 1) return true;
    printf("  no log line \"%s\"\n", line);
    return false;
}

/* Exercise the same exported surface the in-game Lua VM resolves. A second
 * generation must not drive input or release the first generation's lease. */
static void check_hud_handoff(HMODULE dll, const SynStratagem* st)
{
    int (*acquire)(const void*) = (void*)need(dll, "dbf_hud_acquire");
    void (*release)(const void*) = (void*)need(dll, "dbf_hud_release");
    int (*code)(unsigned, unsigned char*, unsigned) = (void*)need(dll, "dbf_hud_code");
    uint64_t (*row)(unsigned) = (void*)need(dll, "dbf_hud_row");
    int (*option)(const char*) = (void*)need(dll, "dbf_hud_option");
    int (*buttons)(void) = (void*)need(dll, "dbf_hud_buttons");
    int (*terminal)(const void*) = (void*)need(dll, "dbf_hud_terminal_active");
    if (!acquire || !release || !code || !row || !option || !buttons || !terminal) return;
    char first = 0, second = 0;
    uint8_t directions[DBF_VAL_CODE_MAX];
    CHECK(!acquire(&first) && !terminal(&first), "Lua waits for C to restore its native HUD before taking ownership");
    entry_tick();
    CHECK(acquire(&first) && !acquire(&second) && native_chosen(-1), "only the claimant owns the restored HUD");
    CHECK(terminal(&first) && !terminal(&second) && !terminal(NULL), "terminal gate requires the exact granted token");
    uintptr_t obstruction = syn_ui() + DBF_OFF_UI_OBSTRUCTION_OFFSET + DBF_OFF_UI_OBSTRUCTION_WORD_OFFSET;
    CHECK(syn_poke_u32(obstruction, 1), "set selector obstruction");
    entry_tick();
    CHECK(buttons() == -1 && terminal(&first), "obstruction blocks selection but allows terminal polling");
    s_set_capturing(1);
    entry_tick();
    CHECK(!terminal(&first), "overlay capture blocks terminal polling");
    s_set_capturing(0);
    CHECK(syn_poke_u32(obstruction, 0), "clear selector obstruction");
    entry_tick();
    uintptr_t state = 0, pm = 0;
    CHECK(syn_read(SYN_GAME_BASE + DBF_RVA_GAME_STATE, &state, sizeof state) == 0 &&
          syn_poke_u32(state + DBF_OFF_GAME_MODE_OFFSET, 3), "leave gameplay with the lease held");
    entry_tick();
    CHECK(!terminal(&first), "terminal gate rejects non-gameplay");
    CHECK(syn_poke_u32(state + DBF_OFF_GAME_MODE_OFFSET, 4) &&
          syn_read(SYN_GAME_BASE + DBF_RVA_PLAYERS, &pm, sizeof pm) == 0 &&
          syn_poke_u32(pm + DBF_OFF_PLAYERS_COUNT_OFFSET, 0), "return to gameplay without a local player");
    entry_tick();
    CHECK(!terminal(&first), "terminal gate requires a local player");
    CHECK(syn_poke_u32(pm + DBF_OFF_PLAYERS_COUNT_OFFSET, 1), "restore local player");
    entry_tick();
    CHECK(terminal(&first), "terminal eligibility recovers on the same lease");
    release(&second);
    CHECK(acquire(&first) && option("selection_mode_ordered") == 1, "a stale claimant cannot release the current HUD");
    CHECK(row(st->kind) && code(st->kind, directions, sizeof directions) == st->code_len &&
          !memcmp(directions, st->code, st->code_len), "Lua receives the admitted HUD row and code");
    CHECK(!code(st->kind, directions, 0) && !row(999), "invalid row and insufficient buffer fail closed");
    key(KEY_NEXT, true);
    entry_tick();
    CHECK((buttons() & 1) && native_chosen(-1), "Lua receives Next while C leaves native selection alone");
    key(KEY_NEXT, false);
    entry_tick();
    release(&first);
    CHECK(!terminal(&first) && !row(st->kind) && buttons() == -1, "release invalidates the HUD frame");
    entry_tick();
    CHECK(native_chosen(0), "fallback selection resumes on its first ready card");
}

/* list-confirm: the default scene (menu open, kinds 118, 4, 50, 63 from the top), Next once, Confirm. */
static void run_list_confirm(HMODULE dll)
{
    static const uint32_t SOUNDS[2] = { DBF_VAL_SOUND_MOVE, DBF_VAL_SOUND_CONFIRM };
    SynScene scene;
    const SynStratagem* st;
    int expected_bytes = 0;
    syn_default(&scene);
    st = &scene.stratagems[1]; /* kind 4: the second row from the top */
    if (!entry_start(&scene, BASE_SETTINGS, st->kind, st->code, st->code_len)) return;
    CHECK(settings_logged(), "DBF read settings.ini, with no problem (its comments included)");
    for (int i = 0; i < dbf_witness_count; i++) {
        int o = overlap(&dbf_witnesses[i]);
        char line[LINE_SIZE];
        if (o == 0) continue;
        expected_bytes += dbf_witnesses[i].size;
        snprintf(line, sizeof line, "witness %s: %d of %u" MASKED_TAIL, dbf_witnesses[i].name, o,
                 (unsigned)dbf_witnesses[i].size);
        CHECK(logged(line) == 1, "a witness under a stub logs the stub's bytes as rewritten, once");
    }
    CHECK(s_byte_calls() == expected_bytes,
          "the loader was asked about single bytes only of the witnesses under a stub (whole witnesses first)");
    CHECK(status_has("text:Code entry: OK") && status_has("text:Select on Release: OK") && status_has("text:Sounds: OK"),
          "code entry, the latch and the sounds are admitted (the stubs are masked)");
    CHECK(status_has("text:Bindings: key:f21 / key:f22 / key:f23") && status_has("text:Settings: settings.ini (0 problems)")
              && status_has("text:Entry: idle"),
          "the Status tab shows the bindings, the settings file and an idle entry");
    CHECK(native_chosen(0), "only the top native card is enlarged");

    s_set_capturing(1);
    tap(KEY_NEXT);
    CHECK(native_chosen(0) && g_sound_count == 0, "API 8 capture blocks Next without a panel draw");
    s_set_capturing(0);
    entry_tick();
    CHECK(syn_poke_u32(syn_ui() + 0x429cu + 20u, 1), "a game menu covers the HUD (R46 input.lua:294-295)");
    tap(KEY_NEXT);
    CHECK(native_chosen(0) && g_sound_count == 0, "while the UI is obstructed, Next does nothing");
    CHECK(syn_poke_u32(syn_ui() + 0x429cu + 20u, 0), "the game menu goes");
    entry_tick();
    tap(KEY_NEXT);
    CHECK(native_chosen(1), "Next chooses the second row");
    CHECK(g_sound_count == 1 && g_sounds[0] == DBF_VAL_SOUND_MOVE, "and plays the move sound");

    key(KEY_CONFIRM, true);
    entry_tick();
    CHECK(g_sound_count == 2 && g_sounds[1] == DBF_VAL_SOUND_CONFIRM && g_calls[FN_INPUT] == 0,
          "Confirm starts the entry with the confirm sound; the first direction goes on the next tick");
    key(KEY_CONFIRM, false);
    tick_until_calls(st->code_len);
    CHECK(handler_took(st->code, st->code_len), "the handler took the second row's code, direction by direction");
    CHECK(paced(st->code_len, INTERVAL_MS), "one direction per tick, at least 60 ms apart (input_interval_ms)");
    CHECK(actions_idle(), "the action bytes are 0 again");
    CHECK(status_has("text:Entry: done"), "the Status tab says the entry is done");
    CHECK(ended("Code entry done: Orbital Gatling Barrage (every change put back)"), "and the log says so");
    CHECK(sounds_are(SOUNDS, 2), "two sounds in all: the move and the confirm");
    CHECK(checkpoints(), "every handler call came right after its checkpoint line");
    CHECK(g_write_no >= 2 * st->code_len && syn_write_count() == 0, "a press and a release per direction");
    CHECK(g_calls[FN_OPEN] == 0 && g_calls[FN_CLOSE] == 0 && g_calls[FN_REQUEST] == 0,
          "a List job opens, closes and requests nothing");
    check_hud_handoff(dll, st);
    end_keys();
}

/* instant: the top row (kind 118, three directions) with instant_stratagems. */
static void run_instant(void)
{
    static const char SETTINGS[] = "[dbf]\ninstant_stratagems = true\n";
    char text[sizeof BASE_SETTINGS + sizeof SETTINGS];
    SynScene scene;
    const SynStratagem* st;
    int calls;
    syn_default(&scene);
    st = &scene.stratagems[0];
    snprintf(text, sizeof text, "%s%s", BASE_SETTINGS, SETTINGS);
    if (!entry_start(&scene, text, st->kind, st->code, st->code_len)) return;
    key(KEY_CONFIRM, true);
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 0 && g_sound_count == 1, "Confirm starts the job (the confirm sound)");
    entry_tick();
    CHECK(g_calls[FN_INPUT] == st->code_len - 1 && g_handler_tick[0] == g_handler_tick[st->code_len - 2],
          "the next tick sends every direction but the last, at once");
    Sleep(150);
    entry_tick();
    CHECK(g_calls[FN_INPUT] == st->code_len - 1, "the last waits while Confirm is held, 150 ms later too");
    key(KEY_CONFIRM, false);
    entry_tick();
    calls = g_calls[FN_INPUT];
    CHECK(calls == st->code_len - 1, "and for 100 ms after it is let go");
    Sleep(150);
    entry_tick();
    CHECK(handler_took(st->code, st->code_len), "then the last direction goes");
    CHECK(actions_idle() && status_has("text:Entry: done"), "done, the action bytes 0");
    CHECK(ended("Code entry done: Orbital Precision Strike (every change put back)"), "and the log says so");
    end_keys();
}

/* menu-close and mission-end: the top row paced, then the game closes the menu, or the mission ends, after one direction. */
static void run_interrupted(bool mission)
{
    static const char SETTINGS[] = "[dbf]\nselection_sounds = false\n";
    char text[sizeof BASE_SETTINGS + sizeof SETTINGS];
    SynScene scene;
    const SynStratagem* st;
    const char* line = mission ? "Code entry failed: the mission ended (every change put back)"
                               : "Code entry failed: menu closed (every change put back)";
    syn_default(&scene);
    st = &scene.stratagems[0];
    snprintf(text, sizeof text, "%s%s", BASE_SETTINGS, SETTINGS);
    if (!entry_start(&scene, text, st->kind, st->code, st->code_len)) return;
    tap(KEY_CONFIRM);
    tick_until_calls(1);
    CHECK(g_calls[FN_INPUT] >= 1, "the first direction went");
    CHECK(g_sound_count == 0, "selection_sounds = false: no confirm sound");
    if (mission) {
        uintptr_t state = 0;
        CHECK(syn_read(SYN_GAME_BASE + DBF_RVA_GAME_STATE, &state, sizeof state) == 0
                  && syn_poke_u32(state + DBF_OFF_GAME_MODE_OFFSET, 3u),
              "the mission ends");
    } else {
        CHECK(set_menu_in_game(false), "the player lets go of the menu");
    }
    Sleep(INTERVAL_MS + 20u);
    entry_tick();
    entry_tick();
    CHECK(g_calls[FN_INPUT] < st->code_len, "the code stops there");
    CHECK(actions_idle(), "the action bytes are 0");
    CHECK(ended(line), mission ? "failed: the mission ended; nothing is left to put back"
                               : "failed: menu closed; nothing is left to put back");
    CHECK(status_has(mission ? "text:Entry: failed: the mission ended" : "text:Entry: failed: menu closed"),
          "the Status tab says why");
    if (!mission) {
        int before = g_calls[FN_INPUT];
        CHECK(native_chosen(-1), "closing the menu restores native scale on every card");
        CHECK(set_menu_in_game(true), "the player holds the menu again");
        entry_tick();
        CHECK(native_chosen(0), "the list opens as before, the top row chosen");
        syn_input_reset();
        syn_input_expect(st->kind, st->code, st->code_len);
        CHECK(syn_poke_u32(syn_local_component(), 0) && syn_poke_u32(syn_local_component() + 0x14u, 0),
              "(the game clears its input when the menu closes)");
        g_calls[FN_INPUT] = 0;
        tap(KEY_CONFIRM);
        tick_until_calls(st->code_len);
        CHECK(before >= 1 && handler_took(st->code, st->code_len) && status_has("text:Entry: done"),
              "and a new Confirm enters the code whole");
    }
    end_keys();
}

/* The shortcut scene (as test_latch's): eight payload entries, the equipped slots 1..4 entries 4..7 (kinds 118, 4, 50,
 * 63), every card showing one; the menu closed. */
static void shortcut_scene(SynScene* scene)
{
    static const uint32_t KINDS[8] = { 10, 11, 12, 13, 118, 4, 50, 63 };
    static const uint8_t CODE[4] = { 1, 2, 3, 4 };
    syn_default(scene);
    scene->stratagem_count = 8;
    scene->menu_open = 0;
    for (int i = 0; i < 8; i++) {
        scene->stratagems[i].kind = KINDS[i];
        scene->stratagems[i].code_len = 3;
        memcpy(scene->stratagems[i].code, (const uint8_t[3]){ 1, 3, 2 }, 3);
        scene->card_entry[i] = i;
    }
    scene->stratagems[4].code_len = 4;
    memcpy(scene->stratagems[4].code, CODE, sizeof CODE);
}

/* SYN_MENU_RECORDS[0] and [2] as R46's latch patches them (menu_latch.lua:71): flags - trigger * 65536, the trigger 0. */
static const uint8_t HOLD_PATCHED[20] = { 0x43, 0x00, 0x10, 0x00, 0x4b, 0x00, 0x00, 0x00, 0x00, 0x00,
                                          0x00, 0x00, 0x11, 0x00, 0x00, 0x00, 0x22, 0x00, 0x00, 0x00 };
static const uint8_t LONG_HOLD_PATCHED[20] = { 0x47, 0x00, 0x30, 0x00, 0x02, 0x20, 0x00, 0x00, 0x00, 0x00,
                                               0x00, 0x00, 0x55, 0x00, 0x00, 0x00, 0x66, 0x00, 0x00, 0x00 };

static bool record_is(int record, const uint8_t want[20])
{
    uint8_t now[20] = { 0 };
    return syn_read(syn_binding_record(syn_menu_bucket(), record), now, sizeof now) == 0 && memcmp(now, want, 20) == 0;
}

static uint32_t u32_at(uintptr_t at)
{
    uint32_t v = 0xeeeeeeeeu;
    syn_read(at, &v, sizeof v);
    return v;
}

static bool latched(void)
{
    return record_is(0, HOLD_PATCHED) && record_is(1, SYN_MENU_RECORDS[1]) && record_is(2, LONG_HOLD_PATCHED)
        && u32_at(syn_controls_menu_trigger()) == 0 && u32_at(syn_local_menu_trigger()) == 0;
}

static bool originals(void)
{
    return record_is(0, SYN_MENU_RECORDS[0]) && record_is(1, SYN_MENU_RECORDS[1]) && record_is(2, SYN_MENU_RECORDS[2])
        && u32_at(syn_controls_menu_trigger()) == 2 && u32_at(syn_local_menu_trigger()) == 2;
}

/* The game builds another HUD (another root, ready, its menu-open byte 1), or puts the first one back. */
static bool replace_hud(bool other_one)
{
    const uintptr_t other = (uintptr_t)0x3f000000000ull;
    static uintptr_t first;
    if (first == 0) syn_read(SYN_GAME_BASE + DBF_RVA_HUD_ROOT, &first, sizeof first);
    return syn_poke_u8(other + DBF_OFF_HUD_READY_OFFSET, 1)
        && syn_poke_u8(other + DBF_OFF_HUD_PANEL_OFFSET + DBF_OFF_OPEN_BYTE_OFFSET, 1)
        && syn_poke_u64(SYN_GAME_BASE + DBF_RVA_HUD_ROOT, other_one ? other : first);
}

/* Slot 1's key pressed from a closed menu: the latch, open and request_slot, the confirm sound. */
static void press_slot1(int opens_before)
{
    key(KEY_SLOT1, true);
    entry_tick();
    CHECK(latched(), "slot 1's key: the Hold and LongHold records are Press, both dwords 0");
    CHECK(g_calls[FN_OPEN] == opens_before + 1 && syn_menu_stray_calls() == 0, "DBF opened the menu");
}

/* Lua resolves equipped shortcuts before opening the stock menu. */
static void check_closed_slot_codes(HMODULE dll, const SynScene* scene)
{
    int (*acquire)(const void*) = (void*)need(dll, "dbf_hud_acquire");
    void (*release)(const void*) = (void*)need(dll, "dbf_hud_release");
    int (*code)(unsigned, unsigned char*, unsigned) = (void*)need(dll, "dbf_hud_code");
    uint64_t (*row)(unsigned) = (void*)need(dll, "dbf_hud_row");
    if (!acquire || !release || !code || !row) return;
    char token = 0;
    uint8_t dirs[DBF_VAL_CODE_MAX];
    unsigned first = scene->stratagems[4].kind;
    CHECK(!acquire(&token), "request the HUD in a closed zero-card scene");
    entry_tick();
    CHECK(acquire(&token), "zero active cards still allow a HUD lease");
    for (int i = 4; i < 8; ++i) {
        const SynStratagem* st = &scene->stratagems[i];
        CHECK(!row(st->kind) && code(st->kind, dirs, sizeof dirs) == st->code_len &&
              !memcmp(dirs, st->code, st->code_len), "equipped slot supplies its code without a presentation row");
    }
    CHECK(!code(first, dirs, 1) && !code(scene->stratagems[0].kind, dirs, sizeof dirs),
          "short buffers and unequipped cardless kinds fail closed");
    uintptr_t count = syn_payload(scene->local_entry) + DBF_OFF_PAYLOAD_COUNT_OFFSET;
    CHECK(syn_poke_u32(count, 7), "invalidate the local equipped payload");
    entry_tick();
    CHECK(!code(first, dirs, sizeof dirs), "the next publication withdraws stale equipped codes");
    CHECK(syn_poke_u32(count, 8), "restore the equipped payload");
    entry_tick();
    CHECK(code(first, dirs, sizeof dirs) == scene->stratagems[4].code_len, "equipped code recovers");
    release(&token);
    CHECK(!code(first, dirs, sizeof dirs), "release withdraws equipped codes immediately");
}

/* shortcut: slot 1 (kind 118, four directions) from a closed menu, one direction per tick, the key held to the end. */
static void run_shortcut(HMODULE dll)
{
    static const char SETTINGS[] = "[dbf]\ninput_interval_ms = 0\n";
    char text[sizeof BASE_SETTINGS + sizeof SETTINGS];
    SynScene scene;
    const SynStratagem* st;
    shortcut_scene(&scene);
    for (int i = 0; i < (int)DBF_VAL_CARD_COUNT; ++i) scene.card_entry[i] = SYN_INACTIVE;
    st = &scene.stratagems[4];
    snprintf(text, sizeof text, "%s%s", BASE_SETTINGS, SETTINGS);
    if (!entry_start(&scene, text, st->kind, st->code, st->code_len)) return;
    CHECK(set_menu_in_game(false), "(the menu is closed in the game)");
    entry_tick();
    CHECK(originals(), "before: the menu binding is Hold, both trigger dwords 2");

    check_closed_slot_codes(dll, &scene);
    entry_tick(); /* The fallback owner samples released keys before its next rising edge. */
    press_slot1(0);
    CHECK(g_calls[FN_REQUEST] == 1 && syn_requested_slot() == 5, "and asked for the stratagem slot (5)");
    CHECK(g_sound_count == 1 && g_sounds[0] == DBF_VAL_SOUND_CONFIRM, "with the confirm sound");
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 1 && latched(), "the first direction goes on the next tick, the latch held");
    Sleep(SOUND_GAP_MS); /* past the move sound's throttle, so a move would be heard */
    tap(KEY_NEXT);
    CHECK(g_sound_count == 1, "Next during a slot hotkey moves nothing (List Select sees a closed list)");
    CHECK(native_chosen(-1), "all native cards retain their original scale during the slot hotkey");
    tick_until_calls(st->code_len);
    CHECK(handler_took(st->code, st->code_len), "the handler took slot 1's code");
    CHECK(latched(), "the code is in; the latch stays until the game closes the menu");
    CHECK(set_menu_in_game(false), "the game closes the menu (the stratagem is in hand)");
    entry_tick();
    CHECK(originals(), "the menu binding is Hold again, both dwords 2");
    CHECK(g_calls[FN_CLOSE] == 0, "DBF closed nothing: the game did");
    CHECK(ended("Code entry done: Orbital Precision Strike (every change put back)"), "the log says done");
    entry_tick();
    entry_tick();
    CHECK(g_calls[FN_OPEN] == 1 && count_lines_starting("Slot 1: entering") == 1,
          "slot 1's key, still held, starts nothing more (a press is a rising edge)");
    key(KEY_SLOT1, false);
    entry_tick();
    CHECK(status_has("text:Entry: done") && actions_idle(), "the Status tab says done; the action bytes are 0");
    CHECK(checkpoints() && count_lines_starting("call open_input(") == 1 && count_lines_starting("call request_slot(") == 1,
          "every game call came right after its checkpoint line");
    end_keys();
}

/* shortcut-hud: the HUD is replaced during a slot hotkey's code, then (the first HUD back) after a second one's code was
 * in, while it waits for the game to close the menu (R46's c.hud == job.hud, input.lua:367 and 382). Each time: cancelled,
 * the latch back, and the menu DBF opened closed. */
static void run_shortcut_hud(void)
{
    static const char SETTINGS[] = "[dbf]\ninput_interval_ms = 0\n";
    char text[sizeof BASE_SETTINGS + sizeof SETTINGS];
    SynScene scene;
    const SynStratagem* st;
    shortcut_scene(&scene);
    st = &scene.stratagems[4];
    snprintf(text, sizeof text, "%s%s", BASE_SETTINGS, SETTINGS);
    if (!entry_start(&scene, text, st->kind, st->code, st->code_len)) return;
    CHECK(set_menu_in_game(false), "(the menu is closed in the game)");
    entry_tick();

    press_slot1(0);
    key(KEY_SLOT1, false);
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 1, "the first direction went");
    CHECK(replace_hud(true), "the game replaces the HUD during the code");
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 1, "no direction goes after that");
    CHECK(ended("Code entry failed: the HUD changed (every change put back)"), "cancelled: the HUD changed");
    CHECK(originals() && g_calls[FN_CLOSE] == 1 && actions_idle(),
          "the menu binding is Hold again, the menu DBF opened closed, the action bytes 0");
    CHECK(status_has("text:Entry: failed: the HUD changed"), "the Status tab says why");

    CHECK(replace_hud(false) && syn_poke_u32(syn_local_component(), 0), "the first HUD is back; the game cleared its input");
    syn_input_reset();
    syn_input_expect(st->kind, st->code, st->code_len);
    g_calls[FN_INPUT] = 0;
    entry_tick();
    press_slot1(1);
    key(KEY_SLOT1, false);
    tick_until_calls(st->code_len);
    CHECK(handler_took(st->code, st->code_len) && latched(), "a second slot hotkey's code is in; the latch held");
    CHECK(replace_hud(true), "the game replaces the HUD while the menu is still open");
    entry_tick();
    CHECK(count_lines_starting("Code entry failed: the HUD changed (every change put back)") == 2,
          "cancelled again: the HUD changed");
    CHECK(originals() && g_calls[FN_CLOSE] == 2, "the latch is back and the menu DBF opened is closed");
    end_keys();
}

/* mod-stratagem: HellForge moved the definition table and added kind 151; its code array lies in the stub loader's own
 * image (where HellForge keeps a mod stratagem's code); the second row shows it. */
static void run_mod_stratagem(void)
{
    static const uint8_t MOD_CODE[4] = { 4, 3, 2, 1 };
    void* (*area)(uint32_t*) = (void* (*)(uint32_t*))need(g_loader, "stub_code_area");
    SynScene scene;
    uintptr_t row, payload;
    uint32_t size = 0;
    syn_default(&scene);
    if (!area) return;
    if (!entry_start(&scene, BASE_SETTINGS, 151, MOD_CODE, 4)) return;
    payload = syn_payload(scene.local_entry);
    row = syn_move_table((int32_t)(SYN_IMAGE_SIZE + 0x10000u)) ? syn_add_mod_stratagem(151, 4, MOD_CODE) : 0;
    CHECK(row != 0 && syn_set_code(row, (uintptr_t)area(&size), 4, MOD_CODE) && size >= 16
              && syn_poke_u32(payload + DBF_OFF_PAYLOAD_KINDS_OFFSET + DBF_OFF_PAYLOAD_ENTRY_STRIDE * 1u, 151),
          "kind 151 is in the payload (the second card), its code array inside hellforge_modloader.dll's image");
    CHECK(build_card_graphics(syn_card(1)), "the game repaints the replacement card with its original style");
    entry_tick();
    CHECK(status_has("text:Stratagem 151") && status_has("text:< v > ^"), "the Status tab lists it with its code");
    tap(KEY_NEXT);
    CHECK(native_chosen(1), "Next chooses it");
    tap(KEY_CONFIRM);
    tick_until_calls(4);
    CHECK(handler_took(MOD_CODE, 4) && actions_idle(), "its code is entered");
    CHECK(ended("Code entry done: Stratagem 151 (every change put back)"), "done");
    end_keys();
}

/* scramble: an effect is on (the fake query says so) and the local avatar's seed is 113, so kind 4 is entered with kind
 * ((4 + 113) mod 149) + 1 = 118's code (R46 input.lua:150-157); the game reports the kind asked for. */
static void run_scramble(void)
{
    SynScene scene;
    const SynStratagem* shown;
    syn_default(&scene);
    scene.scramble_seed = 113;
    g_scramble_remap = true;
    shown = &scene.stratagems[0]; /* kind 118: whose code kind 4 takes */
    if (!entry_start(&scene, BASE_SETTINGS, 4, shown->code, shown->code_len)) return;
    CHECK(g_calls[FN_SCRAMBLE] > 0 && status_has("text:Scrambled codes: OK") && !status_has("text:Codes do not follow scrambling yet"),
          "the scramble query runs, and the codes follow it");
    tap(KEY_NEXT);
    CHECK(native_chosen(1), "Next chooses kind 4");
    tap(KEY_CONFIRM);
    tick_until_calls(shown->code_len);
    CHECK(handler_took(shown->code, shown->code_len), "the remapped code (kind 118's) is entered");
    CHECK(actions_idle() && ended("Code entry done: Orbital Gatling Barrage (every change put back)"),
          "and the game matched kind 4: done");
    end_keys();
}

/* no-entry-admission: a byte of append_and_match (an ENTRY witness under no stub) differs: ENTRY waits. */
static void run_no_entry_admission(void)
{
    const DbfWitness* w = witness("append_and_match");
    SynScene scene;
    uint8_t byte = 0;
    const char* why = "witness append_and_match differs (retrying)";
    char line[LINE_SIZE];
    syn_default(&scene);
    CHECK(w != NULL && overlap(w) == 0, "append_and_match is an ENTRY witness no stub covers");
    if (!w || !entry_prepare(&scene, BASE_SETTINGS, 4, scene.stratagems[1].code, scene.stratagems[1].code_len)) return;
    CHECK(syn_read(SYN_GAME_BASE + w->rva + 5u, &byte, 1) == 0 && syn_poke_u8(SYN_GAME_BASE + w->rva + 5u, (uint8_t)(byte ^ 0xffu)),
          "a byte of append_and_match differs from the table");
    if (!entry_go()) return;
    snprintf(line, sizeof line, "text:Code entry: Waiting (%s)", why);
    CHECK(status_has(line), "the Status tab says code entry waits, and why");
    tap(KEY_NEXT);
    CHECK(native_chosen(1) && g_sound_count == 1 && g_sounds[0] == DBF_VAL_SOUND_MOVE,
          "Next still moves the choice, with its sound");
    tap(KEY_CONFIRM);
    entry_tick();
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 0 && g_write_no == 0 && g_sound_count == 1,
          "Confirm sends nothing, writes nothing and plays no confirm sound");
    snprintf(line, sizeof line, "text:Entry: failed: Code entry: %s", why);
    CHECK(status_has(line), "the Status tab says why the code was not entered");
    snprintf(line, sizeof line, "Orbital Gatling Barrage not entered: Code entry: %s", why);
    CHECK(ended(line), "and so does the log");
    end_keys();
}

/* A compatible settings window on API 5 still lacks the capture query. */
static void run_old_host_input(void)
{
    SynScene scene;
    syn_default(&scene);
    const SynStratagem* st = &scene.stratagems[0];
    if (!entry_start(&scene, BASE_SETTINGS, st->kind, st->code, st->code_len)) return;
    CHECK(s_panel_count() == 1, "the old host registers the settings window");
    tap(KEY_NEXT);
    tap(KEY_CONFIRM);
    CHECK(native_chosen(0) && actions_idle() && g_calls[FN_INPUT] == 0 && g_sound_count == 0,
          "the old host blocks Next and Confirm before any window draws");
    end_keys();
}

/* no-host-entry: no goose_overlay.dll; Confirm on a key enters the top row's code all the same. */
static void run_no_host_entry(void)
{
    SynScene scene;
    const SynStratagem* st;
    syn_default(&scene);
    st = &scene.stratagems[0];
    if (!entry_start(&scene, BASE_SETTINGS, st->kind, st->code, st->code_len)) return;
    CHECK(native_chosen(0), "the native card graphics work without an Overlay Host");
    CHECK(logged(NO_HOST_LINE) == 1 && g_ticker_count == 1, "one line says what runs without the host; HellForge's tick");
    tap(KEY_CONFIRM);
    tick_until_calls(st->code_len);
    CHECK(handler_took(st->code, st->code_len) && actions_idle(), "Confirm on its key enters the top row's code");
    CHECK(paced(st->code_len, INTERVAL_MS), "paced as the settings say");
    CHECK(ended("Code entry done: Orbital Precision Strike (every change put back)"), "done");
    CHECK(g_sound_count == 1 && g_sounds[0] == DBF_VAL_SOUND_CONFIRM, "with the confirm sound");
    CHECK(logged(NO_HOST_LINE) == 1, "the no-host line is still logged once");
    end_keys();
}

/* release-retry: the write that releases the first direction fails once (Task 10's ruling: the entry stays journaled and
 * the tick retries it), so the job fails with the direction still pressed, and the next tick puts the byte back. */
static void run_release_retry(void)
{
    SynScene scene;
    const SynStratagem* st;
    uint8_t byte = 0xee;
    syn_default(&scene);
    st = &scene.stratagems[0];
    if (!entry_start(&scene, BASE_SETTINGS, st->kind, st->code, st->code_len)) return;
    g_fail_write = g_write_no + 2; /* the first direction's press works, its release does not */
    tap(KEY_CONFIRM);
    CHECK(g_calls[FN_INPUT] == 1 && syn_read(syn_local_actions() + 32u * (uint32_t)ACTION_OF[st->code[0]], &byte, 1) == 0
              && byte == 1,
          "the first direction went and its action byte could not be released");
    CHECK(ended("Code entry failed: direction could not be released (1 change not put back yet: DBF tries again each tick)"),
          "the job failed, and the log says one change is still to be put back");
    entry_tick();
    CHECK(actions_idle(), "the next tick wrote the release again: the action bytes are 0");
    CHECK(ended("Every change DBF made to the game is put back"), "and the log says so");
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 1 && logged("Every change DBF made to the game is put back") == 1, "nothing more happens");

    /* Then a code the HUD goes away under (its ready byte 0: R46's snapshot gone). */
    CHECK(syn_poke_u32(syn_local_component(), 0), "(the game cleared its input)");
    syn_input_reset();
    syn_input_expect(st->kind, st->code, st->code_len);
    g_calls[FN_INPUT] = 0;
    tap(KEY_CONFIRM);
    CHECK(g_calls[FN_INPUT] == 1, "a new Confirm: its first direction went");
    CHECK(syn_poke_u8(syn_hud_root() + DBF_OFF_HUD_READY_OFFSET, 0), "the HUD goes away");
    Sleep(INTERVAL_MS + 20u);
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 1 && actions_idle() && ended("Code entry failed: the HUD went away (every change put back)"),
          "the code stops: the HUD went away; the action bytes are 0");
    end_keys();
}

/* card-gone: the top row's card (kind 118) turns unavailable after the first direction (its timer state 5): the list no
 * longer offers it, so the job stops (R46 selection.lua:49-51). */
static void run_card_gone(void)
{
    SynScene scene;
    const SynStratagem* st;
    uintptr_t timer;
    syn_default(&scene);
    st = &scene.stratagems[0];
    if (!entry_start(&scene, BASE_SETTINGS, st->kind, st->code, st->code_len)) return;
    tap(KEY_CONFIRM);
    CHECK(g_calls[FN_INPUT] == 1, "the first direction went");
    timer = syn_card(0) + DBF_OFF_CARD_TIMER_OFFSET;
    CHECK(syn_poke_u32(timer + DBF_OFF_CARD_TIMER_STATE_OFFSET, DBF_VAL_TIMER_STATE_UNAVAILABLE),
          "the game marks its card unavailable");
    Sleep(INTERVAL_MS + 20u);
    entry_tick();
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 1 && actions_idle(), "no direction goes after that; the action bytes are 0");
    CHECK(ended("Code entry failed: card membership changed (every change put back)"), "failed: card membership changed");
    CHECK(status_has("text:Entry: failed: card membership changed"), "the Status tab says why");
    end_keys();
}

/* shortcut-blocked: API 8 reports capture after a slot hotkey's first direction. */
static void run_shortcut_blocked(void)
{
    static const char SETTINGS[] = "[dbf]\ninput_interval_ms = 0\n";
    char text[sizeof BASE_SETTINGS + sizeof SETTINGS];
    SynScene scene;
    const SynStratagem* st;
    shortcut_scene(&scene);
    st = &scene.stratagems[4];
    snprintf(text, sizeof text, "%s%s", BASE_SETTINGS, SETTINGS);
    if (!entry_start(&scene, text, st->kind, st->code, st->code_len)) return;
    CHECK(set_menu_in_game(false), "(the menu is closed in the game)");
    entry_tick();
    press_slot1(0);
    key(KEY_SLOT1, false);
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 1, "the first direction went");
    s_set_capturing(1);
    entry_tick();
    CHECK(g_calls[FN_INPUT] == 1 && actions_idle(), "no direction goes after that; the action bytes are 0");
    CHECK(ended("Code entry failed: an Overlay Host window is open (every change put back)"),
          "failed: an Overlay Host window is open");
    CHECK(originals(), "the menu binding is Hold again, both dwords 2");
    CHECK(g_calls[FN_CLOSE] == 1 && checkpoints(), "the menu DBF opened is closed");
    s_set_capturing(0);
    entry_tick();
    CHECK(syn_poke_u32(syn_local_component(), 0), "the game clears the cancelled direction when its menu closes");
    press_slot1(1);
    key(KEY_SLOT1, false);
    end_keys();
}

/* latch-retry: Task 12 fix round I1 and M3. First a slot hotkey the game does not open the menu for: its latch release
 * cannot write the actions dword; the refusal says so, and the next tick puts it back for the latch's own player (the
 * dword reads 2 again). Then a slot hotkey that ran: the game closes the menu, the release cannot write the same dword,
 * the player respawns (another key), and the retry leaves the old block's dword alone, as R46 does for a changed
 * player. */
static void run_latch_retry(void)
{
    static const char SETTINGS[] = "[dbf]\ninput_interval_ms = 0\n";
    char text[sizeof BASE_SETTINGS + sizeof SETTINGS];
    SynScene scene;
    const SynStratagem* st;
    shortcut_scene(&scene);
    st = &scene.stratagems[4];
    snprintf(text, sizeof text, "%s%s", BASE_SETTINGS, SETTINGS);
    if (!entry_start(&scene, text, st->kind, st->code, st->code_len)) return;
    CHECK(set_menu_in_game(false), "(the menu is closed in the game)");
    entry_tick();

    syn_open_answers(0, false);
    g_fail_write = g_write_no + 5; /* the latch's four swaps work; the release's first write (the actions dword) fails */
    key(KEY_SLOT1, true);
    entry_tick();
    key(KEY_SLOT1, false);
    CHECK(ended("Slot 1 not entered: the game did not open the menu (1 change not put back yet: DBF tries again each "
                "tick)"),
          "a refused slot hotkey says one change is still to be put back");
    CHECK(u32_at(syn_local_menu_trigger()) == 0 && u32_at(syn_controls_menu_trigger()) == 2,
          "(the actions dword still reads the latch's 0)");
    entry_tick();
    CHECK(originals() && ended("Every change DBF made to the game is put back"),
          "the next tick puts it back for the latch's own player: every record and dword reads its original");

    syn_open_answers(1, true);
    press_slot1(1);
    key(KEY_SLOT1, false);
    tick_until_calls(st->code_len);
    CHECK(handler_took(st->code, st->code_len) && latched(), "a second slot hotkey's code is in; the latch held");
    g_fail_write = g_write_no + 1; /* the release's first write (the actions dword) fails */
    CHECK(set_menu_in_game(false), "the game closes the menu");
    entry_tick();
    CHECK(ended("Code entry done: Orbital Precision Strike (1 change not put back yet: DBF tries again each tick)"),
          "done, with one change still to be put back");
    CHECK(syn_respawn_local(syn_local_key() ^ 0x100u), "the player respawns before the retry (another key)");
    entry_tick();
    CHECK(u32_at(syn_local_menu_trigger()) == 0, "the retry did not write the old player's actions dword");
    CHECK(record_is(0, SYN_MENU_RECORDS[0]) && record_is(2, SYN_MENU_RECORDS[2]) && u32_at(syn_controls_menu_trigger()) == 2,
          "the records and the controls dword are back");
    CHECK(logged("latch: the player changed; the old player's menu trigger was left alone") == 1
              && logged("Every change DBF made to the game is put back") == 2,
          "and the log says the old player's trigger was left alone, and that nothing is left");
    end_keys();
}

/* --- main ------------------------------------------------------------------------------------------------------ */

int main(int argc, char** argv)
{
    const char* name;
    HMODULE dll;
    bool known = false;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 3) {
        puts("usage: wine_host.exe <divers_best_friend.dll> <case> [<goose_overlay.dll>] [<hellforge_modloader.dll>]\n"
             "cases: no-host host-api3 host-api4 host-api5 no-tick retry on-at-once late-module second-loaded null-panel"
             " on-fails masked-log list-confirm instant menu-close mission-end shortcut shortcut-hud mod-stratagem"
             " scramble no-entry-admission old-host-input no-host-entry release-retry card-gone shortcut-blocked latch-retry");
        return 2;
    }
    name = argv[2];
    for (size_t i = 0; i < sizeof CASES / sizeof CASES[0]; i++)
        if (strcmp(name, CASES[i].name) == 0) {
            g_case = (CaseId)i;
            known = true;
        }
    if (!known || argc < 3 + (CASES[g_case].stub ? 1 : 0) + (CASES[g_case].loader ? 1 : 0)) {
        printf("FAIL unknown case \"%s\" or a missing stub\n", name);
        return 2;
    }
    printf("== %s\n", CASES[g_case].title);
    CreateThread(NULL, 0, watchdog, NULL, 0, NULL);
    /* First, before any DLL or heap block can land there. */
    CHECK(map_game_code(), "game.dll's code pages are mapped, with a 12-byte stub at each game function DBF calls");

    syn_default(&g_scene);
    CHECK(build_scene(&g_scene), "the synthetic 25480438 image builds, with the generated witness table and the stubs");
    if (!CASES[g_case].entry) CHECK(prepare_appdata(name, NULL), "a LOCALAPPDATA of its own, with no settings.ini");

    g_api.version = HF_MOD_SDK_VERSION;
    g_api.size = sizeof g_api;
    g_api.log = api_log;
    g_api.build_id = api_build_id;
    g_api.mod_id = api_mod_id;
    g_api.mod_folder = api_mod_folder;
    g_api.on = g_case == C_ON_AT_ONCE ? api_on_at_once : g_case == C_ON_FAILS ? api_on_fails : api_on;
    g_api.module_base = api_module_base;
    g_api.read = api_read;
    g_api.write = CASES[g_case].entry ? api_write : syn_write;
    g_api.stratagem_row = syn_stratagem_row;
    g_api.on_game_thread = g_case == C_NO_TICK ? api_refuse_game_thread : api_on_game_thread;
    g_api.read_code = api_read_code;
    g_ticks_via_host = g_case == C_API5 || (CASES[g_case].entry && CASES[g_case].stub);

    /* The stubs first, so DBF finds them by name as it finds the real ones (GetModuleHandleA). */
    if (CASES[g_case].stub) {
        bool exports;
        g_stub = LoadLibraryA(argv[3]);
        CHECK(g_stub != NULL && GetModuleHandleA("goose_overlay.dll") == g_stub,
              "the stub Overlay Host loads as goose_overlay.dll");
        exports = load_stub(g_stub);
        CHECK(exports, "the stub exports what the host reads");
        if (!g_stub || !exports) return 1;
    } else {
        CHECK(GetModuleHandleA("goose_overlay.dll") == NULL, "no goose_overlay.dll is loaded");
    }
    if (CASES[g_case].loader) {
        g_loader = LoadLibraryA(argv[CASES[g_case].stub ? 4 : 3]);
        CHECK(g_loader != NULL && GetModuleHandleA("hellforge_modloader.dll") == g_loader,
              "the stub loader loads as hellforge_modloader.dll");
        if (!g_loader) return 1;
    } else {
        CHECK(GetModuleHandleA("hellforge_modloader.dll") == NULL, "no hellforge_modloader.dll is loaded");
    }

    dll = LoadLibraryA(argv[1]);
    g_init = dll ? (int (*)(const HfApi*, HfMod*))need(dll, "hellforge_mod_init") : NULL;
    CHECK(dll != NULL && g_init != NULL, "divers_best_friend.dll loads and exports hellforge_mod_init");
    if (!g_init) return 1;

    switch (g_case) {
    case C_RETRY: run_retry(); break;
    case C_ON_AT_ONCE: run_on_at_once(); break;
    case C_LATE_MODULE: run_late_module(); break;
    case C_SECOND_LOADED: run_second_loaded(); break;
    case C_NULL_PANEL: run_null_panel(); break;
    case C_ON_FAILS: run_on_fails(); break;
    case C_MASKED_LOG: run_masked_log(); break;
    case C_LIST_CONFIRM: run_list_confirm(dll); break;
    case C_INSTANT: run_instant(); break;
    case C_MENU_CLOSE: run_interrupted(false); break;
    case C_MISSION_END: run_interrupted(true); break;
    case C_SHORTCUT: run_shortcut(dll); break;
    case C_SHORTCUT_HUD: run_shortcut_hud(); break;
    case C_MOD_STRATAGEM: run_mod_stratagem(); break;
    case C_SCRAMBLE: run_scramble(); break;
    case C_NO_ENTRY_ADMISSION: run_no_entry_admission(); break;
    case C_OLD_HOST_INPUT: run_old_host_input(); break;
    case C_NO_HOST_ENTRY: run_no_host_entry(); break;
    case C_RELEASE_RETRY: run_release_retry(); break;
    case C_CARD_GONE: run_card_gone(); break;
    case C_SHORTCUT_BLOCKED: run_shortcut_blocked(); break;
    case C_LATCH_RETRY: run_latch_retry(); break;
    default: run_standard(); break;
    }

    if (g_skipped && test_failures() == 0) {
        printf("== %s: skipped\n", name);
        fflush(stdout);
        return 0;
    }
    printf("== %s: %d failure(s)\n", name, test_failures());
    fflush(stdout);
    TEST_MAIN_END
}
