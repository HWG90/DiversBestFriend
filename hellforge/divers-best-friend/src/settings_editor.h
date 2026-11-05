#ifndef DBF_SETTINGS_EDITOR_H
#define DBF_SETTINGS_EDITOR_H

#include "goose_overlay.h"
#include "snapshot.h"

/* Render thread owns the draft. Only Apply posts an event. */
void editor_tabs(const OvApi* ov, const DbfSnapshot* s);
/* Game thread validates the entire event before updating its candidate settings. */
bool editor_apply(DbfSettings* s, const UiEvent* e);
#endif
