/* native: the game functions behind a port (see native.h). Portable C11: standard headers, memory.h, admission.h and the
 * generated address header only. The RVAs and offsets are the generated header's DBF_RVA_* / DBF_OFF_* names, each from the
 * R46 line it names there (native.lua:298-345 for the casts, 325-332 for the sound's preconditions, input.lua:153 for the
 * effects pointer). The checkpoint line is built by hand (put_text, put_hex), without printf-family functions. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "memory.h"
#include "native.h"

#define NATIVE_LINE_MAX 160 /* not LINE_MAX: POSIX's <limits.h> has one */

/* The scramble query's "no effect" answer: R46 presets its result to this before asking (native.lua:333-338). */
#define SCRAMBLE_NO_ANSWER 0xffffffffu

/* DBF's own (Plan 2's Task 5 review), not R46's: a per-tick call (the scramble query, the UI sound) logs its checkpoint on
 * its first call of the session and then at most once per this many milliseconds. */
#define PER_TICK_LOG_MS 1000u

/* When a per-tick call last logged its checkpoint. */
typedef struct Throttle {
    bool logged;
    uint64_t at;
} Throttle;

static NativePort g_port;
static uintptr_t g_base; /* game.dll; 0 when not set */
static const char* g_last_checkpoint; /* the function the last line native logged names; NULL: that line was not a
                                         checkpoint (or nothing was logged yet) */
static bool g_sound_skip_logged, g_base_unset_logged, g_scramble_skip_logged;
static Throttle g_sound_throttle, g_scramble_throttle;

/* --- the checkpoint line --------------------------------------------------------------------------------------- */

/* Appends `text` at `at`, cut to leave room for the end of the line; returns the new length. */
static size_t put_text(char* line, size_t at, const char* text)
{
    while (*text && at < NATIVE_LINE_MAX - 1) line[at++] = *text++;
    return at;
}

/* Appends 0x and the lowercase hex digits of `value` without leading zeros (0 is "0x0"). */
static size_t put_hex(char* line, size_t at, uint64_t value)
{
    static const char DIGITS[] = "0123456789abcdef";
    char digits[16];
    size_t n = 0;
    at = put_text(line, at, "0x");
    do {
        digits[n++] = DIGITS[value & 15u];
        value >>= 4;
    } while (value != 0);
    while (n > 0 && at < NATIVE_LINE_MAX - 1) line[at++] = digits[--n];
    return at;
}

/* Logs one line; `checkpoint_of` is the function a checkpoint line names, NULL for any other line. */
static void log_line(const char* line, const char* checkpoint_of)
{
    if (!g_port.log) return;
    g_port.log(line);
    g_last_checkpoint = checkpoint_of;
}

/* "call <name>(<arg>, <arg>, ...)" through the port's log, before the call it announces. */
static void checkpoint(const char* name, const uint64_t* args, size_t count)
{
    char line[NATIVE_LINE_MAX];
    size_t at = put_text(line, 0, "call ");
    at = put_text(line, at, name);
    at = put_text(line, at, "(");
    for (size_t i = 0; i < count; i++) {
        if (i > 0) at = put_text(line, at, ", ");
        at = put_hex(line, at, args[i]);
    }
    at = put_text(line, at, ")");
    line[at] = '\0';
    log_line(line, name);
}

/* A per-tick call's checkpoint: logged when there is no clock, on the session's first call, when PER_TICK_LOG_MS have
 * passed since the last one it logged, and whenever the last line native logged was not this function's checkpoint
 * (another function's, or a skip line): then the last line names the call in progress even when calls interleave. */
static void throttled_checkpoint(Throttle* t, const char* name, const uint64_t* args, size_t count)
{
    if (g_port.now_ms) {
        uint64_t now = g_port.now_ms();
        bool last_is_mine = g_last_checkpoint && strcmp(g_last_checkpoint, name) == 0;
        if (t->logged && now - t->at < PER_TICK_LOG_MS && last_is_mine) return;
        t->logged = true;
        t->at = now;
    }
    checkpoint(name, args, count);
}

/* `line`, the first time of the session only (`*latch` says it was logged). */
static void log_once(bool* latch, const char* line)
{
    if (*latch) return;
    *latch = true;
    log_line(line, NULL);
}

static bool admitted(Feature f)
{
    return adm_feature(f, NULL) == ADMIT_OK;
}

/* --- session ---------------------------------------------------------------------------------------------------- */

void native_init(const NativePort* port)
{
    if (port)
        g_port = *port;
    else
        memset(&g_port, 0, sizeof g_port);
    g_base = 0;
    g_last_checkpoint = NULL;
    g_sound_skip_logged = g_base_unset_logged = g_scramble_skip_logged = false;
    memset(&g_sound_throttle, 0, sizeof g_sound_throttle);
    memset(&g_scramble_throttle, 0, sizeof g_scramble_throttle);
}

void native_set_base(uintptr_t game_dll)
{
    g_base = game_dll;
}

/* --- the wrappers ----------------------------------------------------------------------------------------------- */

bool nat_input_handler(uintptr_t component)
{
    uint64_t args[1];
    if (!g_port.input_handler || !admitted(FEAT_ENTRY)) return false;
    args[0] = component;
    checkpoint("input_handler", args, 1);
    g_port.input_handler(component);
    return true;
}

bool nat_open_input(uintptr_t component, uint8_t* result)
{
    uint64_t args[1];
    if (!g_port.open_input || !result || !admitted(FEAT_LATCH)) return false;
    args[0] = component;
    checkpoint("open_input", args, 1);
    *result = g_port.open_input(component);
    return true;
}

bool nat_close_input(uintptr_t component)
{
    uint64_t args[1];
    if (!g_port.close_input || !admitted(FEAT_LATCH)) return false;
    args[0] = component;
    checkpoint("close_input", args, 1);
    g_port.close_input(component);
    return true;
}

bool nat_request_slot(uintptr_t weapon, uint32_t slot)
{
    uint64_t args[2];
    if (!g_port.request_slot || !admitted(FEAT_LATCH)) return false;
    args[0] = weapon;
    args[1] = slot;
    checkpoint("request_slot", args, 2);
    g_port.request_slot(weapon, slot);
    return true;
}

/* "sound skipped: <label> (<from>+0x<offset>)", the first time of the session only. */
static void log_sound_skipped(const char* label, const char* from, uint64_t offset)
{
    char line[NATIVE_LINE_MAX];
    size_t at;
    if (g_sound_skip_logged) return;
    at = put_text(line, 0, "sound skipped: ");
    at = put_text(line, at, label);
    at = put_text(line, at, " (");
    at = put_text(line, at, from);
    at = put_text(line, at, "+");
    at = put_hex(line, at, offset);
    at = put_text(line, at, ")");
    line[at] = '\0';
    log_once(&g_sound_skip_logged, line);
}

/* R46's ui_sound preconditions (native.lua:325-332): the audio engine and the game state globals, then the three pointers
 * they lead to. False, after logging which one is missing, when any is not a plausible readable pointer. */
static bool audio_ready(void)
{
    uintptr_t engine, game, scratch;
    if (g_base == 0) { /* its own line: a missing base is not one of the audio pointers */
        log_once(&g_base_unset_logged, "native: game.dll base not set");
        return false;
    }
    if (!mem_ptr(g_base + DBF_RVA_AUDIO, &engine)) {
        log_sound_skipped("audio engine", "game.dll", DBF_RVA_AUDIO);
        return false;
    }
    if (!mem_ptr(g_base + DBF_RVA_GAME_STATE, &game)) {
        log_sound_skipped("game state", "game.dll", DBF_RVA_GAME_STATE);
        return false;
    }
    if (!mem_ptr(engine + DBF_OFF_AUDIO_CALL_OFFSET, &scratch)) {
        log_sound_skipped("audio call pointer", "engine", DBF_OFF_AUDIO_CALL_OFFSET);
        return false;
    }
    if (!mem_ptr(engine + DBF_OFF_AUDIO_TAIL_CALL_OFFSET, &scratch)) {
        log_sound_skipped("audio tail-call pointer", "engine", DBF_OFF_AUDIO_TAIL_CALL_OFFSET);
        return false;
    }
    if (!mem_ptr(game + DBF_OFF_GAME_AUDIO_OFFSET, &scratch)) {
        log_sound_skipped("game audio pointer", "game", DBF_OFF_GAME_AUDIO_OFFSET);
        return false;
    }
    return true;
}

bool nat_ui_sound(uint32_t id)
{
    uint64_t args[1];
    if (!g_port.ui_sound || !admitted(FEAT_SOUND) || !audio_ready()) return false;
    args[0] = id;
    throttled_checkpoint(&g_sound_throttle, "ui_sound", args, 1);
    g_port.ui_sound(0, id);
    return true;
}

bool nat_scramble_query(uint32_t key, uint32_t kind, uint32_t* out)
{
    uintptr_t effects;
    uint64_t args[3];
    if (!g_port.scramble_query || !out || !admitted(FEAT_SCRAMBLE)) return false;
    if (g_base == 0) {
        log_once(&g_scramble_skip_logged, "scramble query skipped: no base");
        return false;
    }
    if (!mem_ptr(g_base + DBF_RVA_EFFECTS, &effects)) {
        log_once(&g_scramble_skip_logged, "scramble query skipped: no effects pointer");
        return false;
    }
    *out = SCRAMBLE_NO_ANSWER;
    args[0] = effects;
    args[1] = key;
    args[2] = kind;
    throttled_checkpoint(&g_scramble_throttle, "scramble_query", args, 3);
    (void)g_port.scramble_query(effects, out, key, kind, 0, 0);
    return true;
}
