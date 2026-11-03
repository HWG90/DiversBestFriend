/* Stand-in for the kernel32/user32 calls DBF-ASS's native backend makes, so the
 * offline harness exercises real FFI C calls (JIT-compiled, allocation-free)
 * against a synthetic image. Reads outside registered ranges fail like a
 * ReadProcessMemory on unmapped memory.
 *   cc -O2 -shared -fPIC -o fake_win32.so fake_win32.c */
#include <stdint.h>
#include <string.h>
#include <stddef.h>
static uintptr_t first[8], last[8];
static int ranges;
static void *module_base;
static unsigned long long reads, writes;
void fake_add_range(uintptr_t a, uintptr_t b) { if (ranges < 8) { first[ranges] = a; last[ranges] = b; ranges++; } }
void fake_set_module(void *base) { module_base = base; }
unsigned long long fake_reads(void) { return reads; }
unsigned long long fake_writes(void) { return writes; }
/* Denied ranges imitate game code pages not decrypted yet: reads fail. */
static uintptr_t deny_first[8], deny_last[8];
static int denies;
void fake_deny_range(uintptr_t a, uintptr_t b) { if (denies < 8) { deny_first[denies] = a; deny_last[denies] = b; denies++; } }
void fake_clear_denies(void) { denies = 0; }
/* A real capture (offline_capture.lua): its all-zero pages were never decrypted
 * or never read in game, so they read as unavailable, like cold game pages. */
static const unsigned char *zero_map;
static uintptr_t zero_base;
static size_t zero_pages;
void fake_deny_zero_pages(uintptr_t base, const unsigned char *map, size_t pages) { zero_base = base; zero_map = map; zero_pages = pages; }
static int denied(uintptr_t a, size_t n) {
    for (int i = 0; i < denies; i++) if (a < deny_last[i] && a + n > deny_first[i]) return 1;
    if (zero_map && n && a + n > zero_base && a < zero_base + zero_pages * 4096) {
        uintptr_t lo = a < zero_base ? zero_base : a, hi = a + n - 1;
        for (uintptr_t p = (lo - zero_base) / 4096; p <= (hi - zero_base) / 4096 && p < zero_pages; p++) if (zero_map[p]) return 1;
    }
    return 0;
}
static int inside(uintptr_t a, size_t n) {
    for (int i = 0; i < ranges; i++) if (a >= first[i] && a + n <= last[i]) return 1;
    return 0;
}
void *GetModuleHandleA(const char *name) { (void)name; return module_base; }
void *GetCurrentProcess(void) { return (void *)(intptr_t)-1; }
int ReadProcessMemory(void *p, const void *src, void *dst, size_t n, size_t *got) {
    (void)p; reads++;
    if (!inside((uintptr_t)src, n) || denied((uintptr_t)src, n)) return 0;
    memcpy(dst, src, n); if (got) *got = n; return 1;
}
/* Writes are refused unless a check opts in (offline_terminal.lua); then they
 * land only inside registered ranges. */
static int allow_writes;
void fake_allow_writes(int on) { allow_writes = on; }
int WriteProcessMemory(void *p, void *dst, const void *src, size_t n, size_t *got) {
    (void)p; writes++;
    if (!allow_writes || !inside((uintptr_t)dst, n)) return 0;
    memcpy(dst, src, n); if (got) *got = n; return 1;
}
unsigned long long GetTickCount64(void) { return 0; }
unsigned long GetCurrentProcessId(void) { return 42; }
void *GetForegroundWindow(void) { return (void *)1; }
unsigned long GetWindowThreadProcessId(void *w, unsigned long *pid) { (void)w; if (pid) *pid = 42; return 1; }
