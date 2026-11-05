#ifndef DBF_EDITOR_BROWSE_H
#define DBF_EDITOR_BROWSE_H
#include "goose_overlay.h"
#include "snapshot.h"

/* Render thread only. A queued change remains staged until published by the game. */
bool editor_browse_available(const OvApi* ov);
void editor_browse(const OvApi* ov, const DbfSnapshot* s, bool focus_search);
bool editor_browse_escape(void); /* consumes Escape when clearing search */
void editor_changes(const OvApi* ov, const DbfSnapshot* s);
bool editor_apply_changes(const OvApi* ov, const DbfSnapshot* s);
int editor_change_count(const DbfSnapshot* s);
void editor_discard_changes(void);
void editor_reset_defaults(const DbfSnapshot* s);
#endif
