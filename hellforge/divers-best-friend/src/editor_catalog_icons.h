#ifndef DBF_EDITOR_CATALOG_ICONS_H
#define DBF_EDITOR_CATALOG_ICONS_H
#include <stdbool.h>
#include "goose_overlay.h"

/* Render thread. Fit both installed Editor masks in a screen-space square on
 * the caller's current draw layer. Missing art returns false. No layout calls. */
bool editor_stratagem_icon(const OvApi* ov, const char* name, float x, float y, float size);
#endif
