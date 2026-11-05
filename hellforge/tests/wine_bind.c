/* wine_bind: the real BindPort of src/platform_win.c (dbf_bind_port) under Proton's Wine. Built by build.sh wine-test as
 * wine_bind.exe from this file and platform_win.c, which imports KERNEL32 and the C runtime only, as the DLL does: this
 * program finds the user32 calls it needs itself with GetProcAddress too, so user32 is loaded by whoever asks first, as it
 * is in the game.
 *
 * What it proves: the port resolves user32 and XInput by name at run time; the wheel total is read only from an Overlay
 * Host table of version 7 or later that holds it; GetAsyncKeyState's high bit is what key_down reports (a key this program
 * presses itself); the foreground check says yes for a window of this process that is in front. What an environment cannot
 * give (a window that takes the foreground, a keyboard event that reaches the key state) is reported as SKIP, not as a
 * failure; a controller may or may not be attached to the prefix, so the pad is only exercised.
 * Prints "== bind-port: <n> failure(s)" last, as wine_host does for its cases. */
#include <windows.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "platform_win.h"
#include "test.h"

#define VK_PROBE 0x87 /* VK_F24: nothing listens to it */

static int64_t g_wheel;
static int64_t fake_wheel_total(void)
{
    return g_wheel;
}

typedef SHORT(WINAPI* KeyStateFn)(int);
typedef HWND(WINAPI* ForegroundFn)(void);
typedef void(WINAPI* KeybdEventFn)(BYTE, BYTE, DWORD, ULONG_PTR);
typedef HWND(WINAPI* CreateWindowFn)(DWORD, LPCSTR, LPCSTR, DWORD, int, int, int, int, HWND, HMENU, HINSTANCE, LPVOID);
typedef BOOL(WINAPI* SetForegroundFn)(HWND);
typedef BOOL(WINAPI* DestroyWindowFn)(HWND);

static void test_wheel(void)
{
    OvApi ov;
    int64_t total = 99;
    const BindPort* port = dbf_bind_port(NULL);
    CHECK(port != NULL && port->key_down && port->foreground && port->wheel_total && port->pad_buttons, "the port has all four functions");
    CHECK(!port->wheel_total(&total) && total == 99, "no Overlay Host: wheel_total is false and writes nothing");

    memset(&ov, 0, sizeof ov);
    ov.size = sizeof ov;
    ov.version = 7;
    ov.passive_wheel_total = fake_wheel_total;
    g_wheel = 360;
    port = dbf_bind_port(&ov);
    CHECK(port->wheel_total(&total) && total == 360, "an API 7 host: the total it reports (360)");
    g_wheel = -120;
    CHECK(port->wheel_total(&total) && total == -120, "and it follows the host, negative included (-120)");
    g_wheel = (int64_t)1 << 40;
    CHECK(port->wheel_total(&total) && total == ((int64_t)1 << 40), "and it is 64 bits wide");

    total = 99;
    ov.version = 6;
    CHECK(!port->wheel_total(&total) && total == 99, "an API 6 host has no wheel total: false");
    ov.version = 5;
    CHECK(!port->wheel_total(&total), "an API 5 host: false");
    ov.version = 7;
    ov.passive_wheel_total = NULL;
    CHECK(!port->wheel_total(&total), "version 7 with no passive_wheel_total: false");
    ov.passive_wheel_total = fake_wheel_total;
    ov.size = offsetof(OvApi, passive_wheel_total);
    CHECK(!port->wheel_total(&total), "a table that ends before passive_wheel_total: false");
    ov.size = sizeof ov;
    g_wheel = 5;
    CHECK(port->wheel_total(&total) && total == 5, "and a whole one again: true");
    port = dbf_bind_port(NULL);
    CHECK(!port->wheel_total(&total), "dbf_bind_port(NULL) forgets the host");
}

static void test_keys_and_foreground(void)
{
    HMODULE user32;
    KeyStateFn key_state;
    ForegroundFn foreground;
    KeybdEventFn keybd_event_fn;
    CreateWindowFn create_window;
    SetForegroundFn set_foreground;
    DestroyWindowFn destroy_window;
    const BindPort* port = dbf_bind_port(NULL);
    HWND window;

    user32 = GetModuleHandleA("user32.dll");
    if (user32 == NULL) user32 = LoadLibraryA("user32.dll");
    if (user32 == NULL) {
        CHECK(false, "user32.dll loads");
        return;
    }
    key_state = (KeyStateFn)(void*)GetProcAddress(user32, "GetAsyncKeyState");
    foreground = (ForegroundFn)(void*)GetProcAddress(user32, "GetForegroundWindow");
    keybd_event_fn = (KeybdEventFn)(void*)GetProcAddress(user32, "keybd_event");
    create_window = (CreateWindowFn)(void*)GetProcAddress(user32, "CreateWindowExA");
    set_foreground = (SetForegroundFn)(void*)GetProcAddress(user32, "SetForegroundWindow");
    destroy_window = (DestroyWindowFn)(void*)GetProcAddress(user32, "DestroyWindow");
    CHECK(key_state && foreground && keybd_event_fn && create_window && set_foreground && destroy_window, "the probe finds its own user32 calls");

    CHECK(!port->key_down(VK_PROBE), "key_down: a key nobody presses is up");
    keybd_event_fn(VK_PROBE, 0, 0, 0);
    if ((key_state(VK_PROBE) & 0x8000) != 0) {
        CHECK(port->key_down(VK_PROBE), "key_down: the key this program pressed is down");
        CHECK(!port->key_down(VK_PROBE + 1), "key_down: another key is not");
        keybd_event_fn(VK_PROBE, 0, KEYEVENTF_KEYUP, 0);
        CHECK(port->key_down(VK_PROBE) == ((key_state(VK_PROBE) & 0x8000) != 0), "key_down: released, it agrees with GetAsyncKeyState again");
    } else {
        keybd_event_fn(VK_PROBE, 0, KEYEVENTF_KEYUP, 0);
        printf("SKIP key_down with a pressed key: this Wine session does not show a synthesised key in GetAsyncKeyState\n");
    }

    window = create_window(0, "STATIC", "DBF probe", WS_POPUP | WS_VISIBLE, 0, 0, 64, 64, NULL, NULL, GetModuleHandleA(NULL), NULL);
    if (window != NULL) {
        set_foreground(window);
        if (foreground() == window) {
            CHECK(port->foreground(), "foreground: a window of this process is in front");
        } else {
            printf("SKIP foreground with a window in front: this Wine session gave the window no foreground\n");
        }
        destroy_window(window);
    } else {
        printf("SKIP foreground with a window in front: no window could be created here\n");
    }
    {
        HWND front = foreground();
        DWORD process = 0;
        typedef DWORD(WINAPI * ProcessFn)(HWND, LPDWORD);
        ProcessFn thread_process = (ProcessFn)(void*)GetProcAddress(user32, "GetWindowThreadProcessId");
        if (front != NULL && thread_process != NULL) thread_process(front, &process);
        CHECK(port->foreground() == (front != NULL && process == GetCurrentProcessId()), "foreground: true exactly when the front window is this process's");
    }
}

static void test_pad(void)
{
    const BindPort* port = dbf_bind_port(NULL);
    uint16_t buttons = 0xAAAA;
    bool first = port->pad_buttons(&buttons);
    bool loaded = GetModuleHandleA("xinput1_4.dll") != NULL || GetModuleHandleA("xinput9_1_0.dll") != NULL;
    CHECK(loaded, "pad_buttons: XInput was found and loaded (xinput1_4.dll or xinput9_1_0.dll)");
    if (first) {
        printf("PASS pad_buttons: a controller is attached, wButtons 0x%04x\n", buttons);
    } else {
        CHECK(buttons == 0xAAAA, "pad_buttons: no controller, false and nothing written");
        CHECK(!port->pad_buttons(&buttons), "pad_buttons: asked again at once, still false");
    }
}

int main(void)
{
    test_wheel();
    test_keys_and_foreground();
    test_pad();
    printf("== bind-port: %d failure(s)\n", test_failures());
    TEST_MAIN_END
}
