#include "migration.h"
#ifdef _WIN32
#include "hud_prefs.h"
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* Exactly the two filenames R50 reads in this process's LocalAppData. Missing
 * inputs are optional. Refuse an unreadable or partial pair so it can be retried. */
static bool read_legacy(const wchar_t* local_data, const wchar_t* filename, char** text)
{
    static const wchar_t logs[] = L"\\CowboyBingus\\Helldivers2\\Logs\\";
    size_t chars = wcslen(local_data) + wcslen(logs) + wcslen(filename) + 1;
    if (chars > 32767) return false;
    wchar_t* path = malloc(chars * sizeof *path);
    if (!path) return false;
    wcscpy(path, local_data);
    wcscat(path, logs);
    wcscat(path, filename);
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD error = GetLastError();
    free(path);
    if (file == INVALID_HANDLE_VALUE) return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND;
    LARGE_INTEGER size;
    DWORD got = 0;
    bool ok = false;
    if (GetFileSizeEx(file, &size) && size.QuadPart >= 0 && size.QuadPart <= 4*1024*1024) {
        *text = malloc(size.LowPart + 1);
        if (*text && ReadFile(file, *text, size.LowPart, &got, NULL) && got == size.LowPart && !memchr(*text, 0, got)) {
            (*text)[got] = 0;
            ok = true;
        }
    }
    CloseHandle(file);
    return ok;
}

MigrationResult migration_first_start(const wchar_t* local_data, const wchar_t* destination)
{
    char *options = NULL, *blacklist = NULL;
    MigrationResult result = MIGRATION_FAILED;
    if (read_legacy(local_data, L"ModOptionsMenu.values", &options) &&
        read_legacy(local_data, L"DiversBestFriendBlacklist.log", &blacklist)) {
        DbfSettings s;
        settings_defaults(&s);
        if (!migration_parse(&s, options, blacklist)) result = MIGRATION_NONE;
        else if (hud_prefs_create(destination, &s)) result = MIGRATION_CREATED;
    }
    free(options);
    free(blacklist);
    return result;
}
#endif
