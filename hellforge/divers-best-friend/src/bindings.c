/* bindings: see bindings.h. */
#include <string.h>
#include "bindings.h"

/* The state of the module. The game thread's only: bind_init and bind_poll are both called from the tick. */
static BindPort g_port;
static Binding g_map[BIND_COUNT];
static bool g_started;     /* bind_init ran */
static bool g_wheel_bound; /* some action is on wheel_up or wheel_down */
static bool g_pad_bound;   /* some action is on a controller button */
static int64_t g_base;     /* the wheel total the notches are counted from */
static bool g_base_valid;  /* g_base holds a real total */
static int g_pending[2];   /* notches waiting to be handed out, [0] up, [1] down */
static bool g_gap[2];      /* the direction pulsed on the last poll, so it may not on this one (see bind_poll) */
static bool g_seen_up[BIND_COUNT]; /* the action's key, mouse button or pad button has been up on an allowed poll since
                                      bind_init or the last poll that could not fire; only then may its level be true
                                      (the release rule in bindings.h) */

enum { DIR_UP = 0, DIR_DOWN = 1 };

/* The virtual-key code each mouse button is read as (index 1..5). */
static const uint16_t g_mouse_vk[6] = { 0, 0x01 /* VK_LBUTTON */, 0x02 /* VK_RBUTTON */, 0x04 /* VK_MBUTTON */,
                                        0x05 /* VK_XBUTTON1 */, 0x06 /* VK_XBUTTON2 */ };

static void set_status(char* status, size_t n, const char* text)
{
    size_t i = 0;
    if (status == NULL || n == 0) return;
    while (i < n - 1 && text[i] != '\0') {
        status[i] = text[i];
        i++;
    }
    status[i] = '\0';
}

/* A binding that cannot work counts as none, so poll need not check the codes. */
static Binding sanitise(Binding b)
{
    Binding none = { BIND_NONE, 0 };
    switch (b.kind) {
    case BIND_KEY: return b.code >= 1 && b.code <= 0xFF ? b : none;
    case BIND_MOUSE: return b.code >= 1 && b.code <= 5 ? b : none;
    case BIND_PAD: return b.code != 0 ? b : none;
    case BIND_WHEEL_UP:
    case BIND_WHEEL_DOWN: b.code = 0; return b;
    default: return none;
    }
}

static bool read_total(int64_t* total)
{
    return g_port.wheel_total != NULL && g_port.wheel_total(total);
}

void bind_init(const BindPort* port, const Binding map[BIND_COUNT])
{
    int64_t total = 0;
    memset(&g_port, 0, sizeof g_port);
    if (port != NULL) g_port = *port;
    g_wheel_bound = false;
    g_pad_bound = false;
    for (int i = 0; i < BIND_COUNT; i++) {
        Binding none = { BIND_NONE, 0 };
        g_map[i] = map != NULL ? sanitise(map[i]) : none;
        g_wheel_bound |= g_map[i].kind == BIND_WHEEL_UP || g_map[i].kind == BIND_WHEEL_DOWN;
        g_pad_bound |= g_map[i].kind == BIND_PAD;
    }
    g_pending[DIR_UP] = g_pending[DIR_DOWN] = 0;
    g_gap[DIR_UP] = g_gap[DIR_DOWN] = false;
    memset(g_seen_up, 0, sizeof g_seen_up);
    g_base_valid = read_total(&total);
    g_base = g_base_valid ? total : 0;
    g_started = true;
}

static void add_pending(int direction, int64_t notches)
{
    int64_t room = BIND_WHEEL_PENDING_MAX - g_pending[direction];
    g_pending[direction] += (int)(notches < room ? notches : room);
}

/* Takes the notches turned since the last call into the pending pulses. The remainder of a notch stays in the total
 * (g_base moves by whole notches only), so small steps add up. */
static void take_notches(int64_t total)
{
    int64_t notches;
    if (!g_base_valid) {
        g_base = total;
        g_base_valid = true;
        return;
    }
    notches = (total - g_base) / BIND_WHEEL_NOTCH; /* toward zero */
    g_base += notches * BIND_WHEEL_NOTCH;
    if (notches > 0) add_pending(DIR_UP, notches);
    if (notches < 0) add_pending(DIR_DOWN, -notches);
}

void bind_poll(bool levels[BIND_COUNT], bool allowed, char* status, size_t n)
{
    int64_t total = 0;
    bool have_total, pulse[2] = { false, false }, pad_ok = false;
    uint16_t buttons = 0;

    if (levels != NULL)
        for (int i = 0; i < BIND_COUNT; i++) levels[i] = false;
    set_status(status, n, "");
    if (!g_started || levels == NULL) return;

    have_total = read_total(&total);
    if (g_wheel_bound && !have_total) set_status(status, n, BIND_STATUS_NEEDS_HOST);
    if (!have_total) g_base_valid = false; /* a total that comes back later is a new baseline, not a jump */

    /* Nothing fires unless the caller allows it and the game's window is in front. Then what the wheel did is gone: the
     * pending pulses are dropped and the baseline moves to the total. */
    if (!allowed || g_port.foreground == NULL || !g_port.foreground()) {
        g_pending[DIR_UP] = g_pending[DIR_DOWN] = 0;
        g_gap[DIR_UP] = g_gap[DIR_DOWN] = false; /* this poll is a false one already */
        memset(g_seen_up, 0, sizeof g_seen_up); /* what is held now was held while nothing could fire */
        if (have_total) {
            g_base = total;
            g_base_valid = true;
        }
        return;
    }

    if (have_total) take_notches(total);
    /* A direction pulses on at most every other poll: the poll after a pulse is false whatever waits, so that a consumer
     * that takes edges (a rising level) sees every notch as an edge. Notches queued behind it wait their turn. */
    for (int d = 0; d < 2; d++) {
        pulse[d] = g_pending[d] > 0 && !g_gap[d];
        if (pulse[d]) g_pending[d]--;
        g_gap[d] = pulse[d];
    }
    if (g_pad_bound && g_port.pad_buttons != NULL) pad_ok = g_port.pad_buttons(&buttons);

    for (int i = 0; i < BIND_COUNT; i++) {
        const Binding* b = &g_map[i];
        bool held = false; /* a key, mouse button or pad button that is down; a wheel pulse is not held */
        switch (b->kind) {
        case BIND_KEY: held = g_port.key_down != NULL && g_port.key_down(b->code); break;
        case BIND_MOUSE: held = g_port.key_down != NULL && g_port.key_down(g_mouse_vk[b->code]); break;
        case BIND_WHEEL_UP: levels[i] = pulse[DIR_UP]; continue;
        case BIND_WHEEL_DOWN: levels[i] = pulse[DIR_DOWN]; continue;
        case BIND_PAD: held = pad_ok && (buttons & b->code) != 0; break;
        default: continue;
        }
        /* An input seen down before it was ever seen up on an allowed poll was pressed while nothing could fire (or
         * before the module started): it does nothing until it is let go. */
        if (!held) g_seen_up[i] = true;
        levels[i] = held && g_seen_up[i];
    }
}
