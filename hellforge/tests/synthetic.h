/* synthetic: a fake game for the reader tests, laid out as build 25480438 at the offsets R46 reads.
 *
 * Memory is a sparse fake address space: 4 KiB pages, made on first write, carved from one calloc'd arena of at most
 * SYN_MAX_PAGES pages (2 MiB). The addresses are fake and never dereferenced; a read of a page nobody wrote fails, as
 * unmapped memory does. game.dll sits at SYN_GAME_BASE with game.dll's real SizeOfImage, helldivers2.exe at
 * SYN_EXE_BASE, and the game's objects at fixed user-space addresses (every pointer the image holds is 8-aligned, except
 * where R46 says the game packs one 4-aligned: definitions of even kinds, their code arrays, and the registry lookup's
 * slots, as live kind 50 and the live r7 capture showed).
 *
 * syn_build lays out a scene: both PE headers with 25480438's stamps, the bytes of every witness in dbf_witnesses
 * (whichever table is linked: tests/test_witnesses.h under DBF_TEST_WITNESSES, else the generated one), the globals, the
 * game state, the HUD root with its ready byte, the stratagem panel with the menu-open byte and the parent links of the
 * HUD container, fade, content, list and all 16 cards, the players / registry / avatars / units chain of the local
 * player, the session peer, the mission entries with the local payload, the settings block with a definition and a code
 * for every vanilla kind, and the definition table with the displacement that points at it.
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
#define SYN_MAX_PAGES 512
#define SYN_MAX_STRATAGEMS 32
#define SYN_CODE_MAX 12
#define SYN_INACTIVE (-1)

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
    uint32_t table_rva;        /* where the definition table is and what the displacement says */
} SynScene;

/* Gameplay, HUD ready, menu open, three mission peers (the local one second), four stratagems (kinds 118, 4, 50 and 63,
 * codes of 3, 5, 6 and 5 directions), cards 0 to 3 showing entries 0 to 3, and the vanilla table at 0x37cb600. */
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

/* The timer block syn_build gives list card `card` showing payload entry `entry` of kind `kind` (0 when the entry is not
 * in the payload). The card's entry field (+0x3748) lies inside the block, at +0x30. */
void syn_timer_bytes(int card, uint32_t entry, uint32_t kind, uint8_t out[DBF_OFF_CARD_TIMER_SIZE]);

/* HellForge's move: copies the table's 150 entries to `rva` and points the displacement at it. */
bool syn_relocate_table(uint32_t rva);

/* A second definition for `kind` (naming the kind, inside the settings block, past every code array) with its own code
 * of `n` directions; returns its address, or 0 when n is out of range or a write fails. A test points one table's entry
 * at it to tell the tables apart. There is one: a later call replaces it. */
uintptr_t syn_alternate_definition(uint32_t kind, int n, const uint8_t* code);

/* A new session for the same player: the session, the player manager and the local mission entry all get `peer`. */
bool syn_change_peer(uint64_t peer);

#endif
