#ifndef DBF_EDITOR_BROWSE_H
#define DBF_EDITOR_BROWSE_H
#include "goose_overlay.h"
#include "snapshot.h"

/* Render thread only. A queued change remains staged until published by the game. */
bool editor_browse_available(const OvApi* ov);
/* Tab belongs to the shell. Browse uses arrows within the chosen navigation pane. */
void editor_browse(const OvApi* ov, const DbfSnapshot* s, bool focus_search);
/* Shell-provided panel focus gates keyboard navigation; legacy entry retains fallback. */
void editor_browse_focused(const OvApi* ov, const DbfSnapshot* s, bool focus_search, bool focused);
bool editor_browse_escape(void); /* consumes Escape when clearing search */
void editor_changes(const OvApi* ov, const DbfSnapshot* s);
bool editor_apply_changes(const OvApi* ov, const DbfSnapshot* s);
int editor_change_count(const DbfSnapshot* s);
void editor_discard_changes(void);
void editor_reset_defaults(const DbfSnapshot* s);
#endif
