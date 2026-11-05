#include "hud_prefs.h"

#ifdef _WIN32
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "hud_options.h"

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

static bool put_value(Output* out, const DbfSettings* settings, const char* key)
{
    char number[16];
    int n = snprintf(number, sizeof number, "%d", hud_option_get(settings, key));
    return n > 0 && (size_t)n < sizeof number && put(out, number, (size_t)n);
}

/* Follow settings_parse's BOM, whitespace, section and inline-comment grammar.
 * Copy the original bytes in runs; only the value tokens of owned keys change. */
static bool merge(Output* out, const char* data, size_t len, const DbfSettings* settings, bool* seen)
{
    const char* limit = data + len;
    const char* copy = data;
    const char* line = data;
    const char* nl = memchr(data, '\n', len);
    const char* eol = nl && (nl == data || nl[-1] != '\r') ? "\n" : "\r\n";
    bool hud = false, dbf = false;
    if (len >= 3 && !memcmp(line, "\xef\xbb\xbf", 3)) line += 3;
    while (line < limit) {
        nl = memchr(line, '\n', limit - line);
        const char* end = nl ? nl : limit;
        const char* p = line;
        line = nl ? nl + 1 : limit;
        while (p < end && space(*p)) ++p;
        if (p == end || *p == '#' || *p == ';') continue;
        for (const char* q = p + 1; q < end; ++q) {
            if ((*q == '#' || *q == ';') && (q[-1] == ' ' || q[-1] == '\t')) {
                end = q;
                break;
            }
        }
        while (end > p && space(end[-1])) --end;
        if (*p == '[') {
            hud = end[-1] == ']' && name_is(p + 1, end - 1, "hud");
            dbf = end[-1] == ']' && name_is(p + 1, end - 1, "dbf");
            continue;
        }
        if (!hud && !dbf) continue;
        const char* eq = memchr(p, '=', end - p);
        if (!eq) continue;
        for (unsigned i = 0; i < hud_option_count(); ++i) {
            const char* key = hud_option_key(i);
            if (!name_is(p, eq, key)) continue;
            /* The reader also accepts these two aliases in [dbf]. Preserve the
             * legacy line and emit a later [hud] value if it would win. */
            if (dbf) {
                if (!strcmp(key, "enabled") || !strcmp(key, "selection_sounds")) seen[i] = false;
                break;
            }
            const char* value = eq + 1;
            while (value < end && space(*value)) ++value;
            if (!put(out, copy, value - copy) || !put_value(out, settings, key)) return false;
            seen[i] = true;
            copy = end;
            break;
        }
    }
    if (!put(out, copy, limit - copy)) return false;
    for (unsigned i = 0; i < hud_option_count(); ++i) {
        if (seen[i]) continue;
        if (out->used && out->bytes[out->used - 1] != '\n' && !put(out, eol, strlen(eol))) return false;
        if (!hud && (!put(out, "[hud]", 5) || !put(out, eol, strlen(eol)))) return false;
        hud = true;
        const char* key = hud_option_key(i);
        if (!put(out, key, strlen(key)) || !put(out, " = ", 3) ||
            !put_value(out, settings, key) || !put(out, eol, strlen(eol))) return false;
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

bool hud_prefs_save(const wchar_t* path, const DbfSettings* settings)
{
    if (!path || !*path || !settings) return false;
    size_t chars = wcslen(path);
    if (chars > 32767) return false;
    wchar_t* tmp = malloc((chars + 40) * sizeof *tmp);
    char* original = malloc(INI_LIMIT);
    Output* out = calloc(1, sizeof *out);
    bool* seen = calloc(hud_option_count(), sizeof *seen);
    HANDLE lock = INVALID_HANDLE_VALUE;
    HANDLE temp = INVALID_HANDLE_VALUE, source = INVALID_HANDLE_VALUE;
    DWORD size = 0, got = 0;
    bool owns_temp = false, ok = false, exists = false;
    if (!tmp || !original || !out || !seen) goto done;
    for (unsigned i = 0; i < hud_option_count(); ++i) {
        const HudOption* option = hud_option_descriptor(i);
        int value = hud_option_get(settings, option->key);
        if (value < option->min || value > option->max) goto done;
    }

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
    if (exists) {
        LARGE_INTEGER length;
        if (!GetFileSizeEx(source, &length) || length.QuadPart < 0 || length.QuadPart > INI_LIMIT) goto done;
        size = length.LowPart;
        if (!ReadFile(source, original, size, &got, NULL) || got != size || memchr(original, 0, size)) goto done;
    } else if (GetLastError() != ERROR_FILE_NOT_FOUND) goto done;
    if (!merge(out, original, size, settings, seen)) goto done;
    if (exists && out->used == size && !memcmp(original, out->bytes, size)) {
        ok = true;
        goto done;
    }
    if (!WriteFile(temp, out->bytes, (DWORD)out->used, &got, NULL) || got != out->used ||
        !FlushFileBuffers(temp)) goto done;
    if (!CloseHandle(temp)) goto done;
    temp = INVALID_HANDLE_VALUE;
    /* Deny writes and deletes to the source through the flush. Release immediately
     * before the same-directory rename; for an absent original use no-replace. */
    if (exists) {
        CloseHandle(source);
        source = INVALID_HANDLE_VALUE;
    }
    ok = MoveFileExW(tmp, path, MOVEFILE_WRITE_THROUGH | (exists ? MOVEFILE_REPLACE_EXISTING : 0)) != 0;
    if (ok) owns_temp = false;
done:
    if (source != INVALID_HANDLE_VALUE) CloseHandle(source);
    if (temp != INVALID_HANDLE_VALUE) CloseHandle(temp);
    if (owns_temp) DeleteFileW(tmp);
    if (lock != INVALID_HANDLE_VALUE) CloseHandle(lock);
    free(seen);
    free(out);
    free(original);
    free(tmp);
    return ok;
}
#endif
