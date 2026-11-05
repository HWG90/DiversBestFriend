#ifndef DBF_NATIVE_LIST_H
#define DBF_NATIVE_LIST_H

#include "game.h"

/* Start a new session with the verified game.dll base and DBF checkpoint logger. */
void native_list_init(uintptr_t base, void (*log)(const char*));

/* Game thread, once per tick after game_read and list selection. chosen indexes this
 * view's rows. Pass -1 (including on shutdown with a fresh view) to release styling.
 * A transiently missing view suspends changes until identity can be checked. */
void native_list_update(const GameView* view, int chosen);

#endif
