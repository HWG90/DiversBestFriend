/* Standalone Windows regression. Link with hud_prefs_win.c, settings.c and hud_options.c.
 * Works in a private directory under the Wine prefix's temp directory. */
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define DBF_ADDRESSES_DEFINE
#include "addresses_25480438.h"
#include "hud_options.h"
#include "hud_prefs.h"

static const wchar_t path[] = L".\\DBF\\HellForge\\settings.ini";
static const wchar_t lock[] = L".\\DBF\\HellForge\\settings.ini.dbf.lock";
static char data[70000], before[70000];

static void write_bytes(const wchar_t* name, const char* p, size_t n)
{
    FILE* f = _wfopen(name, L"wb");
    assert(f && fwrite(p, 1, n, f) == n && fclose(f) == 0);
}

static size_t read_bytes(const wchar_t* name)
{
    FILE* f = _wfopen(name, L"rb");
    assert(f);
    size_t n = fread(data, 1, sizeof data - 1, f);
    assert(feof(f) && !ferror(f) && fclose(f) == 0);
    data[n] = 0;
    return n;
}

static void round_trip(const DbfSettings* expected)
{
    DbfSettings actual;
    size_t n = read_bytes(path);
    settings_parse(&actual, data, n, NULL, 0);
    for (unsigned i = 0; i < hud_option_count(); ++i) {
        const char* key = hud_option_key(i);
        assert(hud_option_get(&actual, key) == hud_option_get(expected, key));
    }
}

int main(void)
{
    wchar_t base[MAX_PATH], work[MAX_PATH];
    assert(GetTempPathW(MAX_PATH, base) && GetTempFileNameW(base, L"dbf", 0, work));
    assert(DeleteFileW(work) && CreateDirectoryW(work, NULL) && SetCurrentDirectoryW(work));
    DbfSettings s;
    settings_defaults(&s);
    s.weapon_status_strip = false;
    s.vertical_offset = -125;
    s.enabled = false;
    assert(hud_prefs_save(path, &s));
    round_trip(&s);
    const char original[] = "\xef\xbb\xbf# mine\r\n[ HuD ] ; header\r\n\tWeApon_status_strip = true \t# note\r\n"
                            "vertical_offset =  ; empty\r\nenabled = 1\r\n"
                            "[bindings]\nnext = key:r\n[blacklist]\nkind_41 = true\n"
                            "[dbf]\nenabled = true ; legacy\ninput_interval_ms = 121\n"
                            "[external]\nweapon_status_strip = custom\nunknown=42";
    write_bytes(path, original, sizeof original - 1);
    assert(hud_prefs_save(path, &s));
    round_trip(&s);
    assert(!memcmp(data, original, strlen("\xef\xbb\xbf# mine\r\n[ HuD ] ; header\r\n")));
    assert(strstr(data, "\tWeApon_status_strip = 0 \t# note\r\n"));
    assert(strstr(data, "vertical_offset =-125  ; empty\r\n"));
    assert(strstr(data, strstr(original, "[bindings]")));
    size_t n = read_bytes(path);
    memcpy(before, data, n);
    assert(hud_prefs_save(path, &s) && read_bytes(path) == n && !memcmp(before, data, n));

    /* Debris from a killed process (including a reused PID) is never opened for writing. */
    wchar_t abandoned[128];
    swprintf(abandoned, 128, L"%ls.dbf.%08lx.00000004.tmp", path, GetCurrentProcessId());
    write_bytes(abandoned, "stale", 5);

    /* A fresh edit from an editor since the first save. */
    FILE* f = _wfopen(path, L"ab");
    assert(f && fputs("# external edit\r\n", f) >= 0 && !fclose(f));
    s.weapon_status_strip = true;
    assert(hud_prefs_save(path, &s));
    round_trip(&s);
    assert(strstr(data, "# external edit\r\n"));
    assert(read_bytes(abandoned) == 5 && !strcmp(data, "stale") && DeleteFileW(abandoned));

    n = read_bytes(path);
    memcpy(before, data, n);
    HANDLE editor = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    assert(editor != INVALID_HANDLE_VALUE && !hud_prefs_save(path, &s) && CloseHandle(editor));
    assert(read_bytes(path) == n && !memcmp(data, before, n));
    /* Sharing permits the merge read, then denies replacement at publication. */
    editor = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    s.weapon_status_strip = false;
    assert(editor != INVALID_HANDLE_VALUE && !hud_prefs_save(path, &s) && CloseHandle(editor));
    assert(read_bytes(path) == n && !memcmp(data, before, n));
    s.vertical_offset = INT_MAX;
    assert(!hud_prefs_save(path, &s) && read_bytes(path) == n && !memcmp(data, before, n));
    s.vertical_offset = -125;
    write_bytes(lock, "occupied", 8);
    assert(!hud_prefs_save(path, &s) && read_bytes(path) == n && !memcmp(data, before, n));
    assert(read_bytes(lock) == 8 && !memcmp(data, "occupied", 8) && DeleteFileW(lock));

    memset(before, '#', sizeof before);
    for (n = 65536; n <= 65537; ++n) {
        write_bytes(path, before, n);
        assert(!hud_prefs_save(path, &s) && read_bytes(path) == n && !memcmp(data, before, n));
        assert(GetFileAttributesW(lock) == INVALID_FILE_ATTRIBUTES);
    }
    write_bytes(path, "a\0b", 3);
    assert(!hud_prefs_save(path, &s) && read_bytes(path) == 3 && !memcmp(data, "a\0b", 3));
    assert(DeleteFileW(path) && RemoveDirectoryW(L"DBF\\HellForge") && RemoveDirectoryW(L"DBF"));
    write_bytes(L"DBF", "keep", 4);
    assert(!hud_prefs_save(path, &s) && read_bytes(L"DBF") == 4 && !strcmp(data, "keep"));
    assert(DeleteFileW(L"DBF") && SetCurrentDirectoryW(base) && RemoveDirectoryW(work));
    puts("PASS HUD preference persistence");
    return 0;
}
