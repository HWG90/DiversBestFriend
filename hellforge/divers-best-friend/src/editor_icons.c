#include "editor_icons.h"
#include <math.h>
#include <stdbool.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>
#include <stdio.h>
#include <string.h>
#endif

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
/* Mods.ModLines records the asset folder and DLL separately. Read the same
 * UTF-8 plan the loader uses, including its translated paths under Proton. */
static int plan_image(const OvApi* ov, int* width, int* height)
{
    wchar_t plan[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"HELLFORGE_MODLOADER_PLAN", plan, MAX_PATH);
    if (!n || n >= MAX_PATH) return 0;
    FILE* f = _wfopen(plan, L"rb");
    if (!f) return 0;
    static const char prefix[] = "mod\thellforge.editor\t";
    char line[4096];
    int image = 0;
    while (fgets(line, sizeof line, f)) {
        if (strncmp(line, prefix, sizeof prefix - 1) == 0) {
            char* folder = line + sizeof prefix - 1;
            char* end = strchr(folder, '\t');
            if (end && end > folder && (size_t)(end-line) + sizeof "\\icon.png" <= sizeof line) {
                strcpy(end, "\\icon.png");
                image = ov->load_image(folder, width, height);
            }
            break;
        }
        /* Skip any continuation of an unrelated long record. */
        while (!strchr(line, '\n') && fgets(line, sizeof line, f)) {}
    }
    fclose(f);
    return image;
}

static bool installed_logo(const Pen* p)
{
    static int image, width, height;
    static bool checked_plan;
    static HMODULE attempted;
    const OvApi* ov = p->ov;
    if (ov->version < 3 || ov->size < offsetof(OvApi, draw_image_uv) + sizeof ov->draw_image_uv ||
        !ov->load_image || !ov->draw_image_uv) return false;
    if (!checked_plan) {
        checked_plan = true;
        image = plan_image(ov, &width, &height);
        if (image) return false; /* The host uploads images on the next frame. */
    }
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
    if (!ov || !section || !named(section, "logo") || !(size > 0) || !isfinite(size) || !isfinite(x) || !isfinite(y) ||
        ov->version < 2 || ov->size < offsetof(OvApi, theme) + sizeof ov->theme || !ov->theme) return;
    Pen p = {ov, x, y, size/24, ov->theme(OV_THEME_TEXT)};
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
}
