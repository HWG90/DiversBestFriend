/* text: the player-facing text the other units share, built without printf (the DLL imports no printf-family function):
 * a line put together piece by piece, a bounded copy, the stratagems' names and the codes as "^ > v <".
 *
 * A leaf unit: it calls no other unit of the mod, so the snapshot (on the game thread) and the UIs (on the render thread)
 * both use it without depending on each other (Plan 2, Task 12: the snapshot used to reach these through ui_settings).
 *
 * Threads: everything here may be called from any thread, except dbf_kind_name, whose "Stratagem <kind>" text lives in
 * one static buffer: render thread only (the game thread names things with dbf_kind_name_copy).
 *
 * Portable C11: standard headers, game.h (for DBF_CODE_CAPACITY only) and the generated kind names. */
#ifndef DBF_TEXT_H
#define DBF_TEXT_H

#include <stddef.h>
#include <stdint.h>
#include "game.h"

#define DBF_LINE_SIZE 256 /* a DbfLine holds DBF_LINE_SIZE - 1 bytes of text */

/* A line of text built piece by piece; what does not fit is cut, and the text is always terminated. */
typedef struct DbfLine {
    char text[DBF_LINE_SIZE];
    size_t length;
} DbfLine;

/* Starts the line with `first` (NULL: empty). */
void dbf_line_begin(DbfLine* l, const char* first);
/* Appends `text` (NULL: nothing). */
void dbf_line_add(DbfLine* l, const char* text);
/* Appends `value` in decimal; a number that does not fit whole keeps its first digits. */
void dbf_line_add_uint(DbfLine* l, uint32_t value);

/* Copies `src` (NULL: empty) into dst[size] and always terminates it, cutting src at size - 1 bytes when it is longer; size
 * 0 or a NULL dst does nothing. Bytes, not characters: the texts are ASCII. */
void dbf_text_copy(char* dst, size_t size, const char* src);

/* The stratagem's name: its entry in dbf_kind_names for vanilla kinds (below 150) that have one, else "Stratagem <kind>"
 * (HellForge mods' kinds start at 150; Plan 3 gives those their own titles). The "Stratagem <kind>" text lives in a
 * static buffer that the next call overwrites: use it before calling again. Render thread only. */
const char* dbf_kind_name(uint32_t kind);

/* The same name copied into dst[size] (terminated, cut to fit): no shared buffer, so any thread may call it. The game
 * thread names the list view's rows with it while the render thread uses dbf_kind_name. */
void dbf_kind_name_copy(uint32_t kind, char* dst, size_t size);

/* The first `n` directions of a code (limited to DBF_CODE_CAPACITY) as "^ > v <" into dst[size] (terminated, cut to fit): 1
 * up, 2 right, 3 down, 4 left, "?" for any other value; "" for none. Any thread. */
void dbf_code_arrows(const uint8_t* code, size_t n, char* dst, size_t size);

#endif
