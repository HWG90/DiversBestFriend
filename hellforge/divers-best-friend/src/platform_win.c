/* platform_win: DbfLock on a Windows CRITICAL_SECTION (KERNEL32), and the real BindPort. The Linux tests use
 * tests/platform_posix.c for the lock instead and fake the port. */
#include <windows.h>
#include <string.h>
#include "platform.h"
#include "platform_win.h"

_Static_assert(sizeof(CRITICAL_SECTION) <= sizeof(((DbfLock*)0)->storage), "raise DBF_LOCK_STORAGE");
_Static_assert(_Alignof(CRITICAL_SECTION) <= _Alignof(DbfLock), "DbfLock is aligned too little for a CRITICAL_SECTION");

void dbf_lock_init(DbfLock* lock)
{
    InitializeCriticalSection((CRITICAL_SECTION*)(void*)lock->storage);
}

void dbf_lock_enter(DbfLock* lock)
{
    EnterCriticalSection((CRITICAL_SECTION*)(void*)lock->storage);
}

void dbf_lock_leave(DbfLock* lock)
{
    LeaveCriticalSection((CRITICAL_SECTION*)(void*)lock->storage);
}

/* --- the BindPort ---------------------------------------------------------------------------------------------------- */

/* The DLL imports KERNEL32 and the C runtime only, so user32 and XInput are found with GetProcAddress, once. They are not
 * xinput.h's types: that header is not needed for a 16-byte state of which one field is read. */
typedef SHORT(WINAPI* GetAsyncKeyStateFn)(int);
typedef HWND(WINAPI* GetForegroundWindowFn)(void);
typedef DWORD(WINAPI* GetWindowThreadProcessIdFn)(HWND, LPDWORD);

typedef struct PadState { /* XINPUT_STATE */
    DWORD packet;
    WORD buttons; /* XINPUT_GAMEPAD.wButtons */
    BYTE left_trigger, right_trigger;
    SHORT left_x, left_y, right_x, right_y;
} PadState;
_Static_assert(sizeof(PadState) == 16, "XINPUT_STATE is 16 bytes");
typedef DWORD(WINAPI* XInputGetStateFn)(DWORD, PadState*);

#define PAD_USER 0                 /* the first controller */
#define PAD_RETRY_MS 1000u /* a controller that is not there is asked about this often (XInput can be slow to say no) */
#define WHEEL_API 7u       /* the Overlay Host API that has passive_wheel_total */

static GetAsyncKeyStateFn g_get_key_state;
static GetForegroundWindowFn g_get_foreground_window;
static GetWindowThreadProcessIdFn g_get_window_thread_process_id;
static XInputGetStateFn g_xinput_get_state;
static bool g_resolved;
static ULONGLONG g_pad_retry_at; /* GetTickCount64 value before which a missing controller is not asked about again */
static const OvApi* g_ov;

/* A system DLL: the one already in the process, else the one in the system folder (never one beside the game). */
static HMODULE system_dll(const char* name)
{
    HMODULE module = GetModuleHandleA(name);
    return module != NULL ? module : LoadLibraryExA(name, NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
}

static void* symbol(HMODULE module, const char* name)
{
    return module != NULL ? (void*)GetProcAddress(module, name) : NULL;
}

static void resolve(void)
{
    static const char* const xinput[] = { "xinput1_4.dll", "xinput9_1_0.dll" };
    HMODULE user32 = system_dll("user32.dll");
    g_get_key_state = (GetAsyncKeyStateFn)symbol(user32, "GetAsyncKeyState");
    g_get_foreground_window = (GetForegroundWindowFn)symbol(user32, "GetForegroundWindow");
    g_get_window_thread_process_id = (GetWindowThreadProcessIdFn)symbol(user32, "GetWindowThreadProcessId");
    for (size_t i = 0; i < sizeof xinput / sizeof xinput[0] && g_xinput_get_state == NULL; i++)
        g_xinput_get_state = (XInputGetStateFn)symbol(system_dll(xinput[i]), "XInputGetState");
    g_resolved = true;
}

static bool port_key_down(uint16_t vk)
{
    return g_get_key_state != NULL && (g_get_key_state((int)vk) & 0x8000) != 0;
}

/* The window in front belongs to this process: the game's (the Overlay Host draws inside it). */
static bool port_foreground(void)
{
    DWORD process = 0;
    HWND window;
    if (g_get_foreground_window == NULL || g_get_window_thread_process_id == NULL) return false;
    window = g_get_foreground_window();
    if (window == NULL) return false;
    g_get_window_thread_process_id(window, &process);
    return process == GetCurrentProcessId();
}

static bool port_wheel_total(int64_t* total)
{
    if (g_ov == NULL || g_ov->version < WHEEL_API || g_ov->passive_wheel_total == NULL ||
        g_ov->size < offsetof(OvApi, passive_wheel_total) + sizeof g_ov->passive_wheel_total)
        return false;
    *total = g_ov->passive_wheel_total();
    return true;
}

static bool port_pad_buttons(uint16_t* buttons)
{
    PadState state;
    ULONGLONG now;
    if (g_xinput_get_state == NULL) return false;
    now = GetTickCount64();
    if (now < g_pad_retry_at) return false;
    memset(&state, 0, sizeof state);
    if (g_xinput_get_state(PAD_USER, &state) != ERROR_SUCCESS) {
        g_pad_retry_at = now + PAD_RETRY_MS;
        return false;
    }
    *buttons = state.buttons;
    return true;
}

const BindPort* dbf_bind_port(const OvApi* ov)
{
    static const BindPort port = { port_key_down, port_foreground, port_wheel_total, port_pad_buttons };
    if (!g_resolved) resolve();
    g_ov = ov;
    return &port;
}
