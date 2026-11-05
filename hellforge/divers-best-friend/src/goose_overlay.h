/* Goose Overlay Host, API version 7: a shared in-game UI for HellForge code mods.
 *
 * The host (mods/overlay-host, goose_overlay.dll) draws over the game with Dear ImGui, on the game's own Direct3D 12
 * queue (or Direct3D 11 with --use-d3d11), and owns the game window's input while one of its windows is open. Other
 * mods register panels with it and draw them with the calls below. They need no ImGui, Direct3D or hooks of their own,
 * so they stay plain C source mods that HellForge builds, and several mods never fight over the swap chain or the
 * window procedure.
 *
 *   static void Draw(const OvFrame* frame, void* user)
 *   {
 *       ov->text("Hello from my mod");
 *       if (ov->button("Heal")) ...;
 *   }
 *   static void Ready(HfMod* mod, HfEvent event, void* user)       // HF_EVENT_GAME_LOADED or later, never in init
 *   {
 *       ov = ov_connect();
 *       if (ov == NULL) return;                                    // the host is off or missing: the mod runs without UI
 *       OvPanelDef panel = {sizeof panel, "me.my-mod", "My Mod", OV_PANEL_WINDOW, VK_F6};
 *       panel.draw = Draw;
 *       ov->register_panel(&panel);
 *   }
 *
 * Panels:
 *   - OV_PANEL_WINDOW: a window, shown and hidden by its hotkey or from the host's panel list (F7 by default). While any
 *     window is open the host takes the keyboard and mouse from the game and draws a cursor.
 *   - OV_PANEL_HUD: drawn every frame, never takes input: draw_* calls in screen pixels, for HUD elements.
 * Draw callbacks run on the game's render thread, one at a time, inside the host's frame: the widget and draw calls are
 * valid only there. Keep them short, and do not call HfApi functions that need the game thread from them (queue work
 * with the SDK's on_game_thread instead). Everything else here (register_panel, set_open, load_font, log) works from any
 * thread.
 *
 * The game thread: ov->on_game_thread (or ov_on_game_thread at the end of this header) runs a mod's per-update
 * callback through the host's own HellForge slot, so mods that use it take one of HellForge's 16 between them.
 *
 * Text is UTF-8. Colours are 0xAABBGGRR (OV_RGBA). Widget labels follow ImGui's rules: "Label##id" shows "Label" and
 * keeps "id" apart from another "Label"; labels must be unique within a panel (or under push_id).
 *
 * MIT No Attribution: mods that include this header belong to their authors, under any licence they choose. */
#ifndef Goose_OVERLAY_H
#define Goose_OVERLAY_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define OV_API_VERSION 8
#define OV_HOST_DLL "goose_overlay.dll"

#define OV_RGBA(r, g, b, a) ((uint32_t)(r) | ((uint32_t)(g) << 8) | ((uint32_t)(b) << 16) | ((uint32_t)(a) << 24))

typedef struct OvPanel OvPanel; /* a registered panel: opaque */

typedef enum OvPanelKind
{
    OV_PANEL_WINDOW = 0,
    OV_PANEL_HUD = 1,
} OvPanelKind;

typedef enum OvWindowFlags
{
    OV_WINDOW_NO_RESIZE = 1 << 0,
    OV_WINDOW_AUTO_SIZE = 1 << 1,   /* fits its contents each frame */
    OV_WINDOW_NO_TITLE = 1 << 2,
    OV_WINDOW_NO_SCROLLBAR = 1 << 3,
    OV_WINDOW_NO_MOVE = 1 << 4,
    OV_WINDOW_MENU_BAR = 1 << 5,
} OvWindowFlags;

/* What the host tells each draw callback. */
typedef struct OvFrame
{
    float width, height; /* the back buffer, in pixels */
    float delta;         /* seconds since the last frame */
    double time;         /* seconds since the host started drawing */
    float scale;         /* the interface scale: height / 1080, times the host's scale setting */
    int capturing;       /* a host window is open and has the game's input */
} OvFrame;

typedef void (*OvDrawFn)(const OvFrame* frame, void* user);
/* capture_frame's completion (a worker thread): status 0 written, else a Win32 error code or -1. */
typedef void (*OvCaptureFn)(int status, const char* png_path, void* user);
/* on_game_thread's callback: the SDK's HfTickCallback (the mod's own HfMod, the update's dt in seconds). */
struct HfMod;
typedef void (*OvTickFn)(struct HfMod* mod, float dt, void* user);

typedef struct OvPanelDef
{
    uint32_t size;         /* sizeof(OvPanelDef) */
    const char* id;        /* unique, usually the mod's id ("me.my-mod" or "me.my-mod/stats"); copied */
    const char* title;     /* the window's title and its name in the panel list; copied */
    uint32_t kind;         /* OvPanelKind */
    uint32_t hotkey;       /* a virtual-key code (VK_F6) toggling the window, 0 for none; the host's config can override it */
    uint32_t window_flags; /* OvWindowFlags */
    float width, height;   /* the window's first size in 1080p pixels (scaled), 0 for automatic */
    OvDrawFn draw;
    void* user;
} OvPanelDef;

typedef struct OvApi
{
    uint32_t version; /* OV_API_VERSION of the host; functions are only ever added at the end */
    uint32_t size;    /* sizeof(OvApi) of the host */

    /* ---- panels (any thread) ---- */
    /* NULL when the definition is invalid or its id is taken (the host's log says which). */
    OvPanel* (*register_panel)(const OvPanelDef* def);
    void (*set_open)(OvPanel* panel, int open);
    int (*is_open)(OvPanel* panel);
    /* Logs to the host's log in the session folder (mod-goose.overlay-host.log), printf format. */
    void (*log)(const char* format, ...);

    /* ---- text and layout (draw callbacks only) ---- */
    void (*text)(const char* text);
    void (*textf)(const char* format, ...);
    void (*text_colored)(uint32_t color, const char* text);
    void (*text_disabled)(const char* text);
    void (*text_wrapped)(const char* text);
    void (*separator)(void);
    void (*separator_text)(const char* text);
    void (*same_line)(void);
    void (*spacing)(void);
    void (*indent)(void);
    void (*unindent)(void);
    void (*set_next_item_width)(float pixels);
    void (*push_id)(const char* id);
    void (*push_id_int)(int id);
    void (*pop_id)(void);

    /* ---- widgets (draw callbacks only): 1 when clicked or changed this frame ---- */
    int (*button)(const char* label);
    int (*small_button)(const char* label);
    int (*checkbox)(const char* label, int* value);
    int (*radio)(const char* label, int* value, int choice);
    int (*slider_float)(const char* label, float* value, float min, float max, const char* format); /* format NULL: "%.3f" */
    int (*slider_int)(const char* label, int* value, int min, int max);
    int (*drag_float)(const char* label, float* value, float speed, float min, float max);
    int (*input_int)(const char* label, int* value);
    int (*input_float)(const char* label, float* value);
    int (*input_text)(const char* label, char* buffer, size_t size);
    int (*combo)(const char* label, int* current, const char* const* items, int count);
    int (*color_edit)(const char* label, float rgba[4]);
    int (*selectable)(const char* label, int selected);
    void (*progress_bar)(float fraction, const char* overlay);
    int (*is_item_hovered)(void);
    void (*tooltip)(const char* text); /* for the last item, while it is hovered */

    /* ---- grouping (draw callbacks only); every begin_* that returns 1 needs its end_* ---- */
    int (*collapsing_header)(const char* label, int default_open);
    int (*tree_node)(const char* label);
    void (*tree_pop)(void);
    int (*begin_tab_bar)(const char* id);
    void (*end_tab_bar)(void);
    int (*begin_tab_item)(const char* label);
    void (*end_tab_item)(void);
    void (*begin_child)(const char* id, float width, float height, int border); /* always pair with end_child */
    void (*end_child)(void);
    int (*begin_table)(const char* id, int columns);
    void (*table_setup_column)(const char* label);
    void (*table_headers_row)(void);
    void (*table_next_row)(void);
    int (*table_next_column)(void);
    void (*end_table)(void);

    /* ---- drawing in screen pixels (draw callbacks only): over the game, under the host's windows ---- */
    void (*draw_line)(float x0, float y0, float x1, float y1, uint32_t color, float thickness);
    void (*draw_rect)(float x0, float y0, float x1, float y1, uint32_t color, float rounding, float thickness);
    void (*draw_rect_filled)(float x0, float y0, float x1, float y1, uint32_t color, float rounding);
    void (*draw_circle)(float x, float y, float radius, uint32_t color, float thickness);
    void (*draw_circle_filled)(float x, float y, float radius, uint32_t color);
    void (*draw_triangle_filled)(float x0, float y0, float x1, float y1, float x2, float y2, uint32_t color);
    /* size 0: the current font's size; font 0: the current font */
    void (*draw_text)(float x, float y, uint32_t color, int font, float size, const char* text);
    void (*text_size)(int font, float size, const char* text, float* width, float* height);

    /* ---- fonts ---- */
    /* A TrueType font at a size in 1080p pixels (scaled with the screen): its id, usable from the next frame, or 0 when
     * the file cannot be read. Any thread. Font 1 is the host's default (the game's font when the HellForge editor's
     * copy of it is installed); from host 0.4.0 font 2 is its bold copy, and loaded fonts are 3 and up. */
    int (*load_font)(const char* ttf_path, float size);
    void (*push_font)(int font);
    void (*pop_font)(void);

    /* ---- input (draw callbacks only) ---- */
    int (*key_down)(int vk);    /* the key is held (the host's view while capturing, the keyboard's otherwise) */
    int (*key_pressed)(int vk); /* went down this frame (repeats not counted) */
    void (*mouse_pos)(float* x, float* y);

    /* ======== API version 2: check ov->version >= 2 (or size) before using these ======== */

    /* ---- the last item (draw callbacks only) ---- */
    int (*is_item_active)(void);
    int (*is_item_clicked)(int button);        /* 0 left, 1 right, 2 middle */
    int (*is_item_deactivated_after_edit)(void); /* a slider released or a text field left after a change: commit now */
    void (*item_rect)(float* x0, float* y0, float* x1, float* y1);
    int (*invisible_button)(const char* id, float width, float height); /* a hit area for custom-drawn controls */
    void (*dummy)(float width, float height);

    /* ---- the window and the cursor (draw callbacks only), in screen pixels ---- */
    void (*cursor_screen_pos)(float* x, float* y);
    void (*set_cursor_screen_pos)(float x, float y);
    void (*content_region_avail)(float* width, float* height);
    void (*window_rect)(float* x0, float* y0, float* x1, float* y1);
    /* Where draw_* calls go: OV_LAYER_BACKGROUND (under every window: HUDs), OV_LAYER_WINDOW (the current window or
     * child, clipped to it, over its widgets drawn so far), OV_LAYER_FOREGROUND (over everything). */
    void (*draw_layer)(int layer);
    void (*push_clip_rect)(float x0, float y0, float x1, float y1);
    void (*pop_clip_rect)(void);

    /* ---- popups (draw callbacks only); each begin_* that returns 1 needs end_popup ---- */
    void (*open_popup)(const char* id);
    int (*begin_popup)(const char* id);
    int (*begin_popup_context_item)(const char* id); /* right-click on the last item */
    int (*begin_popup_modal)(const char* title, int* open);
    void (*end_popup)(void);
    void (*close_current_popup)(void);
    int (*menu_item)(const char* label, const char* shortcut, int enabled);

    /* ---- style and state (draw callbacks only) ---- */
    void (*push_color)(int slot, uint32_t color); /* OvColorSlot */
    void (*pop_color)(int count);
    void (*begin_disabled)(int disabled);         /* greys out and blocks the widgets until end_disabled */
    void (*end_disabled)(void);
    void (*set_keyboard_focus_here)(void);
    int (*selectable_ex)(const char* label, int selected, float width, float height, int span_columns);
    void (*table_setup_column_ex)(const char* label, int stretch, float width_or_weight);
    int (*color_picker)(const char* label, float rgb[3]);
    int (*input_text_ex)(const char* label, char* buffer, size_t size, int flags); /* OvInputFlags */
    void (*set_clipboard)(const char* text);
    float (*mouse_wheel)(void);   /* notches this frame (+ up) */
    uint32_t (*theme)(int color); /* OvThemeColor: the house palette, so mods match the host */
    float (*frame_height)(void);  /* a standard widget's height */
    float (*text_line_height)(void);
    const char* (*host_folder)(void); /* the host's mod folder (UTF-8), for fonts beside it */

    /* ======== API version 3: check ov->version >= 3 (or size) before using these ======== */

    /* ---- input without a window (any thread unless said) ---- */
    /* Free-look capture for a panel: the host takes the keyboard and mouse from the game as it does for an open
     * window, but hides the cursor, keeps it inside the game window and reports raw mouse motion through mouse_delta.
     * Windows stay drawn and get no mouse while it is on. 0 gives the input back (unless a window is open). */
    void (*set_look_capture)(OvPanel* panel, int on);
    int (*look_capture)(void); /* 1 while any panel holds it */
    /* Raw mouse motion (counts, as the mouse reports them) and wheel notches since the last call: draw callbacks only;
     * gathered only while look capture is on. */
    void (*mouse_delta)(float* dx, float* dy, float* wheel);
    /* The mouse buttons as the host sees them while it captures (draw callbacks only): 0 left, 1 right, 2 middle. */
    int (*mouse_down)(int button);
    int (*mouse_clicked)(int button);
    int (*mouse_double_clicked)(int button);
    int (*want_text_input)(void); /* a text field has the keyboard: a mod's own hotkeys should wait (draw callbacks only) */
    int (*want_mouse)(void);      /* the mouse is over a window or dragging a widget (draw callbacks only) */
    int (*is_focused)(void);      /* the game window is in the foreground */
    /* A window's background opacity (0 .. 1; below 0 the theme's own), applied from its next frame. Any thread. */
    void (*set_panel_alpha)(OvPanel* panel, float alpha);

    /* ---- images: load from any thread, draw in draw callbacks ---- */
    /* A PNG, JPEG, BMP or GIF file (UTF-8 path): its id (1 and up) with its size, or 0 when it cannot be read (the
     * host's log says why); drawable from the next frame. */
    int (*load_image)(const char* path, int* width, int* height);
    void (*draw_image)(int image, float x0, float y0, float x1, float y1, uint32_t tint); /* on the current draw layer */
    void (*draw_image_uv)(int image, float x0, float y0, float x1, float y1, float u0, float v0, float u1, float v1, uint32_t tint);

    /* ---- frame capture (any thread) ---- */
    /* Writes the next frame as a PNG: the game's back buffer with the HUD panels drawn over it, every window and the
     * panel list hidden for that one frame (OV_CAPTURE_NO_OVERLAY: the game alone, nothing of the host's). An HDR10
     * back buffer is tone mapped to SDR (BT.2020 PQ, 203 nits white). The callback runs on a worker thread once the
     * file is written or the capture failed. Returns 0 queued, 1 refused (a capture is already pending, the path is
     * empty or drawing is off). */
    int (*capture_frame)(const char* png_path, uint32_t flags, OvCaptureFn callback, void* user);
    int (*capture_pending)(void);

    /* ======== API version 4: check ov->version >= 4 (or size) before using these ======== */

    /* Mouse wheel notches (+ up) the game window received since the last call while no host window was open and look
     * capture was off. The game still gets them. Any thread; reading resets the count, so two clients reading it take
     * notches from each other: with more than one reader, use passive_wheel_total (version 7). */
    float (*passive_wheel)(void);

    /* ======== API version 5: check ov->version >= 5 (or size) before using these ======== */

    /* ---- the game thread (any thread) ---- */
    /* Calls back every game update on the game thread, as HfApi.on_game_thread does (before the game's update; keep it
     * short), but from the host's own HellForge slot: every mod that uses this shares that one of HellForge's 16. The
     * callbacks run one after another, in the order they were added; one added from inside a callback starts at the
     * next update. Like HellForge's, a callback cannot be removed. Returns 1, or 0 when HellForge gave the host no slot
     * or the host's 32 are taken (the host's log says which): then use hf->on_game_thread. ov_on_game_thread, at the
     * end of this header, does both. */
    int (*on_game_thread)(struct HfMod* mod, OvTickFn callback, void* user);

    /* ======== API version 6 (host 0.4.0): check ov->version >= 6 (or size) before using these ======== */

    /* ---- the house look (HD2-UI-Style/DESIGN.md; draw callbacks only) ----
     * The host already draws titles, headings, tabs, buttons, checkboxes, sliders and selected rows this way; these
     * are the parts a mod asks for by name. */
    int (*button_primary)(const char* label); /* the window's one main button: solid yellow, bold capitals */
    void (*key_cap)(const char* key);         /* a key hint in a small plate, like the game's "Z DISPATCHES" */
    void (*heading)(const char* text);        /* a section heading: bold yellow capitals with a rule under them */
    int (*bold_font)(void);                   /* the bold font's id, for push_font */

    /* ======== API version 7 (host 0.5.0): check ov->version >= 7 (or size) before using these ======== */

    /* The mouse wheel the game window received while no host window was open and look capture was off, summed since
     * the host started, in WHEEL_DELTA units (120 per notch, + up). Never reset: each client keeps its own last value
     * and takes the difference, so clients never take notches from each other. Any thread. */
    int64_t (*passive_wheel_total)(void);
    /* API 8 (host 0.6.0): a window or look capture owns game input. Any thread, even with every HUD hidden. */
    int (*input_captured)(void);
} OvApi;

enum OvLayer { OV_LAYER_BACKGROUND = 0, OV_LAYER_WINDOW = 1, OV_LAYER_FOREGROUND = 2 };

/* push_color slots: ImGui's own colours, the ones a control usually changes. */
enum OvColorSlot
{
    OV_COL_TEXT = 0, OV_COL_TEXT_DISABLED, OV_COL_WINDOW_BG, OV_COL_CHILD_BG, OV_COL_POPUP_BG, OV_COL_BORDER,
    OV_COL_FRAME_BG, OV_COL_FRAME_BG_HOVERED, OV_COL_FRAME_BG_ACTIVE, OV_COL_BUTTON, OV_COL_BUTTON_HOVERED,
    OV_COL_BUTTON_ACTIVE, OV_COL_HEADER, OV_COL_HEADER_HOVERED, OV_COL_HEADER_ACTIVE, OV_COL_SLIDER_GRAB,
    OV_COL_SLIDER_GRAB_ACTIVE, OV_COL_CHECK_MARK, OV_COL_SEPARATOR, OV_COL_TABLE_ROW_BG, OV_COL_TABLE_ROW_BG_ALT,
};

/* The house palette (theme()): the HellForge editor's dark panels and yellow, with Goose's gold. */
enum OvThemeColor
{
    OV_THEME_PANEL = 0,   /* window background */
    OV_THEME_PANEL_ALT,   /* sidebars, headers */
    OV_THEME_ROW,         /* list rows */
    OV_THEME_ROW_HOVER,
    OV_THEME_LINE,        /* borders and rules */
    OV_THEME_TEXT,
    OV_THEME_TEXT_DIM,
    OV_THEME_ACCENT,      /* Helldivers yellow #FFE800 */
    OV_THEME_ACCENT_DIM,  /* selection backgrounds */
    OV_THEME_GOLD,        /* Goose gold #F4CA35 */
    OV_THEME_DANGER,
    OV_THEME_SUCCESS,
    /* host 0.4.0 (older hosts return 0xFFFFFFFF for these) */
    OV_THEME_ON_ACCENT,     /* text and icons on solid yellow */
    OV_THEME_SELECT_HOVER,  /* a selected row under the pointer */
    OV_THEME_FIELD_ACTIVE,  /* a field or secondary button held */
    OV_THEME_LINE_STRONG,   /* hovered borders */
    OV_THEME_TEXT_OFF,      /* disabled text */
    OV_THEME_ACCENT_HOVER,  /* the main button under the pointer */
    OV_THEME_ACCENT_PRESS,  /* the main button held */
    /* HUD roles: older hosts return 0xFFFFFFFF for these. */
    OV_THEME_HUD_PLATE,     /* translucent background behind HUD text */
    OV_THEME_HUD_SHADOW,    /* shadow under HUD text */
};

enum OvInputFlags { OV_INPUT_ENTER_RETURNS = 1, OV_INPUT_AUTO_SELECT = 2, OV_INPUT_HEX = 4, OV_INPUT_NO_SPACES = 8 };
/* capture_frame's flags. The host's windows never show in a capture (it is a screenshot of the game), unless
 * OV_CAPTURE_WITH_WINDOWS (host 0.4.0; older hosts ignore it and hide them). */
enum OvCaptureFlags { OV_CAPTURE_NO_OVERLAY = 1, OV_CAPTURE_WITH_WINDOWS = 2 };

/* The host's export: its API for this version, or NULL when it is older than `version`. */
typedef const OvApi* (*OvApiFn)(uint32_t version);

#ifdef Goose_OVERLAY_HOST
__declspec(dllexport) const OvApi* ov_api(uint32_t version);
#endif

#ifdef __cplusplus
}
#endif

#if !defined(Goose_OVERLAY_HOST) && defined(_WIN32)
#include <windows.h>
/* The host's API, or NULL when it is not loaded (switched off, or missing) or older than this header: a mod built with
 * this header (API 7) gets NULL from hosts before 0.5.0. A mod that uses no API 7 call can keep an older header and run
 * on older hosts too. Call it from an HfApi event (HF_EVENT_GAME_LOADED or later), when every mod's DLL is loaded, not
 * from hellforge_mod_init. */
static inline const OvApi* ov_connect(void)
{
    HMODULE host = GetModuleHandleA(OV_HOST_DLL);
    OvApiFn get = host != NULL ? (OvApiFn)(void*)GetProcAddress(host, "ov_api") : NULL;
    return get != NULL ? get(OV_API_VERSION) : NULL;
}

#ifdef HF_MOD_SDK_VERSION
/* hf->on_game_thread, through the host's slot while the host is loaded (and new enough), else the mod's own. Call it
 * where ov_connect may be called: an HfApi event, HF_EVENT_GAME_LOADED or later. That costs nothing against calling
 * hf->on_game_thread from hellforge_mod_init: either way the callback starts once HellForge has hooked the game's
 * update, up to a minute after HF_EVENT_GAME_LOADED. Returns 1 registered, 0 refused by the host and by HellForge. */
static inline int ov_on_game_thread(const HfApi* hf, HfMod* mod, HfTickCallback callback, void* user)
{
    const OvApi* ov = ov_connect();
    if (ov != NULL && ov->size >= offsetof(OvApi, on_game_thread) + sizeof ov->on_game_thread && ov->on_game_thread(mod, callback, user))
        return 1;
    if (hf->size < offsetof(HfApi, on_game_thread) + sizeof hf->on_game_thread || hf->on_game_thread == NULL) return 0;
    return hf->on_game_thread(mod, callback, user);
}
#endif
#endif

#endif
