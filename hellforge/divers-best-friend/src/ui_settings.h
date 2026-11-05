/* Overlay Host draw callback. Reads the published snapshot only. The Status tab reports the
 * game and HUD diagnostics. Settings controls queue UI_HUD_OPTION edits for the game thread. */
#ifndef DBF_UI_SETTINGS_H
#define DBF_UI_SETTINGS_H

#include <stddef.h>
#include <stdint.h>
#include "goose_overlay.h"
#include "snapshot.h"

/* NULL ov: nothing is drawn. */
void ui_settings_draw(const OvApi* ov, const DbfSnapshot* s);

#endif
