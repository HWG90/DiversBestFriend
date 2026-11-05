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
 * Portable C11: standard headers, goose_overlay.h, snapshot.h and the generated kind names only. The two text helpers at the
 * end are shared with the snapshot (names) and the plain list (codes). */
#ifndef DBF_UI_SETTINGS_H
#define DBF_UI_SETTINGS_H

#include <stddef.h>
#include <stdint.h>
#include "goose_overlay.h"
#include "snapshot.h"

/* NULL ov: nothing is drawn. */
void ui_settings_draw(const OvApi* ov, const DbfSnapshot* s);

/* The stratagem's name: its entry in dbf_kind_names for vanilla kinds (below 150) that have one, else "Stratagem <kind>"
 * (HellForge mods' kinds start at 150; Plan 3 gives those their own titles). The "Stratagem <kind>" text lives in a
 * static buffer that the next call overwrites: use it before calling again. Render thread only. */
const char* dbf_kind_name(uint32_t kind);

/* The same name copied into dst[size] (terminated, cut to fit): no shared buffer, so any thread may call it. The game
 * thread names the list view's rows with it while the render thread uses dbf_kind_name. */
void dbf_kind_name_copy(uint32_t kind, char* dst, size_t size);

/* The first `n` directions of a code (limited to DBF_CODE_CAPACITY) as "^ > v <" into dst[size] (terminated, cut to fit): 1
 * up, 2 right, 3 down, 4 left, "?" for any other value; "" for none. Any thread. */
void dbf_code_arrows(const uint8_t* code, size_t n, char* dst, size_t size);

#endif
