/* synthetic: a fake game for the reader tests, laid out as build 25480438 at the offsets R46 reads.
 *
 * Memory is a sparse fake address space: 4 KiB pages, made on first write, carved from one calloc'd arena of at most
 * SYN_MAX_PAGES pages (2.5 MiB). The addresses are fake and never dereferenced; a read of a page nobody wrote fails, as
 * unmapped memory does. game.dll sits at SYN_GAME_BASE with game.dll's real SizeOfImage, helldivers2.exe at
 * SYN_EXE_BASE, and the game's objects at fixed user-space addresses (every pointer the image holds is 8-aligned, except
 * where R46 says the game packs one 4-aligned: definitions of even kinds, their code arrays, and the registry lookup's
 * slots, as live kind 50 and the live r7 capture showed).
 *
 * syn_build lays out a scene: both PE headers with 25480438's stamps, the bytes of every witness in dbf_witnesses
 * (whichever table is linked: tests/test_witnesses.h under DBF_TEST_WITNESSES, else the generated one), the globals, the
 * game state, the HUD root with its ready byte, the stratagem panel with the menu-open byte and the parent links of the
 * HUD container, fade, content, list and all 16 cards, the players / registry / avatars / units chain of the local
 * player (its avatar's menu-active word with bit 9 set), the session peer, the mission entries with the local payload,
 * the UI (unobstructed) and the controls, the settings block with a definition and a code for every vanilla kind, and
 * the definition table with the displacement that points at it. Each active card's timer block holds its layout target
 * (+0x3740, inside the block), whose second float is syn_list_y(card). The scramble query's inputs R46 reads before it
 * asks (input.lua:150-157) are there too: the positions global with the local (and the other) player's key in its
 * lookup and their 12-byte positions, and the local avatar's scramble seed (SynScene.scramble_seed).
 *
 * HellForge (0.4.0-beta, loader d8a8b46) is modelled as far as codes read it: syn_move_table puts the definition table in
 * a block of HellForge's shape above or below the image, syn_add_mod_stratagem adds a mod stratagem's row to that block
 * with its code array in a fake hellforge_modloader.dll image (SYN_LOADER_BASE, SYN_LOADER_SIZE), syn_stratagem_row is
 * the fake hf->stratagem_row, and syn_set_code points a definition at any array, as a Lua mod's set_code does.
 *
 * The ports: syn_mem_port() reads the image and refuses every write (counting it, so a test can prove the readers wrote
 * nothing); syn_adm_port() serves the two modules, reads code from the same image, and says HellForge may rewrite the
 * definition-table displacement (as it does when it moves the table).
 *
 * Portable C11 (standard headers, memory.h, admission.h and the generated header): Task 9 builds it for Windows too. */
#ifndef DBF_SYNTHETIC_H
#define DBF_SYNTHETIC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "memory.h"

#define SYN_GAME_BASE ((uintptr_t)0x180000000ull)
#define SYN_EXE_BASE ((uintptr_t)0x140000000ull)
#define SYN_IMAGE_SIZE 0x4744000u /* game.dll's SizeOfImage on 25480438 */
#define SYN_EXE_SIZE 0x1000u
#define SYN_GAME_STAMP 0x6AB3B43Fu
#define SYN_EXE_STAMP 0x6AB382E4u
#define SYN_PAGE 0x1000u
#define SYN_MAX_PAGES 640
#define SYN_MAX_STRATAGEMS 32
#define SYN_CODE_MAX 12
#define SYN_INACTIVE (-1)
/* The fake hellforge_modloader.dll image: mod stratagems' code arrays and Lua codes live in it (nothing else does). */
#define SYN_LOADER_BASE ((uintptr_t)0x7ffb12340000ull)
#define SYN_LOADER_SIZE 0x40000u
#define SYN_MOD_FIRST 150u /* HellForge's first new type (HF stratagems.c:42) */
#define SYN_MOD_LAST 197u  /* and its last: 150 + 48 - 1 (HF stratagems.c:43-44) */

typedef struct SynStratagem {
    uint32_t kind;
    uint8_t code_len;
    uint8_t code[SYN_CODE_MAX];
} SynStratagem;

typedef struct SynScene {
    uint32_t game_mode;        /* 4: in gameplay */
    uint8_t hud_ready;         /* 1: ready */
    uint8_t menu_open;         /* 1 open, 0 closed, anything else invalid */
    uint64_t peer;             /* the local peer: the session's, the player manager's and the local mission entry's */
    int mission_peers;         /* mission entries; the others carry other peers and other kinds */
    int local_entry;           /* the local player's mission entry */
    int stratagem_count;       /* entries in the local payload */
    SynStratagem stratagems[SYN_MAX_STRATAGEMS];
    int card_entry[16];        /* per list card: the payload entry it shows, or SYN_INACTIVE */
    uint32_t table_rva;        /* what the displacement says; the table is at game.dll + (int32_t)table_rva (HellForge's
                                  block may sit below the image) */
    uint32_t scramble_seed;    /* u32 at the local avatar + 0x11b8 (R46 input.lua:157) */
} SynScene;

/* Gameplay, HUD ready, menu open, three mission peers (the local one second), four stratagems (kinds 118, 4, 50 and 63,
 * codes of 3, 5, 6 and 5 directions), cards 0 to 3 showing entries 0 to 3, the vanilla table at 0x37cb600, and a
 * scramble seed of 0. */
void syn_default(SynScene* s);

/* Lays the scene out in a fresh image (the previous one is freed). False when the arena is full or the scene is out of
 * range (more than SYN_MAX_STRATAGEMS, a bad code length, mission_peers outside 1..32, local_entry outside them, a card
 * entry below SYN_INACTIVE). */
bool syn_build(const SynScene* s);
void syn_free(void);

/* The ports. */
int syn_read(uintptr_t address, void* out, size_t size);        /* 0 when every byte is mapped */
int syn_write(uintptr_t address, const void* data, size_t size); /* refuses (-1) and counts */
int syn_write_count(void);                                       /* writes asked for since the program started */
const MemPort* syn_mem_port(void);
const AdmPort* syn_adm_port(void);

/* Changes to the built image. A poke makes the pages it needs; syn_unmap drops the page holding `address`, so its reads
 * fail. */
bool syn_poke(uintptr_t address, const void* data, size_t size);
bool syn_poke_u8(uintptr_t address, uint8_t v);
bool syn_poke_u32(uintptr_t address, uint32_t v);
bool syn_poke_u64(uintptr_t address, uint64_t v);
bool syn_unmap(uintptr_t address);

/* Where things are in the built image. */
uintptr_t syn_hud_root(void);
uintptr_t syn_panel(void);
uintptr_t syn_list(void);
uintptr_t syn_card(int index);
uintptr_t syn_game_state(void);
uintptr_t syn_players(void);
uintptr_t syn_registry(void);
uintptr_t syn_avatars(void);
uintptr_t syn_local_unit(void);
uintptr_t syn_local_avatar(void);
uintptr_t syn_session(void);
uintptr_t syn_mission(void);
uintptr_t syn_payload(int mission_entry);
uintptr_t syn_settings(void);
uintptr_t syn_definition(uint32_t kind); /* the definition (settings descriptor) of a vanilla kind */
uintptr_t syn_code_array(uint32_t kind);
uintptr_t syn_ui(void);       /* the UI object: its obstruction word (+0x429c+20) is 0 */
uintptr_t syn_controls(void); /* the controls object */
/* The local player's code-entry context as R46's context() returns it (input.lua:114-137). */
uintptr_t syn_local_component(void);
uintptr_t syn_local_actions(void);
uintptr_t syn_local_input_owner(void);
uint32_t syn_local_key(void);
uint32_t syn_local_index(void); /* its avatar index */
float syn_list_y(int card);     /* the list position syn_build gives card `card` (the second float at +0x3740) */

/* The timer block syn_build gives list card `card` showing payload entry `entry` of kind `kind` (0 when the entry is not
 * in the payload). The card's layout target (+0x3740) and entry field (+0x3748) lie inside the block, at +0x28 and +0x30. */
void syn_timer_bytes(int card, uint32_t entry, uint32_t kind, uint8_t out[DBF_OFF_CARD_TIMER_SIZE]);

/* HellForge's move: syn_move_table((int32_t)rva). */
bool syn_relocate_table(uint32_t rva);

/* HellForge's move of the definition table (HF stratagems.c:372-388, 427-437, 504): a block at game.dll + displacement
 * (sign-extended, as the CPU reads the instruction's disp32: negative is below the image) with HellForge's 198 slots
 * (150 + 48, stratagems.c:42-44) holding the 150 vanilla entries and 48 zeros, then room for 48 400-byte rows after the
 * names; the displacement is pointed at it. The block forgets the mod stratagems added before. False when the image is
 * not built or a write fails. */
bool syn_move_table(int32_t displacement);
uintptr_t syn_table(void); /* the table the displacement points at in the built image (vanilla or moved) */

/* A HellForge mod stratagem of `kind` (SYN_MOD_FIRST..SYN_MOD_LAST) laid out as HellForge lays one out (HF
 * stratagems.c:390-424, 504): its 400-byte row in the moved block, naming the kind, its code array of `n` directions in
 * the fake loader image (syn_mod_code(kind); n 0..SYN_CODE_MAX, beyond HellForge's 9, so tests can break its rule), and
 * the table's slot for the kind pointing at the row. syn_stratagem_row(kind) returns the row from then on. Returns the
 * row; 0 when the table is not moved, the kind or n is out of range, or a write fails. */
uintptr_t syn_add_mod_stratagem(uint32_t kind, int n, const uint8_t* code);
/* The fake hf->stratagem_row: the row of an added kind that is not tombstoned, else 0 (HF stratagems.c:309-314). */
uintptr_t syn_stratagem_row(uint32_t type);
/* HellForge took the kind's mod out (a tombstone, HF live_content.c:674-700): stratagem_row says 0 from now on, while
 * the row and the table's slot stay. False when the kind was not added. */
bool syn_tombstone(uint32_t kind);
uintptr_t syn_mod_code(uint32_t kind);   /* where syn_add_mod_stratagem puts the kind's code array (loader image) */
uintptr_t syn_loader_spare(int slot);    /* spare 64-byte, 8-aligned arrays in the loader image (slot 0..63): where a
                                            Lua mod's set_code puts a code (HF lua_bridge.c:353-401) */

/* Points `definition` (a vanilla definition, a mod row) at `array` with `n` directions written there, as a Lua mod's
 * set_code repoints +0x40/+0x48. n 0..SYN_CODE_MAX; `code` may be NULL to leave the array's bytes alone. */
bool syn_set_code(uintptr_t definition, uintptr_t array, int n, const uint8_t* code);

/* The scramble query's inputs (R46 input.lua:150-152): the positions object, its lookup at +0x40 maps the local key to
 * syn_local_position_index(), and the 12 bytes at [positions + 0x68] + index * 0x308 + 0x2e0 are readable. */
uintptr_t syn_positions(void);
uintptr_t syn_position(uint32_t index);       /* [positions + 0x68] + index * 0x308 + 0x2e0 */
uint32_t syn_local_position_index(void);

/* A second definition for `kind` (naming the kind, inside the settings block, past every code array) with its own code
 * of `n` directions; returns its address, or 0 when n is out of range or a write fails. A test points one table's entry
 * at it to tell the tables apart. There is one: a later call replaces it. */
uintptr_t syn_alternate_definition(uint32_t kind, int n, const uint8_t* code);

/* A new session for the same player: the session, the player manager and the local mission entry all get `peer`. */
bool syn_change_peer(uint64_t peer);

/* Lays the registry's lookup out again with `capacity` slots (a power of two up to 1024), every slot holding some other
 * key except the local player's network index at probe `position` (from its hash; -1: not there) and the empty key at
 * probe `empty_at` (-1: none). False when the arguments are out of range or a write fails. */
bool syn_registry_probe(uint32_t capacity, int position, int empty_at);

#endif
