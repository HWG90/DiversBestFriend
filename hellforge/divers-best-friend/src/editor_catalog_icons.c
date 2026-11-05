#include "editor_catalog_icons.h"
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* icons.cpp ReadIcon: packed, little-endian HFIC v2. Keep only category and
 * white layers. One decoded texture per overlay lifetime, never one per row. */
enum { WIDTH = 2048, MAX_HEIGHT = 4096, MAX_BYTES = 64*1024*1024, MAX_LAYERS = 512 };
typedef struct {
    char name[256];
    unsigned kind, x, y, w, h, channels;
    size_t offset;
} Layer;
static Layer layers[MAX_LAYERS];
static unsigned layer_count, height;
static int image;

static unsigned le16(const unsigned char* p) { return p[0] | ((unsigned)p[1]<<8); }
static uint32_t le32(const unsigned char* p) { return le16(p) | ((uint32_t)le16(p+2)<<16); }

static bool layout(const unsigned char* data, size_t size)
{
    if (size < 12 || memcmp(data, "HFIC", 4) || le32(data+4) != 2) return false;
    uint32_t count = le32(data+8);
    if (count > 16384) return false;
    size_t at = 12;
    unsigned x = 1, y = 1, shelf = 0;
    layer_count = 0;
    for (uint32_t i = 0; i < count; ++i) {
        if (size-at < 7) return false;
        unsigned kind = data[at++], n = data[at++];
        if (size-at < n+5 || !(kind <= 5 || kind == 7 || kind == 8)) return false;
        const unsigned char* name = data+at;
        at += n;
        unsigned w = le16(data+at), h = le16(data+at+2), channels = data[at+4];
        at += 5;
        if (!w || !h || w > 1024 || h > 1024 || (channels != 1 && channels != 4)) return false;
        size_t bytes = (size_t)w*h*channels;
        if (bytes > size-at) return false;
        if (kind == 2 || kind == 3) {
            if (!n || memchr(name, 0, n) || layer_count == MAX_LAYERS) return false;
            if (x+w+1 > WIDTH) { x = 1; y += shelf+2; shelf = 0; }
            if (y+h+1 > MAX_HEIGHT) return false;
            Layer* layer = &layers[layer_count++];
            memcpy(layer->name, name, n);
            layer->name[n] = 0;
            layer->kind = kind; layer->x = x; layer->y = y; layer->w = w; layer->h = h;
            layer->offset = at; layer->channels = channels;
            x += w+2;
            if (h > shelf) shelf = h;
        }
        at += bytes;
    }
    height = y+shelf+1;
    return at == size && layer_count > 0;
}

/* Resolve fixed filenames relative to the Editor DLL or DBF's sibling mod.
 * A catalog label never participates in a filesystem path. */
static HANDLE from_folder(wchar_t* folder, bool sibling)
{
    /* Loader paths are absolute Windows drive paths, including Wine's Z:.
     * Do not resolve relative paths, device names or alternate data streams. */
    if (!((folder[0]>=L'A' && folder[0]<=L'Z') || (folder[0]>=L'a' && folder[0]<=L'z')) ||
        folder[1]!=L':' || folder[2]!=L'\\' || wcschr(folder+2,L':')) return INVALID_HANDLE_VALUE;
    if (sibling) {
        wchar_t* slash = wcsrchr(folder,L'\\');
        if (!slash) return INVALID_HANDLE_VALUE;
        *slash = 0;
    }
    const wchar_t* suffix = sibling ? L"\\hellforge-editor\\game-icons.bin" : L"\\game-icons.bin";
    if (wcslen(folder)+wcslen(suffix)>=2048) return INVALID_HANDLE_VALUE;
    wcscat(folder,suffix);
    return CreateFileW(folder,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,0,NULL);
}

static HANDLE from_module(HMODULE mod, bool sibling)
{
    wchar_t path[2048];
    DWORD n = GetModuleFileNameW(mod,path,2048);
    if (!n || n>=2048) return INVALID_HANDLE_VALUE;
    wchar_t* slash = wcsrchr(path,L'\\');
    if (!slash) return INVALID_HANDLE_VALUE;
    *slash = 0;
    return from_folder(path,sibling);
}

/* The launcher can stage a DLL separately from its assets. The plan's third
 * column is the installed mod folder for both native Windows and Proton. */
static HANDLE from_plan(void)
{
    wchar_t path[2048], sibling[2048] = {0};
    DWORD n = GetEnvironmentVariableW(L"HELLFORGE_MODLOADER_PLAN",path,2048);
    if (!n || n>=2048) return INVALID_HANDLE_VALUE;
    FILE* plan = _wfopen(path,L"rb");
    if (!plan) return INVALID_HANDLE_VALUE;
    HANDLE file = INVALID_HANDLE_VALUE;
    long bytes;
    if (!fseek(plan,0,SEEK_END) && (bytes=ftell(plan))>=0 && bytes<=4*1024*1024 &&
        !fseek(plan,0,SEEK_SET)) {
        char line[8192];
        while (fgets(line,sizeof line,plan)) {
            if (!strchr(line,'\n') && !feof(plan)) {
                while (fgets(line,sizeof line,plan) && !strchr(line,'\n')) {}
                continue;
            }
            if (strncmp(line,"mod\t",4)) continue;
            char* folder = strchr(line+4,'\t');
            if (!folder) continue;
            *folder++ = 0;
            bool own = !strcmp(line+4,"goose.divers-best-friend");
            if (!own && strcmp(line+4,"hellforge.editor")) continue;
            char* end = strchr(folder,'\t');
            if (!end) continue;
            *end = 0;
            if (!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,folder,-1,path,2048)) continue;
            for (wchar_t* p=path; *p; ++p) if (*p==L'/') *p=L'\\';
            if (own) wcscpy(sibling,path);
            else if ((file=from_folder(path,false))!=INVALID_HANDLE_VALUE) break;
        }
    }
    fclose(plan);
    if (file==INVALID_HANDLE_VALUE && *sibling) file=from_folder(sibling,true);
    return file;
}

static unsigned char* read_catalog(size_t* size)
{
    HANDLE file = from_plan();
    HMODULE mod = GetModuleHandleW(L"hellforge_editor.dll");
    if (file == INVALID_HANDLE_VALUE && mod) file = from_module(mod,false);
    if (file == INVALID_HANDLE_VALUE && GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCWSTR)&read_catalog, &mod))
        file = from_module(mod,true);
    if (file == INVALID_HANDLE_VALUE) return NULL;
    LARGE_INTEGER len;
    unsigned char* data = NULL;
    DWORD got;
    if (GetFileSizeEx(file,&len) && len.QuadPart >= 12 && len.QuadPart <= MAX_BYTES) {
        data = malloc(len.LowPart);
        if (data && (!ReadFile(file,data,len.LowPart,&got,NULL) || got != len.LowPart)) { free(data); data = NULL; }
        *size = len.LowPart;
    }
    CloseHandle(file);
    return data;
}

/* Top-down BITMAPV5HEADER with explicit BGRA masks. The overlay's synchronous
 * WIC decode consumes the file before load_image returns. Only the host texture
 * and atlas coordinates survive; the temporary transport is removed. */
static int upload(const OvApi* ov, const unsigned char* pixels)
{
    wchar_t path[MAX_PATH];
    DWORD n = GetTempPathW(MAX_PATH,path);
    if (!n || n+48 >= MAX_PATH) return 0;
    if (swprintf(path+n, MAX_PATH-n, L"dbf-atlas-%lu-%llu.bmp", (unsigned long)GetCurrentProcessId(),
                 (unsigned long long)GetTickCount64()) < 0) return 0;
    char utf8[MAX_PATH*4];
    if (!WideCharToMultiByte(CP_UTF8,0,path,-1,utf8,sizeof utf8,NULL,NULL)) return 0;
    HANDLE f = CreateFileW(path,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_TEMPORARY,NULL);
    if (f == INVALID_HANDLE_VALUE) return 0;
    BITMAPV5HEADER info = {0};
    info.bV5Size = sizeof info; info.bV5Width = WIDTH; info.bV5Height = -(LONG)height;
    info.bV5Planes = 1; info.bV5BitCount = 32; info.bV5Compression = BI_BITFIELDS;
    info.bV5RedMask = 0xff0000; info.bV5GreenMask = 0xff00; info.bV5BlueMask = 0xff;
    info.bV5AlphaMask = 0xff000000; info.bV5CSType = 0x73524742; /* sRGB tag */
    DWORD bytes = WIDTH*height*4, wrote;
    BITMAPFILEHEADER header = {0};
    header.bfType = 0x4d42; header.bfOffBits = sizeof header + sizeof info; header.bfSize = header.bfOffBits+bytes;
    bool ok = WriteFile(f,&header,sizeof header,&wrote,NULL) && wrote == sizeof header &&
              WriteFile(f,&info,sizeof info,&wrote,NULL) && wrote == sizeof info &&
              WriteFile(f,pixels,bytes,&wrote,NULL) && wrote == bytes;
    CloseHandle(f);
    int w = 0, h = 0;
    int id = ok ? ov->load_image(utf8,&w,&h) : 0;
    DeleteFileW(path);
    return w == WIDTH && h == (int)height ? id : 0;
}

static int load(const OvApi* ov)
{
    size_t size = 0;
    unsigned char* data = read_catalog(&size);
    unsigned char* pixels = data && layout(data,size) ? calloc((size_t)WIDTH*height,4) : NULL;
    int id = 0;
    if (pixels) {
        for (unsigned i=0; i<layer_count; ++i) {
            const Layer* l = &layers[i];
            const unsigned char* src = data+l->offset;
            for (unsigned y=0; y<l->h; ++y) {
                unsigned char* dst = pixels+4*((size_t)(l->y+y)*WIDTH+l->x);
                for (unsigned x=0; x<l->w; ++x, src+=l->channels, dst+=4) {
                    if (l->channels == 1) { memset(dst,255,3); dst[3]=src[0]; }
                    else { dst[0]=src[2]; dst[1]=src[1]; dst[2]=src[0]; dst[3]=src[3]; }
                }
            }
        }
        id = upload(ov,pixels);
    }
    free(pixels);
    free(data);
    return id;
}
#endif

bool editor_stratagem_icon(const OvApi* ov, const char* name, float x, float y, float size)
{
#ifdef _WIN32
    if (!ov || !name || !*name || !(size>0) || !isfinite(size) || !isfinite(x) || !isfinite(y) ||
        ov->version<3 || ov->size<offsetof(OvApi,draw_image_uv)+sizeof ov->draw_image_uv ||
        !ov->theme || !ov->load_image || !ov->draw_image_uv) return false;
    if (!image) {
        static ULONGLONG retry;
        ULONGLONG now = GetTickCount64();
        if (now < retry) return false;
        retry = now+30000;
        image = load(ov);
        return false; /* The host uploads on the next frame. */
    }
    const Layer* pair[2] = {NULL,NULL};
    for (unsigned i=0; i<layer_count; ++i)
        if (!_stricmp(name,layers[i].name)) pair[layers[i].kind-2] = &layers[i];
    if (!pair[0] || !pair[1]) return false;
    for (int i=0; i<2; ++i) {
        const Layer* l = pair[i];
        float scale = size/(float)(l->w > l->h ? l->w : l->h);
        float w = l->w*scale, h = l->h*scale;
        float left = x+(size-w)*0.5f, top = y+(size-h)*0.5f;
        ov->draw_image_uv(image,left,top,left+w,top+h,(float)l->x/WIDTH,(float)l->y/height,
            (float)(l->x+l->w)/WIDTH,(float)(l->y+l->h)/height,ov->theme(i ? OV_THEME_TEXT : OV_THEME_GOLD));
    }
    return true;
#else
    (void)ov; (void)name; (void)x; (void)y; (void)size;
    return false;
#endif
}
