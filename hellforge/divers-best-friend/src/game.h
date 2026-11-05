/* game: what DBF reads from the game, read-only, ported from R46 (the Lua DBF for build 25480438).
 *
 * game_read fills a GameView each tick: whether a mission is being played, whether the gameplay HUD is up, whether the
 * stratagem menu is open, whether the local player could be followed to its input owner (and, when it could, that
 * player's code-entry context: GameView.local), and the HUD's stratagem list: its active cards in list order, each with
 * its address and list position, the payload entry it shows, that entry's kind and code, and the card's timer block. It
 * never writes game memory and never calls game code: every read goes through memory.h (mem_read, mem_u8, mem_u32,
 * mem_u64, mem_ptr, mem_ptr_aligned) and every address, offset and constant comes from addresses_25480438.h.
 *
 * Two paths lead to the local player, as in R46:
 *   the display path (input.lua:218-234, R46's decorate, what its list highlight and cooldown dock used): the session's
 *     peer, the one mission entry carrying it, and that entry's payload. The rows and their kinds come from it: when it
 *     finds no payload, row_count is 0.
 *   the code-entry chain (input.lua:102-126, R46's context, what its display_codes and code entry used): player manager,
 *     network index, registry key, avatar (unit and input owner agree), player context, and that player's peer, which
 *     must be the session's (and not 0). local_ok says it held; the codes and GameView.local need it. When it fails
 *     (while dead, or dropping in, the list can still be up), the rows and kinds are still served, without codes, local
 *     is zero, and reason names the failing step. The controls and the UI word (read by R46's release paths, not by its
 *     context) do not belong to the chain: when they cannot be read, local.controls is 0, local.unobstructed false,
 *     local_ok stays true, and reason says "controls unreadable" or "UI unreadable".
 *
 * Lookups (the registry's, the avatars', the players') stop after LOOKUP_PROBE_LIMIT (256) probes, a cap Plan 1's final
 * review set (R46 walked the whole table): "lookup probe limit". game_lookup is the same lookup for other units.
 *
 * Each part is read only while admission admits its feature (adm_feature() == ADMIT_OK):
 *   FEAT_STATE       the game state, the HUD ready byte, the menu-open byte, the display path and the code-entry chain;
 *                    without it nothing is read
 *   FEAT_STRATAGEMS  the payload's kinds, the definition table and the codes (codes.h)
 *   FEAT_HUD_READ    the list cards
 *   FEAT_SCRAMBLE    the scramble remap of the codes (codes.h); without it the codes are the definitions' own
 * A part that is not admitted or not readable is left empty, and `reason` says why.
 *
 * reason: the first reason met in read order (state, HUD, local payload, code-entry chain, payload entries, definitions,
 * cards), cut to fit; "" when everything was read. Examples: "<feature name>: <admission reason>"
 * ("Stratagems: witness bravo differs"), "not initialised", "not in gameplay", "HUD not ready", "invalid menu-open flag",
 * "local mission payload unavailable", "local payload changed", "no local player", "lookup probe limit",
 * "local peer mismatch", "UI unreadable", "definition table unrecognised",
 * "HUD hierarchy not recognized: list parent mismatch", "card 3 parent mismatch", "card 3 layout unavailable",
 * "invalid definition", "shared code array", and the other reasons of codes.h.
 *
 * Where it differs from R46, on purpose:
 * - Rows are read whether the menu is open or closed (R46's include_closed), for the cooldown display.
 * - A card whose parent link or state byte is wrong, or whose layout target is not two usable floats (R46's pair(),
 *   native.lua:71: a NaN or a magnitude over 100000), is skipped (and named in reason); R46 dropped the whole list. A
 *   wrong link above the cards (panel, HUD container, fade, content, list) still drops the whole list.
 * - The code-entry chain reads the menu-active bit (input.lua:118) into local.menu_active but does not require it (R46's
 *   display_codes skipped it too, by passing allow_closed), and it skips R46's whole-HUD check (input.lua:99): here the
 *   HUD hierarchy is checked by the card reads, so one bad card costs that card, not every code.
 * - A lookup gives up after 256 probes (see Lookups above).
 * - The codes are codes.h's: vanilla kinds and HellForge mod stratagems (150 to 197) through the definition table,
 *   vanilla or HellForge's moved copy, with code arrays in the settings block or in HellForge's loader image. R46 knew
 *   neither HellForge nor its table and accepted an array outside the settings block only when the Lua HD2Runtime mod
 *   owned it, which has no counterpart here. Two rows whose kinds share a HellForge array both go without a code.
 * - Not ported (drawing and entry, later plans): HUD visibility bits, geometry and card sizes.
 *
 * Scramble: under a scramble effect R46 remapped the kind before reading its code (input.lua:150-157) after asking the
 * game (the scramble effect query, 0xa10820). codes_read does the same through native.h for each row, with the
 * code-entry context; scramble_known says that the query ran for this read's codes. When it did not (SCRAMBLE not
 * admitted, native without the query, the game.dll base or the effects pointer, or no code-entry chain), the codes are
 * the definitions' own: while a scramble effect is on, such a code may not be the one the game expects.
 *
 * Kept across reads: the image bounds (game_init, which hands them to codes_set_image) and the local identity (the
 * display path's session peer and payload address) of the last read that found one, so the read on which it changes
 * says "local payload changed", has local_ok false and serves no rows; the next read takes the new identity. The
 * definition table is checked again on every read (codes_table). Rows are never kept, and neither is codes' pass:
 * game_read forgets it first thing (codes_forget_pass), before any early return, so a codes_read later in the tick
 * (code entry's) only works on this read's table.
 *
 * Portable C11: standard headers, memory.h, admission.h and the generated header only (game.c adds codes.h). Not
 * thread-safe: only the game thread calls it. */
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
    uintptr_t card;                           /* the card's address in the HUD list */
    float list_y;                             /* the card's list position: the second float of its layout target
                                                 (+0x3740, R46 native.lua:274-276); R46 orders rows by it */
    uint32_t kind;                            /* the stratagem type (149 vanilla on 25480438; 150 and up from
                                                 HellForge mods); 0 when the card's entry is not in the payload */
    uint8_t code[DBF_CODE_CAPACITY];          /* directions 1 up, 2 right, 3 down, 4 left: the definition's, or the
                                                 remapped kind's under a scramble effect (see scramble_known) */
    uint8_t code_len;                         /* 0 when there is no code */
    uint32_t entry;                           /* the payload entry the card shows (+0x3748) */
    uint8_t timer[DBF_OFF_CARD_TIMER_SIZE];   /* the card's timer block (+0x3718), decoded by logic_timer (logic.h) */
    bool active;                              /* true for every row served (rows are the active cards) */
} DbfRow;

/* R46's code-entry context (input.lua:114-137, 294-295, 313), filled when GameView.local_ok; all zero otherwise. */
typedef struct GameLocal {
    uintptr_t manager, avatar, component, actions, input_owner, payload, controls;
    uint32_t key, index;
    bool menu_active;   /* bit 9 of u32 avatar+0xfd8 (R46 input.lua:118-119) */
    bool unobstructed;  /* u32 [UI]+0x429c+20 == 0 (R46 input.lua:294-295) */
} GameLocal;

typedef struct GameView {
    bool build_ok, in_gameplay, hud_ready, menu_open;
    bool local_ok;                            /* the code-entry chain held (codes are read only then); rows do not
                                                 need it */
    bool scramble_known;                      /* the game's scramble query ran for this read's codes: they follow a
                                                 scramble effect (codes.h) */
    uint32_t table_rva;                       /* the definition table's disp32: 0x37cb600, or HellForge's moved copy at
                                                 game.dll + (int32_t)table_rva (negative: below the image); 0 when it
                                                 was not read or not accepted */
    int row_count;                            /* active cards, in list order; rows past it are zero */
    DbfRow rows[DBF_VAL_CARD_COUNT];
    GameLocal local;                          /* the code-entry context; zero unless local_ok */
    char reason[DBF_REASON_SIZE];             /* why a part is missing; "" when nothing is */
} GameView;

/* Sets where game.dll is and its image size (SizeOfImage), for codes too (codes_set_image), and forgets everything kept
 * from earlier reads. A base of 0 or an image size of 0 leaves the reader uninitialised (game_read says "not
 * initialised"). */
void game_init(uintptr_t game_dll_base, uint32_t image_size);

/* Never fails: fills what it can and says why in reason. Uses the memory port of mem_init, the admission of adm_init, and
 * codes (codes_init's port, codes_table once per read, codes_read per row) and native (the scramble query). NULL is
 * ignored. */
void game_read(GameView* out);

/* R46's lookup (input.lua:74-94), for other units (codes): the open-addressing table at owner + offset maps `key` to an
 * index, which must be below `limit`. True with *index set; false (no reason, *index left alone) when the table cannot
 * be read or is not one, the key is not in it, the index is out of bounds, or LOOKUP_PROBE_LIMIT (256) probes found
 * neither the key nor an empty slot. Reads through memory.h only; it checks no admission and needs no game_init. */
bool game_lookup(uintptr_t owner, uint32_t offset, uint32_t key, uint32_t limit, uint32_t* index);

#endif
