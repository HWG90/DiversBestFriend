#ifndef DBF_HUD_PREFS_H
#define DBF_HUD_PREFS_H

#include <stddef.h>
#include "settings.h"

/* Game-thread persistence after UI event validation. path is the same settings.ini used
 * at startup. Only descriptor-owned [hud] keys come from settings. Files or results
 * beyond the startup reader's 64 KiB limit are refused. On false, discard the UI edit. */
bool hud_prefs_save(const wchar_t* path, const DbfSettings* settings);

#endif
