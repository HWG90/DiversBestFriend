/* settings: DBF's options and key bindings, read from the settings file's text.
 *
 * The file is an INI file with three sections. This unit only turns text into a DbfSettings (reading the file from disk is
 * dbf.c's job; writing it comes with the Controls tab):
 *
 *   [dbf]        enabled, selection_sounds, randomize_input_delay, instant_stratagems, hide_sos, hide_eagle_rearm
 *                (true or false, also 1 or 0) and input_interval_ms (whole milliseconds, 0 to 250; 0 sends one direction
 *                per frame)
 *   [bindings]   next, previous, confirm, slot1, slot2, slot3, slot4, each one of
 *                  none | wheel_up | wheel_down | mouse1 .. mouse5 | key:0xNN (a virtual-key code in hex) |
 *                  key:<letter or digit> | key:f1 .. key:f24 |
 *                  pad:<a b x y lb rb back start ls rs dpad_up dpad_down dpad_left dpad_right>
 *   [blacklist]  kind_<id> = true | false for each id in dbf_blacklist_kinds (the stratagems a player may hide)
 *
 * One setting per line as `key = value`; blank lines are skipped, and so are lines whose first character after the spaces is
 * ; or # (comments are whole lines). Spaces and tabs around names and values are trimmed, section names, keys and values
 * are not case sensitive, a UTF-8 byte order mark at the start is skipped, and a later line for the same key wins.
 *
 * Parsing never fails the file. A line that is not understood is listed in `problems` ("line N: ..."), skipped, and the
 * lines after it are read as usual: unknown sections (their keys are skipped without a line each), unknown keys, a key with
 * no section, a line with no `=`, a value that is not valid for its key. An input_interval_ms that is not a whole number
 * from 0 to 250 is listed and becomes the default (70).
 *
 * Defaults are R46's: enabled and selection_sounds true; input_interval_ms 70; randomize_input_delay, instant_stratagems,
 * hide_sos and hide_eagle_rearm false; every blacklist kind at the default_on of dbf_blacklist_kinds; next = wheel_down,
 * previous = wheel_up, confirm = mouse1, the slot hotkeys unbound.
 *
 * Portable C11: standard headers, bindings.h and the generated address header (only its extern declaration of
 * dbf_blacklist_kinds: admission.c holds the one definition). No printf: the problem lines are built by hand. */
#ifndef DBF_SETTINGS_H
#define DBF_SETTINGS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bindings.h"

#define DBF_BLACKLIST_SLOTS 200 /* blacklist_kind[] is indexed by the stratagem kind; a kind of 200 or more cannot be kept */
#define DBF_INTERVAL_DEFAULT_MS 70
#define DBF_INTERVAL_MAX_MS 250

typedef struct DbfSettings {
    bool enabled, selection_sounds, randomize_input_delay, instant_stratagems, hide_sos, hide_eagle_rearm;
    int input_interval_ms;                   /* 0..250 */
    bool blacklist_kind[DBF_BLACKLIST_SLOTS]; /* by kind; true: hidden */
    Binding bind[BIND_COUNT];
} DbfSettings;

/* Every field at its default (see above). */
void settings_defaults(DbfSettings* s);

/* Fills *s from `len` bytes of text, which need not end in a NUL: it starts from settings_defaults, then applies the lines.
 * Returns how many lines were not understood. `problems` (n bytes; NULL or 0 allowed) gets one "line N: ..." per problem,
 * separated by '\n' with none after the last; it is always terminated, and a problem that does not fit is left out whole
 * (the return value still counts it). */
int settings_parse(DbfSettings* s, const char* text, size_t len, char* problems, size_t n);

#endif
