/* ui_list: the plain list, a Goose Overlay Host HUD panel (OV_PANEL_HUD, id goose.divers-best-friend/list) that shows the
 * stratagem list DBF chooses from while the stratagem menu is open. Plan 3 replaces it with the real List Select.
 *
 * ui_list_draw is called from the host's draw callback (the render thread) with the frame, and the snapshot snap_acquire
 * gave this frame (NULL before the first publish). It reads only the snapshot (DbfSnapshot.list, filled by snap_fill_list)
 * and calls only OvApi's draw_rect_filled, draw_text, text_size and theme, so it never touches the game or any widget.
 *
 * It draws nothing unless: the snapshot's list view was filled, DBF is enabled, a mission is on (in_gameplay and
 * hud_ready), the stratagem menu is open and the list has at least one row.
 *
 * What it draws, in screen pixels scaled by OvFrame.scale (a scale that is not a positive number counts as 1):
 *   - a plate in the left third of the screen, centred up and down, in theme(OV_THEME_PANEL) with corners of 6 px
 *     (DESIGN.md hud_plate_rounding);
 *   - one line per row in list order, in columns that line up: the name, the code as "^ > v <" (or "no code") and the
 *     timer ("<n>s" for an incoming or cooldown timer, "unavailable"; nothing when no timer runs);
 *   - colours, all from theme(): OV_THEME_TEXT; the chosen row OV_THEME_ACCENT, with a 3 px accent bar (DESIGN.md
 *     selected_bar) at the left edge of its line; a row that cannot be chosen OV_THEME_TEXT_OFF, or OV_THEME_TEXT_DIM
 *     when the host answers 0xFFFFFFFF for it (hosts before 0.4.0, which have no text_off);
 *   - while the code entry runs (ListView.entry_state), the directions it has sent so far in the row of its stratagem
 *     (the first row with that kind) are drawn in the accent, the rest in the row's own colour; on the chosen row, whose
 *     own colour is the accent already, the rest is OV_THEME_TEXT, so the progress shows.
 * There is no text shadow: the host has no hud_shadow token and a colour is never a literal. The arrows are ASCII because
 * the host loads only ImGui's default glyph range.
 *
 * Portable C11: standard headers, goose_overlay.h, snapshot.h and ui_settings.h (dbf_code_arrows) only. No printf. */
#ifndef DBF_UI_LIST_H
#define DBF_UI_LIST_H

#include "goose_overlay.h"
#include "snapshot.h"

/* NULL ov, frame or snapshot, or an ov missing one of the four calls: nothing is drawn. */
void ui_list_draw(const OvApi* ov, const OvFrame* f, const DbfSnapshot* s);

#endif
