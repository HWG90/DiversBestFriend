#ifndef DBF_MCM_SCHEMA_H
#define DBF_MCM_SCHEMA_H

#include "goose_mcm.h"
#include "settings.h"

#define DBF_MCM_ID "divers_best_friend"
#define DBF_MCM_SCHEMA_CAP 32768
#define DBF_MCM_KEY_CAP 81
#define DBF_MCM_TEXT_CAP 49
#define DBF_MCM_CONDITION "hud_available"

/* Writes the v1 registration JSON and returns its byte length, or 0 on failure. */
size_t dbf_mcm_schema(char* out, size_t cap);
unsigned dbf_mcm_count(void);
bool dbf_mcm_key(unsigned index, char out[DBF_MCM_KEY_CAP]);

/* Text readback borrows caller's text buffer. Write only updates the supplied
 * candidate; callers validate/save their complete transaction before publishing it. */
bool dbf_mcm_read(const DbfSettings* s, const char* id, McmValue* out, char text[DBF_MCM_TEXT_CAP]);
bool dbf_mcm_write(DbfSettings* s, const char* id, const McmValue* value);
bool dbf_mcm_available(const DbfSettings* preview, const char* id);
#endif
