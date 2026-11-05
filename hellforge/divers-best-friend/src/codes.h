/* codes: the stratagem input codes DBF shows and enters, read-only: vanilla kinds, HellForge mod stratagems and the
 * scramble remap. Ported from R46's code() (input.lua:141-179) and extended for HellForge 0.4.0-beta (loader d8a8b46,
 * "HF" below), which R46 did not know about.
 *
 * The definition table (codes_table; game_read calls it once per read, and it reads everything again each time). The
 * definition-table load at RVA 0x66d54c (mov rax, [r13 + r15*8 + disp32], R46 native.lua:51-55) holds the table's
 * offset from game.dll in its disp32 at DBF_RVA_DEFINITION_DISPLACEMENT; the CPU sign-extends it, and so does codes:
 *   - game.dll + 0x37cb600, the vanilla table: kinds 1..149;
 *   - HellForge's moved copy, which exists only when HellForge mods add stratagems (HF stratagems.c:486): a block it
 *     allocates within 2 GiB of game.dll, above or below the image (HF damage.c:123-202), the vanilla pointers copied
 *     into slots 0..149 and the new types' rows in 150..197 (stratagems.c:372-388, 427-437, 504). Accepted when the table
 *     (all 198 slots) lies outside [game.dll, game.dll + image size), less than 2^31 bytes from game.dll and 8-aligned:
 *     kinds 1..197 (stratagems.c:42-44: 150 + 48 types, which travel in 8 bits).
 *   Anything else is "definition table unrecognised"; a displacement or table slots that cannot be read are "definition
 *   table unreadable". The table's slots 1..max_kind must be readable.
 *
 * A kind's code (codes_read):
 *   1. Its definition: the table's slot for the kind, a 4-aligned pointer to a row naming the kind (u32 at +0). Kinds
 *      1..149: the row lies inside the settings block, [settings, settings + 80280 - 400] (R46 input.lua:160-164).
 *      Kinds 150..197: the row equals the port's stratagem_row(kind) and is not 0 (HF stratagems.c:309-314: 0 for a type
 *      not loaded or tombstoned; every kind is asked on its own, so a tombstoned 150 does not hide 151).
 *   2. Its code array: the count (+0x48), then the pointer (+0x40, 4-aligned), then the directions; then all three again,
 *      and any difference is "code changed while reading". The array [pointer, pointer + 4 * count) must lie inside the
 *      settings block with 1 to 12 directions (R46 input.lua:166), or inside hellforge_modloader.dll's image with 1 to 9
 *      (a mod stratagem's own code, HF stratagems.c:47, 400-405; a Lua mod's set_code, HF lua_bridge.c:353-401); every
 *      direction 1 to 4. An array anywhere else is "code outside the game and HellForge", and the port's log gets one
 *      line per kind per session (codes_init).
 *   3. Shared arrays: when two kinds read in one pass (since the last codes_table) point at one loader-image array, both
 *      are refused for the rest of the pass, "shared code array" (HellForge's restore of a Lua code can leave two types on
 *      one array, HF lua_bridge.c:383). The kind that was read first got its code; codes_shared() tells its caller to
 *      drop it (game_read does). At most CODES_PASS_ARRAYS loader-image arrays are tracked in a pass; past that a
 *      loader-image array is refused, "too many HellForge code arrays".
 *   4. Scramble (R46 input.lua:150-157), only when `local` is not NULL and FEAT_SCRAMBLE is ADMIT_OK: the positions entry
 *      of local->key must be there (the lookup at [game.dll + 0x3326508] + 0x40, then 12 readable bytes at
 *      [positions + 0x68] + index * 0x308 + 0x2e0), else "scramble position unavailable"; then nat_scramble_query(key,
 *      kind). An answer of 0xffffffff, or a query that did not run (native.h says when), leaves the kind's own code.
 *      Another answer remaps: kind' = ((kind + u32[avatar + 0x11b8]) mod 2^32) mod 149 + 1, and kind' is read by rules 1
 *      to 3 (scrambled true). With HellForge's moved table (kinds above 149) the game's modulus may not be 149 any more,
 *      so a remap is refused, "scrambled codes with mod stratagems are not supported yet".
 * Whatever fails leaves no code and says why in `reason`. Reasons: "not initialised", "<feature name>: <admission's
 * reason>", "definition table unreadable", "definition table unrecognised", "no definition table" (codes_read before an
 * accepted codes_table), "unknown stratagem kind" (0, or above the table's kinds), "settings unreadable", "invalid
 * definition", "mod stratagems unavailable" (kinds 150 and up without a stratagem_row), "mod stratagem not loaded"
 * (stratagem_row says 0), "invalid code array", "code outside the game and HellForge", "code array unreadable", "code
 * changed while reading", "invalid direction", "shared code array", "too many HellForge code arrays", "scramble position
 * unavailable", "scramble seed unreadable", "scrambled codes with mod stratagems are not supported yet".
 *
 * Every read goes through memory.h, every game call through native.h (nat_scramble_query only), and every number is the
 * generated header's, except HellForge's own limits, which are named constants in codes.c citing their HF lines.
 * Portable C11: standard headers, memory.h, admission.h, native.h, game.h and the generated header only; no SDK and no
 * platform header. Not thread-safe: only the game thread calls it. */
#ifndef DBF_CODES_H
#define DBF_CODES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "game.h"

#define CODES_PASS_ARRAYS 64 /* loader-image arrays tracked per pass: 48 mod rows and the vanilla kinds Lua mods recode */

typedef struct CodePort {
    uintptr_t (*stratagem_row)(uint32_t type);  /* hf->stratagem_row, or NULL: kinds 150 and up get no code */
    uintptr_t loader_base; size_t loader_size;  /* hellforge_modloader.dll's image, or 0: its arrays are refused */
    /* Optional (NULL: codes logs nothing): takes one line, without a line end, from the game thread. Added last, so an
     * initialiser that stops at loader_size stays valid. */
    void (*log)(const char* line);
} CodePort;

typedef struct DbfCode {
    uint8_t dir[DBF_CODE_CAPACITY]; /* directions 1 up, 2 right, 3 down, 4 left */
    uint8_t len;                    /* 0 when there is no code */
    uint32_t kind_used;             /* the kind whose code this is: the kind asked for, or the scramble's kind' */
    bool scrambled;                 /* the scramble remapped the kind */
} DbfCode;

/* Starts a session: copies the port (NULL: an empty one), re-arms the once-per-kind log lines and forgets the table and
 * the pass. The game.dll image comes from codes_set_image. */
void codes_init(const CodePort* port);

/* Where game.dll is and its image size; game_init calls it. Forgets the table and the pass. 0 for either: none. */
void codes_set_image(uintptr_t game_dll, uint32_t image_size);

/* Forgets the table and the pass, as codes_set_image does, without changing the image: codes_read refuses ("no definition
 * table") until the next codes_table accepts a table. game_read calls it first thing, so a codes_read later in the tick
 * (code entry's) never works against an earlier tick's table, claims or scramble flag. */
void codes_forget_pass(void);

/* Reads and checks the definition table (see the top) and starts a new pass: the shared-array table and the scramble
 * flag (codes_scramble_asked) are emptied. True with *max_kind set to 149 (vanilla) or 197 (HellForge's); false with
 * *max_kind 0 and the reason, and then codes_read refuses until the next codes_table that accepts a table. NULL
 * arguments are allowed (reason NULL or n 0: no reason). */
bool codes_table(uint32_t* max_kind, char* reason, size_t n);

/* The code of `kind` (see the top), with the scramble remap when `local` (the code-entry context, GameView.local) is
 * given. True with *out filled; false with *out zero (when not NULL) and the reason. Uses the table of the last
 * codes_table. */
bool codes_read(uint32_t kind, const GameLocal* local, DbfCode* out, char* reason, size_t n);

/* The table the last codes_table accepted (an address), or 0. */
uintptr_t codes_table_at(void);

/* True when a codes_read since the last codes_table asked the game's scramble query (it ran: its feature was admitted
 * and native had the game.dll base and the effects pointer). */
bool codes_scramble_asked(void);

/* True when, in this pass, `kind`'s loader-image code array turned out to be another kind's too (rule 3). */
bool codes_shared(uint32_t kind);

#endif
