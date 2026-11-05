#include "editor_icons.h"
#include <math.h>
#include <stdbool.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>
#endif

/* The Editor 0.4.2 header uses the Editor emblem; its own tabs are text-only.
 * DBF's tab marks are small line drawings, in the same square coordinate space. */
typedef struct { unsigned char x1, y1, x2, y2; } Stroke;
typedef struct {
    const OvApi* ov;
    float x, y, unit;
    uint32_t ink;
} Pen;

static bool named(const char* a, const char* lower)
{
    while (*a && *lower) {
        char c = *a++;
        if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
        if (c != *lower++) return false;
    }
    return *a == *lower;
}

static void lines(const Pen* p, const Stroke* strokes, size_t count)
{
    for (size_t i = 0; i < count; ++i) {
        const Stroke* s = &strokes[i];
        p->ov->draw_line(p->x + s->x1 * p->unit, p->y + s->y1 * p->unit,
                         p->x + s->x2 * p->unit, p->y + s->y2 * p->unit, p->ink, 1.6f * p->unit);
    }
}

static void block(const Pen* p, float x, float y, float w, float h)
{
    p->ov->draw_rect_filled(p->x + x*p->unit, p->y + y*p->unit,
                            p->x + (x+w)*p->unit, p->y + (y+h)*p->unit, p->ink, 0);
}

static void sliders(const Pen* p)
{
    static const int knobs[] = {13, 8, 12};
    for (int i = 0; i < 3; ++i) {
        float y = 7.2f + 4.8f*i;
        block(p, 6, y-0.75f, 12, 1.5f);
        block(p, knobs[i]-1.5f, y-1.7f, 3, 3.4f);
    }
}

#ifdef _WIN32
/* Resolve the player's own PNG beside the loaded Editor. The installed 512px
 * icon is editor-logo.png; its emblem occupies [87,425) in both axes. */
static bool installed_logo(const Pen* p)
{
    static int image, width, height;
    static HMODULE attempted;
    const OvApi* ov = p->ov;
    if (ov->version < 3 || ov->size < offsetof(OvApi, draw_image_uv) + sizeof ov->draw_image_uv ||
        !ov->load_image || !ov->draw_image_uv) return false;
    if (!image) {
        HMODULE mod = GetModuleHandleW(L"hellforge_editor.dll");
        if (!mod || mod == attempted) return false;
        attempted = mod;
        wchar_t path[1024];
        DWORD n = GetModuleFileNameW(mod, path, 1024);
        if (!n || n >= 1024) return false;
        wchar_t* file = wcsrchr(path, L'\\');
        if (!file || (size_t)(file-path) + 10 > 1024) return false;
        wcscpy(file+1, L"icon.png");
        char utf8[4096];
        if (!WideCharToMultiByte(CP_UTF8, 0, path, -1, utf8, sizeof utf8, NULL, NULL)) return false;
        image = ov->load_image(utf8, &width, &height);
        return false; /* Upload occurs on the next frame. */
    }
    float lo = 0, hi = 1;
    if (width == 512 && height == 512) { lo = 87.0f/512; hi = 425.0f/512; }
    ov->draw_image_uv(image, p->x, p->y, p->x + 24*p->unit, p->y + 24*p->unit, lo, lo, hi, hi, p->ink);
    return true;
}
#endif

void editor_icon(const OvApi* ov, const char* section, float x, float y, float size)
{
    if (!ov || !section || !(size > 0) || !isfinite(size) || !isfinite(x) || !isfinite(y) ||
        ov->version < 2 || ov->size < offsetof(OvApi, theme) + sizeof ov->theme || !ov->theme) return;
    Pen p = {ov, x, y, size/24, ov->theme(OV_THEME_TEXT)};
    if (named(section, "logo")) {
#ifdef _WIN32
        if (installed_logo(&p)) return;
#endif
        if (!ov->draw_rect_filled) return;
        /* Editor's built-in fallback: four corner brackets around three faders. */
        p.ink = ov->theme(OV_THEME_ACCENT);
        for (int i = 0; i < 4; ++i) {
            bool right = i & 1, bottom = i & 2;
            block(&p, right ? 15.36f : 0, bottom ? 20.88f : 0, 8.64f, 3.12f);
            block(&p, right ? 20.88f : 0, bottom ? 15.36f : 0, 3.12f, 8.64f);
        }
        sliders(&p);
    } else if (named(section, "controls")) {
        if (ov->draw_rect_filled) sliders(&p);
    } else if (ov->draw_line) {
        static const Stroke browse[] = {{5,6,7,6},{10,6,20,6},{5,12,7,12},{10,12,20,12},{5,18,7,18},{10,18,20,18}};
        static const Stroke pencil[] = {{4,20,6,13},{6,13,16,3},{16,3,21,8},{21,8,11,18},{11,18,4,20},{14,5,19,10}};
        static const Stroke slash[] = {{6,18,18,6}};
        static const Stroke pulse[] = {{2,13,7,13},{7,13,10,6},{10,6,14,18},{14,18,17,11},{17,11,22,11}};
        if (named(section, "browse")) lines(&p, browse, sizeof browse / sizeof *browse);
        else if (named(section, "changes")) lines(&p, pencil, sizeof pencil / sizeof *pencil);
        else if (named(section, "blacklist") && ov->draw_circle) {
            ov->draw_circle(x + size/2, y + size/2, 8.5f*p.unit, p.ink, 1.6f*p.unit);
            lines(&p, slash, 1);
        } else if (named(section, "status")) lines(&p, pulse, sizeof pulse / sizeof *pulse);
    }
}
