#ifndef DBF_MIGRATION_H
#define DBF_MIGRATION_H

#include "settings.h"

/* Defaults are supplied by the caller. Each optional input is a writable,
 * NUL-terminated copy of one Lua TSV file. Only recognised values are applied. */
bool migration_parse(DbfSettings* settings, char* options, char* blacklist);

#ifdef _WIN32
typedef enum { MIGRATION_NONE, MIGRATION_CREATED, MIGRATION_FAILED } MigrationResult;
MigrationResult migration_first_start(const wchar_t* local_data, const wchar_t* destination);
#endif
#endif
