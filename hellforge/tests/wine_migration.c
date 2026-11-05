/* Win32 file import, using only a synthetic LocalAppData underneath a temp directory. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <windows.h>
#define DBF_ADDRESSES_DEFINE
#include "addresses_25480438.h"
#include "migration.h"

static void write_file(const wchar_t* name, const char* data)
{
    FILE* f = _wfopen(name, L"wb");
    assert(f && fwrite(data, 1, strlen(data), f) == strlen(data) && !fclose(f));
}

int main(void)
{
    wchar_t tmp[MAX_PATH], base[MAX_PATH];
    assert(GetTempPathW(MAX_PATH, tmp) && GetTempFileNameW(tmp, L"mig", 0, base));
    assert(DeleteFileW(base) && CreateDirectoryW(base, NULL) && SetCurrentDirectoryW(base));
    const wchar_t* dst = L".\\DBF\\HellForge\\settings.ini";
    assert(migration_first_start(base, dst) == MIGRATION_NONE);
    assert(CreateDirectoryW(L"CowboyBingus", NULL));
    assert(CreateDirectoryW(L"CowboyBingus\\Helldivers2", NULL));
    assert(CreateDirectoryW(L"CowboyBingus\\Helldivers2\\Logs", NULL));
    const wchar_t* opts = L"CowboyBingus\\Helldivers2\\Logs\\ModOptionsMenu.values";
    const wchar_t* list = L"CowboyBingus\\Helldivers2\\Logs\\DiversBestFriendBlacklist.log";
    write_file(opts, "native_stratagem_radial.selection_mode\t4\n"
                     "native_stratagem_radial.cooldown_display\t3\n"
                     "native_stratagem_radial.auto_terminal_complete\tfalse\n"
                     "native_stratagem_radial.terminal_input\t2\n");
    write_file(list, "version\t3\n149\ttrue\n43\ttrue\n");
    HANDLE locked = CreateFileW(list, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
    assert(locked != INVALID_HANDLE_VALUE && migration_first_start(base, dst) == MIGRATION_FAILED);
    assert(GetFileAttributesW(dst) == INVALID_FILE_ATTRIBUTES && CloseHandle(locked));
    assert(migration_first_start(base, dst) == MIGRATION_CREATED);
    FILE* f = _wfopen(dst, L"rb");
    char data[8192];
    assert(f);
    size_t n = fread(data, 1, sizeof data, f);
    assert(n < sizeof data && !ferror(f) && !fclose(f));
    DbfSettings s;
    assert(!settings_parse(&s, data, n, NULL, 0));
    assert(s.hide_sos && s.blacklist_kind[42] && s.cooldown_display == 3 &&
           s.selection_mode_ordered == 1 && s.experimental_layout == 2 &&
           !s.auto_terminal_complete && s.terminal_input == 2);
    write_file(dst, "; user's existing ini\r\n[bindings]\r\nnext = key:r\r\n");
    assert(migration_first_start(base, dst) == MIGRATION_FAILED);
    f = _wfopen(dst, L"rb");
    assert(f);
    n = fread(data, 1, sizeof data-1, f);
    data[n] = 0;
    assert(!fclose(f) && !strcmp(data, "; user's existing ini\r\n[bindings]\r\nnext = key:r\r\n"));
    assert(DeleteFileW(dst) && DeleteFileW(opts) && DeleteFileW(list));
    assert(RemoveDirectoryW(L"DBF\\HellForge") && RemoveDirectoryW(L"DBF"));
    assert(RemoveDirectoryW(L"CowboyBingus\\Helldivers2\\Logs") &&
           RemoveDirectoryW(L"CowboyBingus\\Helldivers2") && RemoveDirectoryW(L"CowboyBingus"));
    assert(SetCurrentDirectoryW(tmp) && RemoveDirectoryW(base));
    puts("First-start import: current LocalAppData, failure/retry, INI round trip and no-replace passed");
    return 0;
}
