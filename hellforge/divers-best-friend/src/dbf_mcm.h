#ifndef DBF_MCM_H
#define DBF_MCM_H
#include "goose_mcm.h"
#include "settings.h"

/* Game thread only. Call after processing local edits. current points to DBF's
 * session-lifetime settings, including between ticks while MCM calls its provider.
 * persist saves and publishes the candidate synchronously, returning false on failure.
 * Pass NULL for resolve in production to discover the optional goose_mcm.dll. */
void dbf_mcm_tick(const DbfSettings *current, bool (*persist)(const DbfSettings *),
                  const McmApi *(*resolve)(void));
bool dbf_mcm_registered(void);
bool dbf_mcm_open(void);
#endif
