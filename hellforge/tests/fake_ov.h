/* fake_ov: an OvApi (src/goose_overlay.h) that draws nothing and writes down what the code under test asked for.
 *
 * Every call the UI makes appends one line to an in-memory log the test reads. The lines:
 *   text:<s>  text_disabled:<s>  text_wrapped:<s>  text_colored:<s>        the text calls
 *   separator  spacing                                                      layout
 *   tabbar:<id>  tab:<label>  table:<id>                                    a begin_* call (its result is a knob below)
 *   col:<label>  headers  row  cell                                         table setup and movement
 *   end:tabbar  end:tab  end:table                                          an end_* call
 *   rect:<color>  dtext:<color>:<text>                                      draw_rect_filled and draw_text, the colour as
 *                                                                           8 hex digits (0xAABBGGRR, upper case)
 * The numbers of a draw line are read with fake_ov_geom. text_size and theme are queries: they answer (see below) and log
 * nothing.
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

/* Clears the log and the stack, sets every begin_* result back to 1 and the theme back to a host 0.4.0's. */
void fake_ov_reset(void);
void fake_ov_set_results(int tab_bar, int tab_item, int table);

/* The fake theme: token OV_THEME_* gives the colour 0xFFC0DE00 + token, so every token has a colour of its own that no
 * literal in the UI can equal by accident. fake_ov_set_old_host(1) makes the tokens host 0.4.0 added (OV_THEME_ON_ACCENT
 * and later) answer 0xFFFFFFFF, as an older host does. text_size answers `size / 2` pixels of width per byte (size 0 is a
 * 20 px font) and a height of `size`. */
uint32_t fake_ov_theme_color(int token);
void fake_ov_set_old_host(int old);

/* The log. */
int fake_ov_lines(void);
const char* fake_ov_line(int index); /* NULL out of range */
/* The index of the first line equal to `line` at or after `from`, or -1. */
int fake_ov_find(const char* line, int from);
/* How many lines start with `prefix`. */
int fake_ov_count_prefix(const char* prefix);
/* The numbers behind line `index` when it is a draw call, else 0 (out is left alone). rect: x0, y0, x1, y1, rounding.
 * dtext: x, y, size, font, 0. */
int fake_ov_geom(int index, float out[5]);
/* 1 when more lines were written than the log holds (the extra ones were dropped). */
int fake_ov_overflowed(void);

/* begin_* calls that returned 1 and have no end_* yet; end_* calls that matched no open begin_* (or the wrong one). */
int fake_ov_open(void);
int fake_ov_misuse(void);

#endif
