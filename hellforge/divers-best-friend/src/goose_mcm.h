/* Public API of DBF-MCM for HellForge (goose.mcm): the Mod Configuration Menu for HellForge's C mods.
 *
 * Copy this header into your mod. It is self-contained: mcm_connect() finds the loaded goose_mcm.dll and returns its
 * McmApi table, or NULL when the menu is not loaded or is older than this header.
 *
 * Call every McmApi function from the game thread (your mod's ov_on_game_thread update, where you connect too). From
 * any other thread every call returns 0 (NULL) and changes nothing, error() says "called off the game thread", and MCM
 * logs it once per McmMod*. mcm_connect() returns NULL until MCM's first update: try again on the next one.
 *
 * Live mods: mods declared "live": true in hellforge-mod.json (HellForge 0.4, SDK 16) are not supported by this
 * version of MCM: their settings registration cannot be taken out while the game runs (hellforge_mod_unload runs on
 * the loader's thread, where unregister is refused), so MCM would go on calling a DLL that is gone. Register only from
 * a mod that stays loaded for the session.
 *
 * What MCM keeps: the strings it is given (the JSON definition, ids, values, labels) and the McmCallbacks struct are
 * copied, so none of them has to outlive the call. The callbacks' code, and whatever their user pointer points to,
 * must stay loaded and valid for the whole session.
 *
 * Callbacks run inside MCM's calls, on the game thread. A callback that crashes cannot be caught (this build has no
 * structured exception handling): it takes the game down with it. A callback may call MCM again; inside more than 32
 * nested callbacks every call that changes anything fails with "callbacks nest too deep" (logged).
 *
 * Saving: set, reset, set_many and confirm (also the menu's Apply, and edit of a control that saves at once) write and
 * flush the mod's settings file synchronously, on the calling game thread: do not call them every update. A settings
 * file MCM could not read when the mod registered (a read error, not a missing file) is never saved over: the mod gets
 * its defaults, and every save fails with "<id>.ini could not be read when <id> registered; not overwriting it".
 *
 * A mod id ([A-Za-z0-9_-], 1-80 bytes) is also its settings file's name, <id>.ini, so it cannot be a Windows device
 * name (con, prn, aux, nul, com1-com9, lpt1-lpt9, in any case), nor a registered mod's id in another case. The shared palette's id mcm_custom_palette is reserved too.
 *
 * Versions: this is version 1 of the API (MCM_API_VERSION). Set each size field (McmCallbacks.size, McmModInfo.size,
 * McmStatus.size) to sizeof the struct in this header. MCM accepts any size from version 1's sizeof upward: members
 * past the size a caller gives count as NULL or unset, and members MCM does not know (a newer header's) are ignored, so
 * a mod keeps working across versions. Members added to McmApi after version 1 need a check of api->version or
 * api->size before they are used.
 *
 * SPDX-License-Identifier: MIT-0
 * MIT No Attribution: mods that include this header belong to their authors, under any licence they choose.
 */
#ifndef GOOSE_MCM_H
#define GOOSE_MCM_H

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#endif

#define MCM_API_VERSION 1
typedef struct McmMod McmMod; /* a registration: opaque */
typedef enum McmType { MCM_NONE = 0, MCM_BOOL = 1, MCM_NUMBER = 2, MCM_TEXT = 3 } McmType;
/* choice: 1-based index; keybind: VK 0-255, 0 unbound, 256 wheel up, 257 wheel down; color: "#RRGGBB" text.
 * text points into MCM and stays valid until the caller's next call into MCM: copy it to keep it. */
typedef struct McmValue { uint32_t type; int boolean; double number; const char* text; } McmValue;

typedef struct McmCallbacks
{
    uint32_t size; /* sizeof(McmCallbacks) */
    void* user;
    int (*validate)(void* user, const char* id, const McmValue* value);            /* 0 rejects; NULL accepts */
    void (*changed)(void* user, const char* id, const McmValue* value, const McmValue* previous); /* after the save */
    const char* (*activate)(void* user, const char* id); /* a button: NULL done, or a message the footer shows */
    /* 1 true, 0 false, anything else a failed condition (logged; disabled_if counts as true, the others as false).
     * id: the control's, NULL for a text block or section that has none. Read values with preview, which sees
     * drafts; during register_mod the McmMod* comes from find(mod_id). */
    int (*condition)(void* user, const char* handler, const char* id);
    /* Optional storage provider: the mod keeps its own persistence ("storage": true in the JSON). Values travel as the
     * INI text of section 8. load: the text's length written into buffer, 0 none, -1 failed; save: 1 saved, 0 failed. */
    int (*load)(void* user, char* buffer, size_t size);
    int (*save)(void* user, const char* text, size_t length);
    /* Render thread: a page with "preview": true draws into this rectangle with Overlay Host calls. Must not change
     * settings or call MCM. */
    void (*draw_preview)(void* user, const char* page, float x0, float y0, float x1, float y1);
} McmCallbacks;

typedef struct McmModInfo { uint32_t size; const char* id; const char* name; McmMod* mod; } McmModInfo;
typedef struct McmStatus { uint32_t size; int open; uint32_t menu_key; int editing; } McmStatus; /* editing: a text
                                                                       field, key capture or the colour picker */
typedef struct McmApi
{
    uint32_t version, size;
    /* Every call: 1 (or a pointer) on success, 0 (NULL) on failure, error() says why. Two exceptions: refresh_conditions
     * and set_disabled return the change flag, 1 when something changed and 0 when nothing did. That 0 is not an
     * error: it sets error() to "", so after a 0, !*error() means "unchanged" and a non-empty error() a failure. */
    McmMod* (*register_mod)(const char* json, size_t length, const McmCallbacks* callbacks);
    int (*unregister)(McmMod* mod);
    const char* (*error)(void);
    int (*get)(McmMod* mod, const char* id, McmValue* out);      /* saved */
    int (*preview)(McmMod* mod, const char* id, McmValue* out);  /* draft, else saved */
    int (*set)(McmMod* mod, const char* id, const McmValue* value);
    int (*reset)(McmMod* mod, const char* id);
    int (*set_many)(McmMod* mod, const char* json, size_t length); /* {"id": value, ...}: all or nothing */
    int (*edit)(McmMod* mod, const char* id, const McmValue* value); /* stages on confirmation pages */
    int (*queue)(McmMod* mod, const char* button_id);
    int (*activate)(McmMod* mod, const char* button_id);
    int (*confirm)(McmMod* mod, const char* page_id);
    int (*discard)(McmMod* mod, const char* page_id);
    int (*reset_page)(McmMod* mod, const char* page_id);
    int (*available)(McmMod* mod, const char* id);
    int (*set_disabled)(McmMod* mod, const char* id, int disabled);
    int (*refresh_conditions)(McmMod* mod);
    int (*set_label)(McmMod* mod, const char* id, const char* label); /* display only; NULL restores the authored one */
    int (*open)(void);
    int (*close)(void);
    int (*is_open)(void);
    int (*focus_page)(const char* mod_id, const char* page_id);
    int (*list)(uint32_t index, McmModInfo* out); /* 0-based (swatches is 1-based); by name, then id; 0 past the last */
    McmMod* (*find)(const char* mod_id);
    int (*status)(McmStatus* out);
    int (*swatches)(uint32_t index, char out[8]);                /* 1-based, "#RRGGBB" */
    int (*save_swatch)(const char* hex);
    int (*replace_swatch)(uint32_t index, const char* hex);
} McmApi;

/* The loaded menu's API table, or NULL when goose_mcm.dll is not loaded, has not had its first update yet, is older than
 * this header, or this is not a Windows build. */
static inline const McmApi* mcm_connect(void)
{
#ifdef _WIN32
    HMODULE module = GetModuleHandleA("goose_mcm.dll");
    if (!module) return NULL;
    typedef const McmApi* (*McmApiFn)(void);
    McmApiFn entry = (McmApiFn)(void*)GetProcAddress(module, "mcm_api");
    if (!entry) return NULL;
    const McmApi* api = entry();
    if (!api || api->version < 1) return NULL;
    if (api->size < offsetof(McmApi, replace_swatch) + sizeof api->replace_swatch) return NULL;
    return api;
#else
    return NULL;
#endif
}

/* "#RRGGBB" (either case) to three bytes. 1 on success, 0 for any other text; rgb is untouched on failure. */
static inline int mcm_parse_hex(const char* text, uint8_t rgb[3])
{
    uint8_t parsed[3];
    if (!text || text[0] != '#') return 0;
    for (int i = 0; i < 6; i++)
    {
        char c = text[1 + i];
        int d = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (d < 0) return 0;
        if (i % 2 == 0) parsed[i / 2] = (uint8_t)(d << 4);
        else parsed[i / 2] = (uint8_t)(parsed[i / 2] | d);
    }
    if (text[7]) return 0;
    rgb[0] = parsed[0];
    rgb[1] = parsed[1];
    rgb[2] = parsed[2];
    return 1;
}

#endif
