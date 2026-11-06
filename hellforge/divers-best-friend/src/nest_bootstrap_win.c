#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <wchar.h>
#include <string.h>
#include "nest_bootstrap_win.h"

typedef unsigned (*RuntimeAbi)(void);
typedef int (*HostInit)(const HfApi*, HfMod*);

static const OvApi* api_of(HMODULE module)
{
    OvApiFn get = (OvApiFn)(void*)GetProcAddress(module, "ov_api");
    const OvApi* api = get ? get(4) : NULL;
    return api && api->version >= 4 ? api : NULL;
}

static bool shared_runtime(HMODULE module)
{
    RuntimeAbi abi = (RuntimeAbi)(void*)GetProcAddress(module, "ov_runtime_abi");
    return abi && abi() == 1;
}

const OvApi* dbf_nest_connect(const HfApi* hf, HfMod* mod, bool* migration)
{
    *migration = false;
    bool standalone_planned = false;
    /* A late/incomplete plan must never race a standalone host's initializer.
     * Normal HellForge startup initializes every plan entry before GAME_LOADED. */
    if (hf->size >= offsetof(HfApi, mods) + sizeof hf->mods && hf->mods) {
        HfModInfo info = {.size = sizeof info};
        for (unsigned i = 0; hf->mods(mod, i, &info); ++i) {
            if (info.id && !strcmp(info.id, "goose.overlay-host")) standalone_planned = true;
            if (info.id && !strcmp(info.id, "goose.overlay-host") && !info.loaded) {
                hf->log(mod, "Planned standalone NEST has not initialized; bundled NEST deferred. Check its loader log and restart.");
                return NULL;
            }
            info.size = sizeof info;
        }
    }

    /* Different absolute paths may map different copies with the same basename.
     * Inspect them all before loading anything. Guarded copies share one API. */
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        hf->log(mod, "NEST module inventory unavailable; bundled startup deferred.");
        return NULL;
    }
    MODULEENTRY32W entry = {.dwSize = sizeof entry};
    const OvApi* active = NULL;
    HMODULE legacy = NULL;
    for (BOOL found = Module32FirstW(snapshot, &entry); found; found = Module32NextW(snapshot, &entry)) {
        if (_wcsicmp(entry.szModule, L"goose_overlay.dll")) continue;
        if (!shared_runtime(entry.hModule)) legacy = entry.hModule;
        else if (!active) active = api_of(entry.hModule);
    }
    CloseHandle(snapshot);
    if (legacy) {
        const OvApi* api = api_of(legacy);
        /* Pre-editor APIs retain DBF's established limited settings fallback.
         * Legacy .8.1 exposes the modern editor API but lacks corrected fonts. */
        *migration = api && api->version >= 9;
        hf->log(mod, "Legacy standalone NEST is active. Disable it and restart to use bundled NEST, or update standalone NEST to 0.8.2 or later. DBF's corrected editor requires the shared runtime.");
        return api;
    }
    if (active) {
        hf->log(mod, "DBF Reforged is sharing the active NEST runtime.");
        return active;
    }

    if (standalone_planned) {
        hf->log(mod, "Planned standalone NEST has no active compatible API; bundled NEST deferred. Update or disable standalone NEST and restart.");
        return NULL;
    }

    HMODULE self;
    wchar_t path[32768];
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCWSTR)&dbf_nest_connect, &self)) return NULL;
    DWORD length = GetModuleFileNameW(self, path, sizeof path / sizeof *path);
    if (!length || length >= sizeof path / sizeof *path) return NULL;
    wchar_t* name = wcsrchr(path, L'\\');
    if (!name || (size_t)(name + 1 - path) + wcslen(L"goose_overlay.dll") >= sizeof path / sizeof *path) return NULL;
    wcscpy(name + 1, L"goose_overlay.dll");
    HMODULE bundled = LoadLibraryExW(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!bundled) {
        hf->log(mod, "Bundled NEST could not load from the DBF mod folder (Windows error %lu).", GetLastError());
        return NULL;
    }
    HostInit init = (HostInit)(void*)GetProcAddress(bundled, "hellforge_mod_init");
    if (!shared_runtime(bundled) || !init) {
        hf->log(mod, "Bundled NEST lacks the shared-runtime contract; reinstall the complete DBF Reforged ZIP.");
        FreeLibrary(bundled);
        return NULL;
    }
    /* Retain this mapping even on failed init: a host may have installed SDK
     * callbacks before reporting failure. Successful hosts also pin their owner. */
    if (init(hf, mod) != 0 || !(active = api_of(bundled))) {
        hf->log(mod, "Bundled NEST initialization failed; check the host log.");
        return NULL;
    }
    hf->log(mod, "DBF Reforged connected to bundled NEST.");
    return active;
}
#endif
