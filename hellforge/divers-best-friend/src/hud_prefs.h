#ifndef DBF_HUD_PREFS_H
#define DBF_HUD_PREFS_H

#include <stddef.h>
#include "settings.h"

/* Game-thread persistence after UI event validation. path is the same settings.ini used
 * at startup. Updates the HUD descriptors in an existing file, or writes full defaults and preferences for a new file. Files or results
 * beyond the startup reader's 64 KiB limit are refused. On false, discard the UI edit. */
bool hud_prefs_save(const wchar_t* path, const DbfSettings* settings);

/* Merge changed UI values into the latest file, preserving unrelated edits. */
bool hud_prefs_apply(const wchar_t* path, const DbfSettings* old, const DbfSettings* updated);
/* Import the entire configuration only if no settings.ini exists. */
bool hud_prefs_create(const wchar_t* path, const DbfSettings* settings);
#endif
