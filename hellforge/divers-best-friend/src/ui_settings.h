/* ui_settings: the settings window's contents, drawn through the Goose Overlay Host's C API (goose_overlay.h).
 *
 * ui_settings_draw is called from the host's draw callback (the render thread), with the snapshot snap_acquire gave this
 * frame (NULL before the first publish). It reads only the snapshot and calls only the OvApi functions below, so it
 * never touches the game. This plan has one tab, Status; later plans add tabs beside it.
 *
 * Status tab, in order (plain English, for players; the arrows are ASCII because the host loads only ImGui's default
 * glyph range):
 *   Game build 25480438: OK                    or   Game build: <why not>
 *   <feature>: OK | Waiting (<reason>) | Off (<reason>)       one line per feature, by adm_feature_name; Waiting is
 *                                                             pending, Off is refused
 *   Overlay Host API <n>
 *   In a mission: yes | no (<reason>)          a mission is in_gameplay and hud_ready
 *   Stratagem menu: open | closed
 *   Reader: <why part of the game's data was not read>         in a mission only, when game.reason is not empty (outside
 *                                                              a mission the reason is in the line above)
 *   Codes do not follow scrambling yet         in a mission while scramble_known is false
 *   a table of the stratagems, in a mission: name, code as "^ > v <" (1 up, 2 right, 3 down, 4 left, "?" for any other
 *     value) or "no code"
 * and, when the snapshot's list view was filled (snap_fill_list; the three lines are drawn in or out of a mission, behind
 * a rule that follows the scramble note and comes before the table):
 *   Bindings: <next> / <previous> / <confirm>   each as settings.ini spells it, "none" when unbound
 *   <the bindings status>                       bind_poll's text, only when it has one
 *   Settings: <file> (<n> problems)             the file's name (no path), "defaults" when no file was read; "1 problem"
 *   Entry: idle | entering <name> (<sent>/<len>) | done | failed: <reason>      (failed: with no reason is just failed)
 * The OvApi functions it calls: text, separator, begin_tab_bar, end_tab_bar, begin_tab_item, end_tab_item, begin_table,
 * table_setup_column, table_headers_row, table_next_row, table_next_column, end_table.
 *
 * Portable C11: standard headers, goose_overlay.h, snapshot.h and text.h (the line builder, the names and the arrows, which
 * the snapshot and the plain list share) only. */
#ifndef DBF_UI_SETTINGS_H
#define DBF_UI_SETTINGS_H

#include <stddef.h>
#include <stdint.h>
#include "goose_overlay.h"
#include "snapshot.h"

/* NULL ov: nothing is drawn. */
void ui_settings_draw(const OvApi* ov, const DbfSnapshot* s);

#endif
