/* bindings: DBF's own keys (Next, Previous, Confirm and the slot hotkeys 1..4) turned into one level per action per tick.
 *
 * A Binding says which input drives an action: a keyboard key, a mouse button, one direction of the mouse wheel or a
 * controller button. bind_poll reads them through a BindPort (the operating system's side: src/platform_win.c has the real
 * one, the tests have fakes) and gives each action a level that is true while its input is down (once it has been seen up:
 * see Release after a block below). A wheel notch is not a held input, so a wheel binding is true for one poll per notch.
 *
 * Nothing fires unless the caller says it may: bind_poll's `allowed` is the caller's gate (DBF enabled, the game's UI not
 * obstructed, no Overlay Host window open: the host's input_captured query), and the
 * game's window must be in front (BindPort.foreground). While either is false every level is false.
 *
 * The wheel. The Overlay Host (API 7, host 0.5.0) keeps a total of the wheel since it started, in WHEEL_DELTA units (120 per
 * notch, + up), that nobody resets: every reader keeps its own last value and takes the difference, so two mods never take
 * notches from each other. bind_poll turns the difference into whole notches (toward zero; the rest of a notch stays in the
 * total and is counted with the next movement, so a mouse that sends 30 or 60 units at a time still gives notches). Notches
 * up are pending pulses of wheel_up, notches down of wheel_down. A direction pulses on at most every other poll: a poll
 * that gave a pulse is followed by a poll with none even when notches are pending, and only then does the next one pulse, so
 * three notches are true, false, true, false, true, false over six polls (a level that is true for three polls in a row
 * would be one rising edge to a consumer that takes edges, as List Select does, and the other two notches would be lost).
 * Every action bound to that direction gets the pulse. At most BIND_WHEEL_PENDING_MAX pulses wait per direction. Up and
 * down notches between two polls cancel (the total only knows the net movement). While nothing may fire, the pending pulses
 * are dropped and the baseline moves to the current total, so a notch turned then is gone for good. The baseline is taken
 * at bind_init (or at the first poll that can read the total); what was turned before is not DBF's.
 *
 * Release after a block. A key, mouse button or controller button that is down when nothing could fire is not a press:
 * a level can only be true for an action whose input has been seen up on an allowed poll since the module started
 * (bind_init) or since the last poll that could not fire (`allowed` false, or the game's window not in front). Until then
 * the level stays false though the input is down, and the poll that sees it up arms it, so the poll after that, with the
 * input down again, is true at once. A Confirm that opened the stratagem menu, or was held through a window that blocked
 * input, therefore does not confirm anything, and an input that was up when the block ended works the moment it is
 * pressed. It is judged per action, and an input is only looked at on allowed polls (a block-time release and press is
 * not seen). A controller that is absent counts as up. The wheel is not held, so it is outside the rule: a pulse is
 * true on the first allowed poll that has one (notches turned while blocked were already dropped).
 *
 * Portable C11: standard headers only. No windows.h, no Overlay Host header: the BindPort is the whole interface. */
#ifndef DBF_BINDINGS_H
#define DBF_BINDINGS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum { BIND_NONE, BIND_KEY, BIND_MOUSE, BIND_WHEEL_UP, BIND_WHEEL_DOWN, BIND_PAD } BindKind;

/* kind BIND_KEY: code is a Windows virtual-key code (1..0xFE); BIND_MOUSE: 1 left, 2 right, 3 middle, 4 and 5 the side
 * buttons (read as VK_LBUTTON, VK_RBUTTON, VK_MBUTTON, VK_XBUTTON1, VK_XBUTTON2 through BindPort.key_down); BIND_PAD:
 * an XInput wButtons mask with one bit; BIND_NONE and the wheel kinds: code is 0. */
typedef struct Binding {
    uint8_t kind;
    uint16_t code;
} Binding;

typedef enum {
    BIND_NEXT, BIND_PREVIOUS, BIND_CONFIRM, BIND_SLOT1, BIND_SLOT2, BIND_SLOT3, BIND_SLOT4, BIND_COUNT
} BindAction;

/* XInput's wButtons bits (xinput.h XINPUT_GAMEPAD_*), named here so portable code and the settings file need no header. */
#define BIND_PAD_DPAD_UP 0x0001
#define BIND_PAD_DPAD_DOWN 0x0002
#define BIND_PAD_DPAD_LEFT 0x0004
#define BIND_PAD_DPAD_RIGHT 0x0008
#define BIND_PAD_START 0x0010
#define BIND_PAD_BACK 0x0020
#define BIND_PAD_LS 0x0040
#define BIND_PAD_RS 0x0080
#define BIND_PAD_LB 0x0100
#define BIND_PAD_RB 0x0200
#define BIND_PAD_A 0x1000
#define BIND_PAD_B 0x2000
#define BIND_PAD_X 0x4000
#define BIND_PAD_Y 0x8000

#define BIND_WHEEL_NOTCH 120           /* WHEEL_DELTA */
#define BIND_WHEEL_PENDING_MAX 64      /* pulses that wait per direction */
#define BIND_STATUS_NEEDS_HOST "wheel bindings need Overlay Host 0.5.0"

/* The operating system's side. Any member may be NULL: key_down, wheel_total and pad_buttons then never report anything;
 * a NULL foreground counts as "not in front" (nothing fires), so a port that forgets it is quiet rather than live. All are
 * called from the game thread only. */
typedef struct BindPort {
    bool (*key_down)(uint16_t vk);          /* the key or mouse button is down right now (GetAsyncKeyState's high bit) */
    bool (*foreground)(void);               /* the game's window is in front */
    bool (*wheel_total)(int64_t* total);    /* the Overlay Host's wheel total (API 7); false when older or absent */
    bool (*pad_buttons)(uint16_t* buttons); /* XInput user 0's wButtons; false when there is no controller */
} BindPort;

/* Starts (or restarts) the module: copies the port and the map, takes the wheel baseline, forgets pending and just-given
 * pulses, and takes every input as not yet seen up (the release rule above: a key held now does nothing until it is let
 * go). A binding that cannot work (an unknown kind, a mouse code outside 1..5, a key or pad code of 0) counts as BIND_NONE.
 * A NULL port reads nothing; a NULL map binds nothing. */
void bind_init(const BindPort* port, const Binding map[BIND_COUNT]);

/* Reads the inputs once and writes levels[BIND_COUNT]: true for an action whose input is down and has been seen up since
 * the module started or could last not fire (the release rule above; a wheel notch: for this poll only, and never on two
 * polls in a row). `allowed` false, or the game's window not in front: every level is false, every input has to be seen up
 * again before it can be true, pending wheel pulses are dropped and the wheel baseline moves on. `status` (n bytes, NULL
 * or 0 allowed) gets "" or, when a wheel binding is set and the port has no wheel total, BIND_STATUS_NEEDS_HOST; it is
 * always terminated and cut to fit. Before bind_init every level is false. */
void bind_poll(bool levels[BIND_COUNT], bool allowed, char* status, size_t n);

#endif
