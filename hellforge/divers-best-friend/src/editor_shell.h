#ifndef DBF_EDITOR_SHELL_H
#define DBF_EDITOR_SHELL_H
#include "goose_overlay.h"
#include "snapshot.h"

bool editor_shell_available(const OvApi* ov);
void editor_shell_draw(const OvApi* ov, const DbfSnapshot* s, const OvFrame* frame, OvPanel* panel);
#endif
