/* Tests for src/bindings.c: the keys, mouse buttons, wheel notches and controller buttons that drive DBF's actions, read
 * through a fake BindPort. bindings.c keeps its state in statics, so every test starts with bind_init (test_before_init
 * runs first, while nothing has been started). The wheel total is the Overlay Host's: + is up, 120 units a notch. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "bindings.h"
#include "test.h"

/* --- the fake port --------------------------------------------------------------------------------------------- */

static bool g_keys[256];
static bool g_front = true;
static bool g_wheel_ok = true;
static int64_t g_total;
static bool g_pad_ok;
static uint16_t g_pad;
static int g_key_calls, g_front_calls, g_wheel_calls, g_pad_calls;

static bool fake_key_down(uint16_t vk)
{
    g_key_calls++;
    return vk < 256 && g_keys[vk];
}
static bool fake_foreground(void)
{
    g_front_calls++;
    return g_front;
}
static bool fake_wheel_total(int64_t* total)
{
    g_wheel_calls++;
    if (!g_wheel_ok) return false;
    *total = g_total;
    return true;
}
static bool fake_pad_buttons(uint16_t* buttons)
{
    g_pad_calls++;
    if (!g_pad_ok) return false;
    *buttons = g_pad;
    return true;
}

static const BindPort g_port = { fake_key_down, fake_foreground, fake_wheel_total, fake_pad_buttons };

static void reset_fake(void)
{
    memset(g_keys, 0, sizeof g_keys);
    g_front = true;
    g_wheel_ok = true;
    g_total = 0;
    g_pad_ok = true;
    g_pad = 0;
    g_key_calls = g_front_calls = g_wheel_calls = g_pad_calls = 0;
}

static Binding key(unsigned vk) { Binding b = { BIND_KEY, (uint16_t)vk }; return b; }
static Binding mouse(unsigned n) { Binding b = { BIND_MOUSE, (uint16_t)n }; return b; }
static Binding pad(unsigned mask) { Binding b = { BIND_PAD, (uint16_t)mask }; return b; }
static Binding wheel_up(void) { Binding b = { BIND_WHEEL_UP, 0 }; return b; }
static Binding wheel_down(void) { Binding b = { BIND_WHEEL_DOWN, 0 }; return b; }

/* The defaults' map: next = wheel_down, previous = wheel_up, confirm = mouse1, the slots unbound. */
static void default_map(Binding map[BIND_COUNT])
{
    memset(map, 0, BIND_COUNT * sizeof map[0]);
    map[BIND_NEXT] = wheel_down();
    map[BIND_PREVIOUS] = wheel_up();
    map[BIND_CONFIRM] = mouse(1);
}

static char g_status[128];
static bool g_levels[BIND_COUNT];

static void poll(bool allowed)
{
    bind_poll(g_levels, allowed, g_status, sizeof g_status);
}

/* bind_init right after a reset of the fake, and nothing polled: the first poll is the first one after bind_init. */
static void start_cold(const Binding map[BIND_COUNT])
{
    reset_fake();
    bind_init(&g_port, map);
}

/* start_cold, then one allowed poll with every input up (reset_fake releases them all): each action has been seen up, as
 * a mod that has run for a moment has seen it, so a test that presses a key next sees it work at once. The counters of
 * the fake start from zero after it. */
static void start(const Binding map[BIND_COUNT])
{
    start_cold(map);
    poll(true);
    g_key_calls = g_front_calls = g_wheel_calls = g_pad_calls = 0;
}

static bool only(BindAction a)
{
    for (int i = 0; i < BIND_COUNT; i++)
        if (g_levels[i] != (i == (int)a)) return false;
    return true;
}

static bool none_down(void)
{
    for (int i = 0; i < BIND_COUNT; i++)
        if (g_levels[i]) return false;
    return true;
}

/* How many polls in a row (up to `max`) have `a` true, with nothing else changing. */
static int pulses(BindAction a, int max)
{
    int n = 0;
    for (int i = 0; i < max; i++) {
        poll(true);
        if (!g_levels[a]) break;
        n++;
    }
    return n;
}

static void turn(int notches) { g_total += (int64_t)notches * 120; }

/* --- tests ----------------------------------------------------------------------------------------------------- */

static void test_before_init(void)
{
    bool levels[BIND_COUNT];
    char status[16] = "xxxx";
    memset(levels, 1, sizeof levels);
    bind_poll(levels, true, status, sizeof status);
    bool all_false = true;
    for (int i = 0; i < BIND_COUNT; i++) all_false &= !levels[i];
    CHECK(all_false, "before bind_init, every level is false");
    CHECK(status[0] == '\0', "before bind_init, the status is empty");
}

static void test_nothing_down(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    start(map);
    poll(true);
    CHECK(none_down(), "nothing pressed: every level is false");
    CHECK(g_status[0] == '\0', "and the status is empty when the wheel is available");
    for (int i = 0; i < 5; i++) poll(true);
    CHECK(none_down(), "and stays false");
}

static void test_keys(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    map[BIND_SLOT1] = key(0x31);
    map[BIND_SLOT2] = key('Q');
    start(map);
    g_keys[0x31] = true;
    poll(true);
    CHECK(only(BIND_SLOT1), "key 0x31 down: slot1 only");
    poll(true);
    CHECK(only(BIND_SLOT1), "still held: still true (a level, not a pulse)");
    g_keys[0x31] = false;
    poll(true);
    CHECK(none_down(), "released: false");
    g_keys['Q'] = true;
    g_keys[0x31] = true;
    poll(true);
    CHECK(g_levels[BIND_SLOT1] && g_levels[BIND_SLOT2] && !g_levels[BIND_NEXT] && !g_levels[BIND_CONFIRM],
          "two keys together: both slots");
    g_keys['W'] = true;
    poll(true);
    CHECK(g_levels[BIND_SLOT1] && g_levels[BIND_SLOT2], "a key nobody bound changes nothing");
}

static void test_mouse_buttons(void)
{
    static const uint16_t vk[6] = { 0, 0x01, 0x02, 0x04, 0x05, 0x06 };
    Binding map[BIND_COUNT];
    for (unsigned b = 1; b <= 5; b++) {
        char text[64];
        memset(map, 0, sizeof map);
        map[BIND_SLOT3] = mouse(b);
        start(map);
        g_keys[vk[b]] = true;
        poll(true);
        snprintf(text, sizeof text, "mouse%u is read as virtual key 0x%02x", b, vk[b]);
        CHECK(only(BIND_SLOT3), text);
        g_keys[vk[b]] = false;
        for (unsigned other = 1; other <= 5; other++) {
            if (other == b) continue;
            g_keys[vk[other]] = true;
        }
        poll(true);
        snprintf(text, sizeof text, "mouse%u: the other four buttons do not drive it", b);
        CHECK(none_down(), text);
    }
}

static void test_pad(void)
{
    Binding map[BIND_COUNT];
    memset(map, 0, sizeof map);
    map[BIND_SLOT1] = pad(BIND_PAD_DPAD_UP);
    map[BIND_SLOT2] = pad(BIND_PAD_A);
    map[BIND_CONFIRM] = pad(BIND_PAD_Y);
    start(map);
    poll(true);
    CHECK(none_down(), "pad: nothing held");
    g_pad = BIND_PAD_DPAD_UP;
    poll(true);
    CHECK(only(BIND_SLOT1), "pad: dpad_up drives slot1 only");
    g_pad = BIND_PAD_DPAD_DOWN | BIND_PAD_B;
    poll(true);
    CHECK(none_down(), "pad: other buttons drive nothing");
    g_pad = BIND_PAD_DPAD_UP | BIND_PAD_A | BIND_PAD_LB;
    poll(true);
    CHECK(g_levels[BIND_SLOT1] && g_levels[BIND_SLOT2] && !g_levels[BIND_CONFIRM], "pad: two buttons together");
    g_pad = BIND_PAD_Y;
    poll(true);
    CHECK(only(BIND_CONFIRM), "pad: Y (0x8000) drives confirm");
    g_pad = 0xffff;
    poll(true);
    CHECK(g_levels[BIND_SLOT1] && g_levels[BIND_SLOT2] && g_levels[BIND_CONFIRM], "pad: every button held: all three");
    g_pad_ok = false;
    poll(true);
    CHECK(none_down(), "pad: no controller (pad_buttons false): false");
    CHECK(g_status[0] == '\0', "pad: and no status text for it");

    default_map(map);
    start(map);
    g_pad = 0xffff;
    for (int i = 0; i < 3; i++) poll(true);
    CHECK(g_pad_calls == 0, "no pad binding: the controller is not polled");
}

static void test_wheel_notches(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    start(map);
    turn(-3); /* three notches down: next */
    CHECK(pulses(BIND_NEXT, 10) == 3, "total -360: three polls of next (wheel_down), then false");
    CHECK(none_down(), "and it stays false afterwards");
    poll(true);
    CHECK(none_down(), "a further poll: still false");

    turn(+2);
    poll(true);
    CHECK(only(BIND_PREVIOUS), "total +240: previous (wheel_up) on the first poll");
    poll(true);
    CHECK(only(BIND_PREVIOUS), "and on the second");
    poll(true);
    CHECK(none_down(), "and then false");

    map[BIND_NEXT] = wheel_up();
    map[BIND_PREVIOUS] = wheel_down();
    start(map);
    turn(3);
    CHECK(pulses(BIND_NEXT, 10) == 3, "with next on wheel_up, total +360 gives three polls of next, then false");
}

static void test_wheel_one_pulse_per_poll(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    start(map);
    turn(-3);
    poll(true);
    CHECK(only(BIND_NEXT), "three notches: the first poll has one pulse");
    turn(-1);
    CHECK(pulses(BIND_NEXT, 10) == 3, "one more notch while two wait: three more polls");
    turn(2);
    turn(-2);
    poll(true);
    CHECK(none_down(), "up and down notches between two polls cancel (the total only knows the net)");

    turn(-2);
    poll(true);
    turn(5);
    poll(true);
    CHECK(g_levels[BIND_NEXT] && g_levels[BIND_PREVIOUS], "a pulse of each direction pending: one poll gives both, one each");
    CHECK(pulses(BIND_PREVIOUS, 10) == 4, "and the remaining notches follow one per poll");
}

static void test_wheel_fractions(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    start(map);
    g_total += 60;
    poll(true);
    CHECK(none_down(), "half a notch (+60): nothing yet");
    g_total += 60;
    poll(true);
    CHECK(only(BIND_PREVIOUS), "another half (+120 in all): one pulse of previous");
    poll(true);
    CHECK(none_down(), "and only one");
    g_total += 119;
    poll(true);
    CHECK(none_down(), "+119: nothing");
    g_total += 1;
    poll(true);
    CHECK(only(BIND_PREVIOUS), "+1 more: the notch that was waiting");

    start(map);
    g_total -= 130;
    poll(true);
    CHECK(only(BIND_NEXT), "-130: one notch down, the ten left over wait (toward zero)");
    g_total -= 110;
    poll(true);
    CHECK(only(BIND_NEXT), "-110 more: the remainder joins it for the second notch");
    poll(true);
    CHECK(none_down(), "and no third");
}

static void test_wheel_pending_cap(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    start(map);
    turn(1000);
    CHECK(pulses(BIND_PREVIOUS, 1000) == BIND_WHEEL_PENDING_MAX, "a thousand notches queue BIND_WHEEL_PENDING_MAX pulses");
    poll(true);
    CHECK(none_down(), "and then it is over");
}

static void test_wheel_shared_by_actions(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    map[BIND_SLOT1] = wheel_down();
    start(map);
    turn(-1);
    poll(true);
    CHECK(g_levels[BIND_NEXT] && g_levels[BIND_SLOT1] && !g_levels[BIND_PREVIOUS],
          "two actions on wheel_down both get the notch");
    poll(true);
    CHECK(none_down(), "and it is one notch");
}

static void test_wheel_baseline(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    reset_fake();
    g_total = 12345 * 120;
    bind_init(&g_port, map);
    poll(true);
    CHECK(none_down(), "notches turned before bind_init are not pulses");
    turn(1);
    poll(true);
    CHECK(only(BIND_PREVIOUS), "the first notch after it is");

    reset_fake();
    g_wheel_ok = false;
    g_total = 77 * 120;
    bind_init(&g_port, map);
    poll(true);
    g_wheel_ok = true;
    poll(true);
    CHECK(none_down(), "a total that could not be read at bind_init is the baseline at the first poll that reads it");
    turn(-1);
    poll(true);
    CHECK(only(BIND_NEXT), "and the notch after that counts");
}

static void test_blocked_drops_notches(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    start(map);
    turn(-3);
    poll(false);
    CHECK(none_down(), "allowed false: false though the wheel turned");
    CHECK(pulses(BIND_NEXT, 10) == 0, "and the notches turned while blocked are gone once it is allowed again");

    turn(-1);
    poll(true);
    CHECK(only(BIND_NEXT), "a notch after unblocking counts");

    turn(-4);
    poll(true);
    CHECK(only(BIND_NEXT), "four notches: first pulse");
    poll(false);
    CHECK(none_down(), "blocked with pulses pending: false");
    CHECK(pulses(BIND_NEXT, 10) == 0, "and the pending pulses were dropped");

    start(map);
    g_total = 5 * 120 + 50; /* with a part of a notch */
    poll(false);
    g_total += 70;
    poll(true);
    CHECK(none_down(), "a part of a notch carried through a blocked poll is dropped with it (the baseline moved to the total)");
    g_total += 120;
    poll(true);
    CHECK(only(BIND_PREVIOUS), "and the next whole notch counts");
}

static void test_blocked_clears_everything(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    map[BIND_SLOT1] = key(0x31);
    map[BIND_SLOT2] = pad(BIND_PAD_A);
    start(map);
    g_keys[0x31] = true;
    g_keys[0x01] = true;
    g_pad = BIND_PAD_A;
    poll(true);
    CHECK(g_levels[BIND_SLOT1] && g_levels[BIND_SLOT2] && g_levels[BIND_CONFIRM], "key, mouse and pad held: three levels");
    poll(false);
    CHECK(none_down(), "allowed false: every level is false with the inputs still held");
    g_front = false;
    poll(true);
    CHECK(none_down(), "the game window not in front: every level is false");
    CHECK(g_status[0] == '\0', "and nothing is said about it");
    g_front = true;
    poll(true);
    CHECK(none_down(), "back in front with the inputs still held: still false (they were held while nothing could fire)");
    poll(true);
    CHECK(none_down(), "and false for as long as they stay held");
    g_keys[0x31] = false;
    g_keys[0x01] = false;
    g_pad = 0;
    poll(true);
    CHECK(none_down(), "released: false");
    g_keys[0x31] = true;
    g_keys[0x01] = true;
    g_pad = BIND_PAD_A;
    poll(true);
    CHECK(g_levels[BIND_SLOT1] && g_levels[BIND_SLOT2] && g_levels[BIND_CONFIRM],
          "pressed again: true (levels once they have been seen up)");

    int keys_before = g_key_calls, pads_before = g_pad_calls;
    poll(false);
    CHECK(g_key_calls == keys_before && g_pad_calls == pads_before, "blocked: the keyboard and the controller are not read");
}

static void test_foreground_drops_notches(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    start(map);
    g_front = false;
    turn(-3);
    poll(true);
    g_front = true;
    CHECK(pulses(BIND_NEXT, 10) == 0, "notches turned while the game is not in front are dropped");
    turn(-1);
    poll(true);
    CHECK(only(BIND_NEXT), "and the next one counts");

    Binding quiet[BIND_COUNT];
    default_map(quiet);
    BindPort no_front = g_port;
    no_front.foreground = NULL;
    reset_fake();
    bind_init(&no_front, quiet);
    g_keys[0x01] = true;
    poll(true);
    CHECK(none_down(), "a port without foreground counts as not in front: nothing fires");
}

static void test_release_after_block(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    start(map);
    g_keys[0x01] = true;
    poll(true);
    CHECK(only(BIND_CONFIRM), "confirm held with the inputs allowed: true");
    poll(false);
    CHECK(none_down(), "blocked: false");
    poll(true);
    CHECK(none_down(), "allowed again with confirm still held: false (it was held while blocked)");
    poll(true);
    CHECK(none_down(), "and for as long as it stays held");
    g_keys[0x01] = false;
    poll(true);
    CHECK(none_down(), "released: false");
    g_keys[0x01] = true;
    poll(true);
    CHECK(only(BIND_CONFIRM), "pressed again: true at once");
    poll(true);
    CHECK(only(BIND_CONFIRM), "and a level while it stays held");

    /* A key that is not held when the block ends works as soon as it is pressed. */
    start(map);
    poll(false);
    poll(true);
    CHECK(none_down(), "blocked and then allowed with nothing held: false");
    g_keys[0x01] = true;
    poll(true);
    CHECK(only(BIND_CONFIRM), "confirm pressed after the block ended: true at once");

    /* The input is seen up on an allowed poll or not at all: letting go and pressing again while blocked is not seen. */
    start(map);
    g_keys[0x01] = true;
    poll(false);
    g_keys[0x01] = false;
    poll(false);
    g_keys[0x01] = true;
    poll(true);
    CHECK(none_down(), "released and pressed again while blocked: still false (never seen up while allowed)");
    g_keys[0x01] = false;
    poll(true);
    g_keys[0x01] = true;
    poll(true);
    CHECK(only(BIND_CONFIRM), "seen up while allowed, then pressed: true");

    /* The window not being in front blocks the same way. */
    start(map);
    g_keys[0x01] = true;
    g_front = false;
    poll(true);
    g_front = true;
    poll(true);
    CHECK(none_down(), "confirm held while the game was not in front: false when it comes back");
    g_keys[0x01] = false;
    poll(true);
    g_keys[0x01] = true;
    poll(true);
    CHECK(only(BIND_CONFIRM), "and it works once it has been released and pressed");
}

static void test_release_after_block_per_action(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    map[BIND_SLOT1] = key(0x31);
    map[BIND_SLOT2] = pad(BIND_PAD_A);
    map[BIND_SLOT3] = key(0x31); /* two actions on one key */
    start(map);
    g_keys[0x31] = true;
    g_pad = BIND_PAD_A;
    poll(false);
    g_pad = 0; /* the pad button is let go while blocked, the key is not */
    poll(true);
    CHECK(none_down(), "slot1 and slot3 (key held) wait; slot2's pad button is up and has been seen up");
    g_pad = BIND_PAD_A;
    poll(true);
    CHECK(only(BIND_SLOT2), "slot2 fires when pressed while slot1 and slot3 are still waiting for the key's release");
    g_keys[0x31] = false;
    poll(true);
    g_keys[0x31] = true;
    poll(true);
    CHECK(g_levels[BIND_SLOT1] && g_levels[BIND_SLOT2] && g_levels[BIND_SLOT3] && !g_levels[BIND_CONFIRM],
          "after the key's release both actions on it work");
}

static void test_first_poll_after_init(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    map[BIND_SLOT1] = key(0x31);
    map[BIND_SLOT2] = key('Q');
    start_cold(map);
    g_keys[0x31] = true;
    poll(true);
    CHECK(none_down(), "a key held at the first poll after bind_init: false");
    g_keys['Q'] = true;
    poll(true);
    CHECK(only(BIND_SLOT2), "another key, up at the first poll and pressed after: true at once");
    poll(true);
    CHECK(only(BIND_SLOT2), "slot1 is still waiting for its key to be let go");
    g_keys[0x31] = false;
    poll(true);
    g_keys[0x31] = true;
    poll(true);
    CHECK(g_levels[BIND_SLOT1] && g_levels[BIND_SLOT2], "and works after it was let go and pressed");

    /* A first poll that is blocked is not a look at the input: the rule starts at the first allowed poll. */
    start_cold(map);
    g_keys[0x31] = true;
    poll(false);
    g_keys[0x31] = false;
    poll(true);
    g_keys[0x31] = true;
    poll(true);
    CHECK(only(BIND_SLOT1), "up at the first allowed poll (after a blocked one), pressed after: true");

    /* The wheel has no held state: its first pulse counts at once. */
    start_cold(map);
    turn(-1);
    poll(true);
    CHECK(only(BIND_NEXT), "wheel: a notch at the first poll after bind_init is a pulse");
    start(map);
    poll(false);
    turn(1);
    poll(true);
    CHECK(only(BIND_PREVIOUS), "wheel: a notch turned after a blocked poll is a pulse on the first allowed poll");
}

static void test_no_wheel_api(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    map[BIND_SLOT1] = key(0x31);
    start(map);
    g_wheel_ok = false;
    turn(-3);
    g_keys[0x31] = true;
    poll(true);
    CHECK(g_levels[BIND_SLOT1] && !g_levels[BIND_NEXT] && !g_levels[BIND_PREVIOUS], "no wheel total: wheel levels stay false, keys work");
    CHECK(strcmp(g_status, "wheel bindings need Overlay Host 0.5.0") == 0, "and the status says the host is too old");
    CHECK(strcmp(g_status, BIND_STATUS_NEEDS_HOST) == 0, "(that is BIND_STATUS_NEEDS_HOST)");
    poll(false);
    CHECK(strcmp(g_status, BIND_STATUS_NEEDS_HOST) == 0, "the status is the same while nothing may fire");
    for (int i = 0; i < 5; i++) {
        poll(true);
        CHECK(!g_levels[BIND_NEXT] && !g_levels[BIND_PREVIOUS], "and the wheel levels stay false");
    }

    BindPort no_wheel = g_port;
    no_wheel.wheel_total = NULL;
    bind_init(&no_wheel, map);
    poll(true);
    CHECK(strcmp(g_status, BIND_STATUS_NEEDS_HOST) == 0, "a port without wheel_total says the same");

    Binding nowheel_map[BIND_COUNT];
    memset(nowheel_map, 0, sizeof nowheel_map);
    nowheel_map[BIND_SLOT1] = key(0x31);
    start(nowheel_map);
    g_wheel_ok = false;
    poll(true);
    CHECK(g_status[0] == '\0', "with no wheel binding the missing wheel total is not mentioned");

    start(map);
    poll(true);
    CHECK(g_status[0] == '\0', "the host's wheel total reads again: no status");
    g_wheel_ok = false;
    poll(true);
    g_wheel_ok = true;
    turn(-3);
    CHECK(pulses(BIND_NEXT, 10) == 0, "a total that was unavailable for a poll is a new baseline when it returns");
}

static void test_status_buffer(void)
{
    Binding map[BIND_COUNT];
    char small[8];
    default_map(map);
    start(map);
    g_wheel_ok = false;
    bind_poll(g_levels, true, small, sizeof small);
    CHECK(strcmp(small, "wheel b") == 0, "a short status buffer gets the text cut and terminated");
    bind_poll(g_levels, true, NULL, 0);
    CHECK(true, "a NULL status with size 0 is allowed");
    bind_poll(g_levels, true, small, 0);
    CHECK(true, "a status of size 0 is not written");
    bind_poll(g_levels, true, small, 1);
    CHECK(small[0] == '\0', "a status of size 1 is just the terminator");
}

static void test_bad_bindings(void)
{
    Binding map[BIND_COUNT];
    memset(map, 0, sizeof map);
    map[BIND_NEXT].kind = 77;
    map[BIND_PREVIOUS] = mouse(9);
    map[BIND_CONFIRM] = mouse(0);
    map[BIND_SLOT1] = key(0);
    map[BIND_SLOT2] = pad(0);
    map[BIND_SLOT3].kind = BIND_NONE;
    map[BIND_SLOT3].code = 0x31;
    start(map);
    memset(g_keys, 1, sizeof g_keys);
    g_pad = 0xffff;
    turn(-2);
    turn(2);
    poll(true);
    CHECK(none_down(), "bindings that cannot work (unknown kind, mouse 0 or 9, key 0, pad 0, none with a code) bind nothing");

    bind_init(&g_port, NULL);
    poll(true);
    CHECK(none_down(), "a NULL map binds nothing");
    bind_init(NULL, map);
    poll(true);
    CHECK(none_down(), "a NULL port reads nothing");
    default_map(map);
    bind_init(NULL, map);
    poll(true);
    CHECK(none_down(), "a NULL port with wheel bindings: nothing fires");
    CHECK(strcmp(g_status, BIND_STATUS_NEEDS_HOST) == 0, "and the missing wheel total is reported");
}

static void test_reinit(void)
{
    Binding map[BIND_COUNT];
    default_map(map);
    start(map);
    turn(-3);
    poll(true);
    CHECK(only(BIND_NEXT), "re-init: a pulse is pending");
    bind_init(&g_port, map);
    poll(true);
    CHECK(none_down(), "bind_init forgets pending pulses and takes a new baseline");
    memset(map, 0, sizeof map);
    map[BIND_SLOT4] = key('Z');
    bind_init(&g_port, map);
    g_keys['Z'] = false;
    g_keys[0x01] = false;
    poll(true);
    g_keys['Z'] = true;
    g_keys[0x01] = true;
    poll(true);
    CHECK(only(BIND_SLOT4), "and a new map replaces the old");

    bind_init(&g_port, map);
    poll(true);
    CHECK(none_down(), "a key held across bind_init does not fire (the first poll after bind_init only looks)");
}

int main(void)
{
    test_before_init();
    test_nothing_down();
    test_keys();
    test_mouse_buttons();
    test_pad();
    test_wheel_notches();
    test_wheel_one_pulse_per_poll();
    test_wheel_fractions();
    test_wheel_pending_cap();
    test_wheel_shared_by_actions();
    test_wheel_baseline();
    test_blocked_drops_notches();
    test_blocked_clears_everything();
    test_foreground_drops_notches();
    test_release_after_block();
    test_release_after_block_per_action();
    test_first_poll_after_init();
    test_no_wheel_api();
    test_status_buffer();
    test_bad_bindings();
    test_reinit();
    printf("%s\n", test_failures() == 0 ? "PASS test_bindings" : "FAIL test_bindings");
    TEST_MAIN_END
}
