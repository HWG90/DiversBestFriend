/* settings: DBF's options and key bindings, read from the settings file's text.
 *
 * The parser reads four INI sections. File I/O belongs to the game thread.
 *
 *   [dbf]        enabled, selection_sounds, randomize_input_delay, instant_stratagems, hide_sos, hide_eagle_rearm
 *                (true or false, also 1 or 0) and input_interval_ms (whole milliseconds, 0 to 250; 0 sends one direction
 *                per frame)
 *   [hud]        R50 HUD preferences (hud_options.h), including the weapon status strip. Valid [hud] entries
 *                override legacy [dbf] entries for the same preference in any section order.
 *   [bindings]   next, previous, confirm, slot1, slot2, slot3, slot4, each one of
 *                  none | wheel_up | wheel_down | mouse1 .. mouse5 | key:0xNN (a virtual-key code in hex) |
 *                  key:<letter or digit> | key:f1 .. key:f24 |
 *                  pad:<a b x y lb rb back start ls rs dpad_up dpad_down dpad_left dpad_right>
 *   [blacklist]  kind_<id> = true | false for each id in dbf_blacklist_kinds (the stratagems a player may hide)
 *
 * One setting per line as `key = value`; blank lines are skipped, and so are lines whose first character after the spaces is
 * ; or # (a comment line). A value or a section header may end in a comment too: from the first ; or # that follows a
 * space or a tab ("enabled = false ; off" is false; a ; or # with no space before it is part of the text). Spaces and tabs
 * around names and values are trimmed, section names, keys and values are not case sensitive, a UTF-8 byte order mark at
 * the start is skipped, and a later line for the same key wins.
 *
 * Parsing never fails the file. A line that is not understood is listed in `problems` ("line N: ..."), skipped, and the
 * lines after it are read as usual: unknown sections (their keys are skipped without a line each), unknown keys, a key with
 * no section, a line with no `=`, a value that is not valid for its key. A value that is not valid leaves its setting as an
 * earlier line or the default had it; for input_interval_ms (a whole number from 0 to 250) the problem says which value is
 * kept.
 *
 * Legacy defaults: enabled and selection_sounds true; input_interval_ms 70; randomize_input_delay, instant_stratagems,
 * hide_sos and hide_eagle_rearm false; every blacklist kind at the default_on of dbf_blacklist_kinds; next = wheel_down,
 * previous = wheel_up, confirm = mouse1, the slot hotkeys unbound.
 *
 * bind_describe is the other way round: a Binding written as the file spells it, so the Status tab shows what to type.
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
    int selection_mode_ordered;
    int experimental_layout;
    int appearance_preset;
    int wheel_size;
    int icon_size;
    int label_size;
    int native_opacity;
    int wedge_darkness;
    int wedge_opacity;
    bool cooldown_timers;
    int cooldown_timer;
    int short_timer_style;
    bool dim_unselected;
    bool hide_blacklisted_list;
    bool hide_cooldown_list;
    int brief_timer_limit;
    bool hide_closed_status;
    int dock_gap;
    bool cooldown_icons;
    int cooldown_display;
    int short_status_placement;
    bool track_unavailable;
    bool balance_separated_dock;
    int release_selection_mode;
    int vertical_offset;
    bool weapon_status_strip;
} DbfSettings;

/* Every field at its default (see above). */
void settings_defaults(DbfSettings* s);

/* Fills *s from `len` bytes of text, which need not end in a NUL: it starts from settings_defaults, then applies the lines.
 * Returns how many lines were not understood. `problems` (n bytes; NULL or 0 allowed) gets one "line N: ..." per problem,
 * separated by '\n' with none after the last; it is always terminated, and a problem that does not fit is left out whole
 * (the return value still counts it). */
int settings_parse(DbfSettings* s, const char* text, size_t len, char* problems, size_t n);

/* Writes `b` into out[n] as a [bindings] value: none, wheel_up, wheel_down, mouse1 .. mouse5, key:a .. key:z, key:0 ..
 * key:9, key:f1 .. key:f24, key:0xNN (any other code, two upper case hex digits) or pad:<button>, so that settings_parse of
 * that text gives the binding back. A binding that cannot work (an unknown kind, a mouse code outside 1 to 5, a key code
 * outside 1 to 0xFE, a pad mask that is not exactly one named button: bind_init takes these as BIND_NONE too) and a NULL
 * `b` read none. The text is cut to fit n and always terminated; a NULL `out` or n of 0 does nothing. A wheel binding's
 * code is not looked at. */
void bind_describe(const Binding* b, char* out, size_t n);

#endif
