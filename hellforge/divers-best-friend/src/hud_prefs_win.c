#include "hud_prefs.h"

#ifdef _WIN32
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "hud_options.h"
#include "addresses_25480438.h"

enum { INI_LIMIT = 65536 };

typedef struct {
    char bytes[INI_LIMIT];
    size_t used;
} Output;

static bool put(Output* out, const char* p, size_t n)
{
    if (n > sizeof out->bytes - out->used) return false;
    memcpy(out->bytes + out->used, p, n);
    out->used += n;
    return true;
}

static bool space(char c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\v' || c == '\f';
}

static bool name_is(const char* start, const char* end, const char* name)
{
    while (start < end && space(*start)) ++start;
    while (start < end && space(end[-1])) --end;
    return (size_t)(end - start) == strlen(name) && !_strnicmp(start, name, end - start);
}

enum { SEC_HUD, SEC_BINDINGS, SEC_BLACKLIST, SEC_DBF, SEC_OTHER };
static const char* const sections[] = {"hud", "bindings", "blacklist", "dbf"};
typedef struct {
    int section;
    char key[40], value[24];
    bool seen;
} IniEdit;

typedef struct {
    IniEdit items[HUD_OPTION_COUNT + BIND_COUNT + DBF_BLACKLIST_SLOTS + 2];
    size_t count;
} Edits;

static IniEdit* add(Edits* edits, int section, const char* key)
{
    IniEdit* item = &edits->items[edits->count++];
    item->section = section;
    snprintf(item->key, sizeof item->key, "%s", key);
    return item;
}

static void add_boolean(Edits* edits, int section, const char* key, bool value)
{
    strcpy(add(edits, section, key)->value, value ? "true" : "false");
}

/* Legacy save callers own all HUD descriptors. The UI owns just the values it
 * changed; a first-start import owns all supported settings in the new file. */
static bool collect(Edits* edits, const DbfSettings* old, const DbfSettings* s, bool full)
{
    for (unsigned i = 0; i < hud_option_count(); ++i) {
        const HudOption* d = hud_option_descriptor(i);
        int value = hud_option_get(s, d->key);
        if (value < d->min || value > d->max) return false;
        if (!full && old && value == hud_option_get(old, d->key)) continue;
        snprintf(add(edits, SEC_HUD, d->key)->value, sizeof edits->items[0].value, "%d", value);
    }
    if (!full && !old) return true;
    for (unsigned i = 0; i < BIND_COUNT; ++i) {
        Binding b = s->bind[i];
        if (!full && b.kind == old->bind[i].kind && b.code == old->bind[i].code) continue;
        IniEdit* item = add(edits, SEC_BINDINGS, settings_action_key(i));
        bind_describe(&b, item->value, sizeof item->value);
        Binding check;
        if (!settings_parse_binding(item->value, &check) || check.kind != b.kind || check.code != b.code) return false;
    }
    for (int i = 0; i < dbf_blacklist_kind_count; ++i) {
        unsigned kind = dbf_blacklist_kinds[i].kind;
        if (kind >= DBF_BLACKLIST_SLOTS) return false;
        bool alias_changed = !full && ((kind == DBF_VAL_HIDE_SOS_KIND && old->hide_sos != s->hide_sos) ||
                                       (kind == DBF_VAL_HIDE_EAGLE_REARM_KIND && old->hide_eagle_rearm != s->hide_eagle_rearm));
        if (!full && !alias_changed && old->blacklist_kind[kind] == s->blacklist_kind[kind]) continue;
        char key[32];
        snprintf(key, sizeof key, "kind_%u", kind);
        add_boolean(edits, SEC_BLACKLIST, key, s->blacklist_kind[kind]);
    }
    if (full || old->hide_sos != s->hide_sos || old->blacklist_kind[DBF_VAL_HIDE_SOS_KIND] != s->blacklist_kind[DBF_VAL_HIDE_SOS_KIND]) add_boolean(edits, SEC_DBF, "hide_sos", s->hide_sos);
    if (full || old->hide_eagle_rearm != s->hide_eagle_rearm ||
        old->blacklist_kind[DBF_VAL_HIDE_EAGLE_REARM_KIND] != s->blacklist_kind[DBF_VAL_HIDE_EAGLE_REARM_KIND])
        add_boolean(edits, SEC_DBF, "hide_eagle_rearm", s->hide_eagle_rearm);
    return true;
}

static bool key_matches(const IniEdit* item, const char* p, const char* end)
{
    if (item->section != SEC_BLACKLIST) return name_is(p, end, item->key);
    while (p < end && space(*p)) ++p;
    while (end > p && space(end[-1])) --end;
    /* The reader also accepts kind_005. Replace all valid spellings, even if
     * they follow a canonical line and would otherwise override the edit. */
    if (end - p < 6 || end - p > 14 || _strnicmp(p, "kind_", 5)) return false;
    p += 5;
    while (end - p > 1 && *p == '0') ++p;
    return (size_t)(end - p) == strlen(item->key + 5) && !memcmp(p, item->key + 5, end - p);
}

static bool merge(Output* out, const char* data, size_t len, Edits* edits)
{
    const char* limit = data + len;
    const char* copy = data;
    const char* line = data;
    const char* nl = memchr(data, '\n', len);
    const char* eol = nl && (nl == data || nl[-1] != '\r') ? "\n" : "\r\n";
    int section = SEC_OTHER;
    if (len >= 3 && !memcmp(line, "\xef\xbb\xbf", 3)) line += 3;
    while (line < limit) {
        nl = memchr(line, '\n', limit - line);
        const char* end = nl ? nl : limit;
        const char* p = line;
        line = nl ? nl + 1 : limit;
        while (p < end && space(*p)) ++p;
        if (p == end || *p == '#' || *p == ';') continue;
        for (const char* q = p + 1; q < end; ++q) {
            if ((*q == '#' || *q == ';') && (q[-1] == ' ' || q[-1] == '\t')) { end = q; break; }
        }
        while (end > p && space(end[-1])) --end;
        if (*p == '[') {
            section = SEC_OTHER;
            for (int i = 0; i < SEC_OTHER; ++i)
                if (end[-1] == ']' && name_is(p + 1, end - 1, sections[i])) section = i;
            continue;
        }
        const char* eq = memchr(p, '=', end - p);
        if (!eq) continue;
        for (size_t i = 0; i < edits->count; ++i) {
            IniEdit* item = &edits->items[i];
            if (item->section != section || !key_matches(item, p, eq)) continue;
            const char* value = eq + 1;
            while (value < end && space(*value)) ++value;
            if (!put(out, copy, value - copy) || !put(out, item->value, strlen(item->value))) return false;
            item->seen = true;
            copy = end;
            break;
        }
    }
    if (!put(out, copy, limit - copy)) return false;
    for (size_t i = 0; i < edits->count; ++i) {
        const IniEdit* item = &edits->items[i];
        if (item->seen) continue;
        if (out->used && out->bytes[out->used - 1] != '\n' && !put(out, eol, strlen(eol))) return false;
        if (section != item->section) {
            section = item->section;
            if (!put(out, "[", 1) || !put(out, sections[section], strlen(sections[section])) ||
                !put(out, "]", 1) || !put(out, eol, strlen(eol))) return false;
        }
        if (!put(out, item->key, strlen(item->key)) || !put(out, " = ", 3) ||
            !put(out, item->value, strlen(item->value)) || !put(out, eol, strlen(eol))) return false;
    }
    return true;
}

static bool directory(const wchar_t* path)
{
    if (CreateDirectoryW(path, NULL)) return true;
    if (GetLastError() != ERROR_ALREADY_EXISTS) return false;
    DWORD attributes = GetFileAttributesW(path);
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY);
}

/* Only create the two known application directories below an existing base. */
static bool make_folders(wchar_t* scratch)
{
    wchar_t* file = wcsrchr(scratch, L'\\');
    if (!file || _wcsicmp(file + 1, L"settings.ini")) return false;
    *file = 0;
    wchar_t* hf = wcsrchr(scratch, L'\\');
    if (!hf || _wcsicmp(hf + 1, L"HellForge")) return false;
    *hf = 0;
    wchar_t* dbf = wcsrchr(scratch, L'\\');
    if (!dbf || _wcsicmp(dbf + 1, L"DBF") || !directory(scratch)) return false;
    *hf = L'\\';
    return directory(scratch);
}

static HANDLE reserve_writer(const wchar_t* path, wchar_t* scratch)
{
    const wchar_t suffix[] = L".dbf.lock";
    for (unsigned attempt = 0; attempt < 2; ++attempt) {
        wcscpy(scratch, path);
        wcscat(scratch, suffix);
        HANDLE lock = CreateFileW(scratch, DELETE, 0, NULL, CREATE_NEW, FILE_FLAG_DELETE_ON_CLOSE, NULL);
        if (lock != INVALID_HANDLE_VALUE || GetLastError() != ERROR_PATH_NOT_FOUND) return lock;
        wcscpy(scratch, path);
        if (attempt || !make_folders(scratch)) break;
    }
    return INVALID_HANDLE_VALUE;
}

static bool save(const wchar_t* path, const DbfSettings* old, const DbfSettings* settings, bool create)
{
    if (!path || !*path || !settings) return false;
    size_t chars = wcslen(path);
    if (chars > 32767) return false;
    wchar_t* backup = malloc((chars + 5) * sizeof *backup);
    wchar_t* tmp = malloc((chars + 40) * sizeof *tmp);
    char* original = malloc(INI_LIMIT);
    Output* out = calloc(1, sizeof *out);
    Edits* edits = calloc(1, sizeof *edits);
    HANDLE lock = INVALID_HANDLE_VALUE;
    HANDLE temp = INVALID_HANDLE_VALUE, source = INVALID_HANDLE_VALUE;
    DWORD size = 0, got = 0;
    bool owns_temp = false, ok = false, exists = false;
    if (!backup || !tmp || !original || !out || !edits) goto done;
    wcscpy(backup, path);
    wcscat(backup, L".bak");

    /* DBF writers serialize across processes. The OS releases the reservation on
     * process exit. A crash can leave an unpublished temp but cannot block a retry. */
    lock = reserve_writer(path, tmp);
    if (lock == INVALID_HANDLE_VALUE) goto done;
    static LONG serial;
    wcscpy(tmp, path);
    do {
        swprintf(tmp + chars, 40, L".dbf.%08lx.%08lx.tmp", GetCurrentProcessId(),
                 (unsigned long)InterlockedIncrement(&serial));
        temp = CreateFileW(tmp, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    } while (temp == INVALID_HANDLE_VALUE && GetLastError() == ERROR_FILE_EXISTS);
    if (temp == INVALID_HANDLE_VALUE) goto done;
    owns_temp = true;
    source = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    exists = source != INVALID_HANDLE_VALUE;
    if (create && exists) goto done;
    if (exists) {
        LARGE_INTEGER length;
        if (!GetFileSizeEx(source, &length) || length.QuadPart < 0 || length.QuadPart > INI_LIMIT) goto done;
        size = length.LowPart;
        if (!ReadFile(source, original, size, &got, NULL) || got != size || memchr(original, 0, size)) goto done;
    } else if (GetLastError() != ERROR_FILE_NOT_FOUND) goto done;
    if (!collect(edits, old, settings, create || !exists) || !merge(out, original, size, edits)) goto done;
    if (exists && out->used == size && !memcmp(original, out->bytes, size)) {
        ok = true;
        goto done;
    }
    if (!WriteFile(temp, out->bytes, (DWORD)out->used, &got, NULL) || got != out->used ||
        !FlushFileBuffers(temp)) goto done;
    if (!CloseHandle(temp)) goto done;
    temp = INVALID_HANDLE_VALUE;
    /* Publish existing files with the OS backup operation. No-op saves have
     * returned above, so .bak is the previous distinct file, byte-for-byte. */
    if (exists) {
        CloseHandle(source);
        source = INVALID_HANDLE_VALUE;
        ok = ReplaceFileW(path, tmp, backup, 0, NULL, NULL) != 0;
        if (!ok && GetLastError() == ERROR_UNABLE_TO_MOVE_REPLACEMENT_2) {
            /* The original may now be under its backup name. Restore it only
             * when the destination is still absent; preserve the backup too. */
            CopyFileW(backup, path, TRUE);
        }
    } else {
        ok = MoveFileExW(tmp, path, MOVEFILE_WRITE_THROUGH) != 0;
    }
    if (ok) owns_temp = false;
done:
    if (source != INVALID_HANDLE_VALUE) CloseHandle(source);
    if (temp != INVALID_HANDLE_VALUE) CloseHandle(temp);
    if (owns_temp) DeleteFileW(tmp);
    if (lock != INVALID_HANDLE_VALUE) CloseHandle(lock);
    free(edits);
    free(out);
    free(original);
    free(tmp);
    free(backup);
    return ok;
}
bool hud_prefs_save(const wchar_t* path, const DbfSettings* settings)
{
    return save(path, NULL, settings, false);
}

bool hud_prefs_apply(const wchar_t* path, const DbfSettings* old, const DbfSettings* updated)
{
    return old && save(path, old, updated, false);
}

bool hud_prefs_create(const wchar_t* path, const DbfSettings* settings)
{
    return save(path, NULL, settings, true);
}
#endif
