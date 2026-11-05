#ifndef DBF_EDITOR_ICONS_H
#define DBF_EDITOR_ICONS_H

#include "goose_overlay.h"

/* Render-thread only. x/y are the top-left screen coordinates, size is the
 * square's side in pixels. Draws on the current layer without moving the cursor.
 * Case-insensitive section names: Logo, Browse, Changes, Controls, Blacklist,
 * Status. Unknown names draw nothing. Tab ink uses the current text theme. */
void editor_icon(const OvApi* ov, const char* section, float x, float y, float size);

#endif
