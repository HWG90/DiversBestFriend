/* native: the game functions DBF calls, behind a port.
 *
 * Until Plan 2 DBF only read game memory. These six wrappers are the only way the mod runs game code (no other unit
 * calls a game function, and later units must go through them): the input handler, opening and closing the code-entry
 * input, requesting a weapon slot, the UI sound, and the scramble-effect query. R46 cast the same addresses with
 * ffi.cast (native.lua:298-345).
 *
 * The functions are reached through a NativePort of plain function pointers, so the units that call them are tested with
 * fakes. The real port is built by dbf.c from the game.dll base and the generated header's DBF_FN_* RVAs; this unit
 * never builds it and includes no platform and no SDK header (portable C11, like memory.h and admission.h). It needs the
 * game.dll base for the audio and effects globals it reads: native_set_base gives it (native_init does not take it, so
 * the port can be installed before game.dll is known; until the base is set the two wrappers that read a global,
 * nat_ui_sound and nat_scramble_query, do nothing).
 *
 * Every wrapper has the same shape:
 *   1. If the port's function is NULL (a partial port, as tests build), or the feature that gates the call is not
 *      ADMIT_OK (adm_feature), it returns false, calls nothing and logs nothing. The features: the input handler ENTRY,
 *      open_input / close_input / request_slot LATCH, ui_sound SOUND, scramble_query SCRAMBLE.
 *   2. Otherwise it logs one checkpoint line through the port's `log` (when that is not NULL), then makes the call, then
 *      returns true. The checkpoint comes first so that, if the game crashes inside the call, the last line of the log
 *      names the step that was running. The user-triggered calls (input handler, open, close, request slot) log every
 *      call. The per-tick calls (ui_sound on selection moves, scramble_query for every row each tick) log their first call
 *      of the session, then at most once per 1000 ms each by the port's now_ms clock (NULL: every call logs), and also
 *      whenever the last line native logged was not that function's own checkpoint (another function's checkpoint, or
 *      one of the lines below). So the last line native logged always names the call in progress, even when calls
 *      interleave (scramble queries around an input handler call); for a per-tick call it may be the checkpoint of an
 *      earlier call of the same function, with other arguments. Lines that other units log (admission, codes) go
 *      through their own ports, which native does not see. The line is "call <name>(<arguments>)", every argument as
 *      0x followed by lowercase hex digits without leading zeros (0 is "0x0"), separated by ", ". For example:
 *          call request_slot(0x2c0000100, 0x5)
 *      The arguments logged are the ones the caller chose, plus the effects pointer the scramble wrapper reads itself:
 *      input_handler(component), open_input(component), close_input(component), request_slot(weapon, slot), ui_sound(id),
 *      scramble_query(effects, key, kind). The constant arguments (ui_sound's unused 0, scramble_query's two null outputs)
 *      and scramble_query's out buffer are not logged. The line is built without printf-family functions (the DLL's
 *      imports stay KERNEL32 and the C runtime it already uses).
 * A pointer argument that is the wrapper's output (nat_open_input's `result`, nat_scramble_query's `out`) must not be
 * NULL: a NULL one is refused like a missing feature (false, nothing called, nothing logged).
 *
 * nat_ui_sound also checks the audio preconditions R46's ui_sound checked (native.lua:325-332), through mem_ptr: the
 * audio engine global (game.dll + DBF_RVA_AUDIO), the game state global (game.dll + DBF_RVA_GAME_STATE), and the three
 * pointers *(engine + DBF_OFF_AUDIO_CALL_OFFSET), *(engine + DBF_OFF_AUDIO_TAIL_CALL_OFFSET) and
 * *(game + DBF_OFF_GAME_AUDIO_OFFSET) must all be readable, plausible, 8-aligned pointers. When one is not, nothing is
 * called and the port's log gets "sound skipped: <which pointer>" (for example "sound skipped: audio call pointer
 * (engine+0x288)"), at most once per session (since native_init): the sound is asked for on every selection move, so
 * only the first gap is worth a line. Before native_set_base it is not called either, and the log gets "native: game.dll
 * base not set", once a session, a line of its own (it does not use up the "sound skipped" line). A sound that the
 * feature does not admit logs nothing, not even these.
 *
 * nat_scramble_query reads the effects pointer from game.dll + DBF_RVA_EFFECTS through mem_ptr (R46 input.lua:153); when
 * there is no base or that fails nothing is called, *out is left alone, and the log gets "scramble query skipped: no
 * base" or "scramble query skipped: no effects pointer", one of them once a session (since native_init). Otherwise *out
 * is set to 0xffffffff before the call ("no effect" in R46's reading, input.lua:156) and the game is asked with
 * (effects, out, key, kind, 0, 0), the two optional outputs null (native.lua:333-338); what the game wrote to *out is
 * the answer. The function's own return value is not used. A query that the feature does not admit logs nothing.
 *
 * Not thread-safe by design: only the game thread calls it. */
#ifndef DBF_NATIVE_H
#define DBF_NATIVE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct NativePort {
    void (*input_handler)(uintptr_t component);
    uint8_t (*open_input)(uintptr_t component);
    void (*close_input)(uintptr_t component);
    void (*request_slot)(uintptr_t weapon, uint32_t slot);
    void (*ui_sound)(uintptr_t unused, uint32_t id);
    uintptr_t (*scramble_query)(uintptr_t effects, uint32_t* out, uint32_t key, uint32_t kind, uintptr_t a5, uintptr_t a6);
    void (*log)(const char* line); /* the checkpoint before each call; takes one line, without a line end */
    /* Optional: a monotonic millisecond clock (GetTickCount64 in the DLL). NULL: every call logs its checkpoint. Added
     * last, so an initialiser that stops at `log` stays valid. */
    uint64_t (*now_ms)(void);
} NativePort;

/* Starts a session: copies the port (NULL leaves no port, so every wrapper returns false), forgets the game.dll base (see
 * native_set_base), re-arms the once-per-session lines ("sound skipped", "native: game.dll base not set", "scramble
 * query skipped") and the per-tick calls' first checkpoints. */
void native_init(const NativePort* port);

/* The base address of game.dll, where the audio and effects globals are read from. Call it after native_init (which
 * clears it). 0 means unknown. */
void native_set_base(uintptr_t game_dll);

/* false: the function is missing from the port or its feature is not admitted; nothing was called. */
bool nat_input_handler(uintptr_t component);
/* Stores open_input's returned byte in *result. */
bool nat_open_input(uintptr_t component, uint8_t* result);
bool nat_close_input(uintptr_t component);
bool nat_request_slot(uintptr_t weapon, uint32_t slot);
/* Checks the audio preconditions first (see the top). */
bool nat_ui_sound(uint32_t id);
/* effects = [game.dll + DBF_RVA_EFFECTS]; *out starts 0xffffffff. */
bool nat_scramble_query(uint32_t key, uint32_t kind, uint32_t* out);

#endif
