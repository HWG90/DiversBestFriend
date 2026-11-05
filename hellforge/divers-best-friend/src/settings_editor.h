#ifndef DBF_SETTINGS_EDITOR_H
#define DBF_SETTINGS_EDITOR_H

#include "goose_overlay.h"
#include "snapshot.h"

/* Render thread owns the draft. Only Apply posts an event. */
/* Content only: false for Controls, true for Blacklist. Pass NULL for s when
 * navigating away from both pages to stop capture without discarding drafts. */
void editor_page(const OvApi* ov, const DbfSnapshot* s, bool blacklist_page);
/* Legacy navigation inside the caller's tab bar. */
void editor_tabs(const OvApi* ov, const DbfSnapshot* s);
/* Game thread validates the entire event before updating its candidate settings. */
bool editor_apply(DbfSettings* s, const UiEvent* e);
#endif
