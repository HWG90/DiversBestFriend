/* platform_win: what the DLL needs from Windows that the portable units do not ask for themselves (platform.h is the
 * lock). Implemented in platform_win.c; the Linux tests do not build it, so nothing portable includes this header.
 *
 * dbf_bind_port is the real BindPort (bindings.h): the keyboard and mouse buttons through user32's GetAsyncKeyState, the
 * game's window through GetForegroundWindow, the first controller through XInput, and the wheel through the Overlay
 * Host's passive_wheel_total (API 7). The DLL imports KERNEL32 and the C runtime only, so every other function it uses is
 * found at run time with GetProcAddress (tests/check_imports.sh fails the build on any other import). */
#ifndef DBF_PLATFORM_WIN_H
#define DBF_PLATFORM_WIN_H

#include "bindings.h"
#include "goose_overlay.h"

/* The port for bind_init. `ov` is the Overlay Host's table (NULL: none); its wheel total is used when ov->version is 7 or
 * more and passive_wheel_total is set, else wheel_total reports false. The pointer is kept, so the table must stay valid
 * (the host's does for the life of the game). Resolves user32 and XInput on the first call; the returned pointer is to a
 * static port that stays valid. Game thread. */
const BindPort* dbf_bind_port(const OvApi* ov);

#endif
