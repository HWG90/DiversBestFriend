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
 *   Codes do not follow scrambling yet         in a mission while scramble_known is false
 *   a table of the stratagems, in a mission: name, code as "^ > v <" (1 up, 2 right, 3 down, 4 left, "?" for any other
 *     value) or "no code"
 * The OvApi functions it calls: text, separator, begin_tab_bar, end_tab_bar, begin_tab_item, end_tab_item, begin_table,
 * table_setup_column, table_headers_row, table_next_row, table_next_column, end_table.
 *
 * Portable C11: standard headers, goose_overlay.h, snapshot.h and the generated kind names only. */
#ifndef DBF_UI_SETTINGS_H
#define DBF_UI_SETTINGS_H

#include <stdint.h>
#include "goose_overlay.h"
#include "snapshot.h"

/* NULL ov: nothing is drawn. */
void ui_settings_draw(const OvApi* ov, const DbfSnapshot* s);

/* The stratagem's name: its entry in dbf_kind_names for vanilla kinds (below 150) that have one, else "Stratagem <kind>"
 * (HellForge mods' kinds start at 150; Plan 3 gives those their own titles). The "Stratagem <kind>" text lives in a
 * static buffer that the next call overwrites: use it before calling again. Render thread only. */
const char* dbf_kind_name(uint32_t kind);

#endif
