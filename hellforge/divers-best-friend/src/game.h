/* game: what DBF reads from the game, read-only, ported from R46 (the Lua DBF for build 25480438).
 *
 * game_read fills a GameView each tick: whether a mission is being played, whether the gameplay HUD is up, whether the
 * stratagem menu is open, whether the local player's mission payload was found, and the HUD's stratagem list: its
 * active cards in list order, each with the payload entry it shows, that entry's kind and code, and the card's timer
 * block. It never writes game memory and never calls game code: every read goes through memory.h (mem_read, mem_u8,
 * mem_u32, mem_u64, mem_ptr, mem_ptr_aligned) and every address, offset and constant comes from addresses_25480438.h.
 *
 * Each part is read only while admission admits its feature (adm_feature() == ADMIT_OK):
 *   FEAT_STATE       the game state, the HUD ready byte, the menu-open byte and the local player (registry, avatar,
 *                    session peer, mission payload); without it nothing is read
 *   FEAT_STRATAGEMS  the payload's kinds, the definition table and the codes
 *   FEAT_HUD_READ    the list cards
 * A part that is not admitted or not readable is left empty, and `reason` says why. Rows need the local payload: when
 * local_ok is false, row_count is 0.
 *
 * reason: the first reason met in read order (state, HUD, local player, payload, definitions, cards), cut to fit; "" when
 * everything was read. Examples: "<feature name>: <admission reason>" ("Stratagems: witness bravo differs"),
 * "not initialised", "not in gameplay", "HUD not ready", "invalid menu-open flag", "no local player",
 * "local peer mismatch", "local payload changed", "definition table unrecognised",
 * "HUD hierarchy not recognized: list parent mismatch", "card 3 parent mismatch", "invalid definition".
 *
 * Where it differs from R46, on purpose:
 * - Rows are read whether the menu is open or closed (R46's include_closed), for the cooldown display.
 * - A card whose parent link or state byte is wrong is skipped (and named in reason); R46 dropped the whole list. A wrong
 *   link above the cards (panel, HUD container, fade, content, list) still drops the whole list.
 * - The local player is read without R46's whole-HUD check (input.lua:99): that check belongs to code entry.
 * - Codes are read only for vanilla kinds (1 to 149), and only from code arrays inside the settings block: R46 accepted
 *   an array elsewhere only when the Lua HD2Runtime mod owned it, which has no counterpart here. Kinds from HellForge
 *   mods (150 and up) are listed without a code and without a reason.
 * - Not ported (drawing and entry, later plans): HUD visibility bits, geometry and card sizes, the menu-active bit, the
 *   scramble query's position read.
 *
 * Scramble: under a scramble effect R46 remapped the kind before reading its code (input.lua:150-157) after asking the
 * game through a native call (the scramble effect query, 0xa10820). This plan calls no game code, so codes are the
 * definition's own, never remapped, and scramble_known is always false: while a scramble effect is on, a code may not be
 * the one the game expects. Plan 2 adds the remap.
 *
 * Kept across reads: the image bounds (game_init), the definition table's RVA once accepted (accepted again whenever the
 * displacement changes), and the local identity (session peer and payload address) of the last read that found one, so
 * the read on which it changes says "local payload changed" and serves no rows. Rows are never kept.
 *
 * Portable C11: standard headers, memory.h, admission.h and the generated header only. Not thread-safe: only the game
 * thread calls it. */
#ifndef DBF_GAME_H
#define DBF_GAME_H

#include <stdbool.h>
#include <stdint.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "memory.h"

#define DBF_CODE_CAPACITY 16 /* DbfRow.code: R46 codes have at most DBF_VAL_CODE_MAX (12) directions */
#define DBF_REASON_SIZE 96

typedef struct DbfRow {
    uint32_t kind;                            /* the stratagem type (149 vanilla on 25480438; 150 and up from
                                                 HellForge mods); 0 when the card's entry is not in the payload */
    uint8_t code[DBF_CODE_CAPACITY];          /* directions 1 up, 2 right, 3 down, 4 left, as the definition gives them
                                                 (no scramble remap in this plan: see scramble_known) */
    uint8_t code_len;                         /* 0 when there is no code */
    uint32_t entry;                           /* the payload entry the card shows (+0x3748) */
    uint8_t timer[DBF_OFF_CARD_TIMER_SIZE];   /* the card's timer block (+0x3718), decoded by Plan 3 */
    bool active;                              /* true for every row served (rows are the active cards) */
} DbfRow;

typedef struct GameView {
    bool build_ok, in_gameplay, hud_ready, menu_open, local_ok;
    bool scramble_known;                      /* always false in this plan: codes are not scramble-remapped */
    uint32_t table_rva;                       /* where the definition table is: 0x37cb600 or HellForge's moved copy;
                                                 0 when it was not read or not accepted */
    int row_count;                            /* active cards, in list order; rows past it are zero */
    DbfRow rows[DBF_VAL_CARD_COUNT];
    char reason[DBF_REASON_SIZE];             /* why a part is missing; "" when nothing is */
} GameView;

/* Sets where game.dll is and its image size (SizeOfImage), and forgets everything kept from earlier reads. A base of 0
 * leaves the reader uninitialised. */
void game_init(uintptr_t game_dll_base, uint32_t image_size);

/* Never fails: fills what it can and says why in reason. Uses the memory port of mem_init and the admission of
 * adm_init. NULL is ignored. */
void game_read(GameView* out);

#endif
