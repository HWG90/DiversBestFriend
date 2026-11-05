/* fake_ov: an OvApi (src/goose_overlay.h) that draws nothing and writes down what the code under test asked for.
 *
 * Every call the UI makes appends one line to an in-memory log the test reads. The lines:
 *   text:<s>  text_disabled:<s>  text_wrapped:<s>  text_colored:<s>        the text calls
 *   separator  spacing                                                      layout
 *   tabbar:<id>  tab:<label>  table:<id>                                    a begin_* call (its result is a knob below)
 *   col:<label>  headers  row  cell                                         table setup and movement
 *   end:tabbar  end:tab  end:table                                          an end_* call
 * Calls the UI does not make are NULL in the table, so a UI that starts using one fails loudly in its test.
 *
 * begin_* results: 1 by default; fake_ov_set_results changes them for the next draw (0 = the bar, the tab or the table is
 * not shown, and the UI must then not call its end_*). The fake keeps a stack of the begin_* calls that returned 1, so a
 * test can prove the UI paired every begin with its end (fake_ov_open() == 0) and never ended the wrong thing
 * (fake_ov_misuse() == 0).
 *
 * Portable C11 plus goose_overlay.h; for the Linux tests only. Not thread-safe. */
#ifndef DBF_FAKE_OV_H
#define DBF_FAKE_OV_H

#include "goose_overlay.h"

/* The fake API (version 4). */
const OvApi* fake_ov_api(void);

/* Clears the log and the stack, and sets every begin_* result back to 1. */
void fake_ov_reset(void);
void fake_ov_set_results(int tab_bar, int tab_item, int table);

/* The log. */
int fake_ov_lines(void);
const char* fake_ov_line(int index); /* NULL out of range */
/* The index of the first line equal to `line` at or after `from`, or -1. */
int fake_ov_find(const char* line, int from);
/* How many lines start with `prefix`. */
int fake_ov_count_prefix(const char* prefix);
/* 1 when more lines were written than the log holds (the extra ones were dropped). */
int fake_ov_overflowed(void);

/* begin_* calls that returned 1 and have no end_* yet; end_* calls that matched no open begin_* (or the wrong one). */
int fake_ov_open(void);
int fake_ov_misuse(void);

#endif
