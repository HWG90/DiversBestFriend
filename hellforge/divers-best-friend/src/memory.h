/* memory: the only way the mod touches game memory.
 *
 * Reads go through a port and fail instead of faulting. Writes are compare-and-swap writes recorded in a restore journal,
 * so every byte the mod changes in the game can be put back (menu close, mission end, a feature refused, shutdown). The
 * port is what wraps HellForge's hf->read and hf->write; this unit includes no platform and no SDK header, so it builds
 * and is tested natively on Linux.
 *
 * Not thread-safe by design: only the game thread calls it.
 *
 * The journal is a fixed array (MEM_JOURNAL_ENTRIES entries of up to MEM_SWAP_MAX bytes) and never allocates. Each
 * entry keeps the address, the size, the owner, the original bytes and the bytes the mod left there. An owner has at
 * most one entry per address: swapping the same address and size again re-asserts that entry (see mem_swap).
 *
 * When owners' changes overlap (one owner swaps bytes another owner already changed, e.g. LIST then CAMERA on one
 * address), restore newer owners first: each entry's original is the bytes the owner before it left, so only
 * newest-first gives the game's original back. Restoring the older owner first leaves the newer owner's bytes alone
 * (they are not what the older owner wrote), and the newer owner's restore then writes back the older owner's value.
 * mem_restore_all always goes newest first. */
#ifndef DBF_MEMORY_H
#define DBF_MEMORY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MEM_JOURNAL_ENTRIES 64
#define MEM_SWAP_MAX 32

typedef struct MemPort {
    int (*read)(uintptr_t address, void* out, size_t size);         /* 0 on success */
    int (*write)(uintptr_t address, const void* data, size_t size); /* 0 on success */
} MemPort;

/* Who made a change, so one feature's changes can be put back without touching another's. */
typedef enum { MEM_OWNER_LIST, MEM_OWNER_LATCH, MEM_OWNER_CAMERA, MEM_OWNER_ENTRY, MEM_OWNER_TERMINAL, MEM_OWNER_COUNT } MemOwner;

typedef enum {
    MEM_SWAPPED,   /* the bytes held `expect` (on a re-assert: the entry's original) and now hold `value`; journaled */
    MEM_ALREADY,   /* the bytes already hold `value`; nothing was written or journaled */
    MEM_DIFFERENT, /* the bytes hold neither; nothing was written or journaled */
    MEM_FAILED     /* the arguments were bad, the read failed, the journal is full, or the write failed (see mem_swap
                      for the one case that still journals) */
} MemSwap;

/* Starts a session: copies the port (NULL leaves no port, so every call fails) and empties the journal. Entries still in
 * the journal are forgotten, not restored: call mem_restore_all first when anything is still swapped. */
void mem_init(const MemPort* port);

/* Reads `size` bytes (at least 1) at `address` into `out`. False when the port is missing, an argument is bad, the range
 * wraps the address space, or the port's read fails; `out` is then unspecified. */
bool mem_read(uintptr_t address, void* out, size_t size);

/* Typed reads; the output is left alone when the read fails. */
bool mem_u8(uintptr_t a, uint8_t* v);
bool mem_u32(uintptr_t a, uint32_t* v);
bool mem_u64(uintptr_t a, uint64_t* v);

/* Reads a pointer and accepts it only when it is plausibly a user-mode pointer: fails for 0, for values below 0x10000 or
 * above 0x7FFFFFFFFFFF, and unless 8-aligned. The output is left alone on failure. */
bool mem_ptr(uintptr_t a, uintptr_t* v);

/* mem_ptr with another alignment (1, 2, 4 or 8; anything else fails): the same range, the value a multiple of
 * `alignment`. For the data pointers the game packs tighter than its objects (R46 reads definition, code-array and lookup
 * pointers 4-aligned). mem_ptr(a, v) is mem_ptr_aligned(a, v, 8). */
bool mem_ptr_aligned(uintptr_t a, uintptr_t* v, uintptr_t alignment);

/* Replaces `size` bytes (1 to MEM_SWAP_MAX) at `address` with `value`, only when they equal `expect`, and journals the
 * change under `owner`. A fresh read decides the result: MEM_ALREADY when the bytes already equal `value` (checked
 * first), MEM_DIFFERENT when they do not equal `expect`. A full journal is MEM_FAILED, and then nothing is written.
 *
 * Re-assert: when `owner` already has an entry for `address` and the same `size`, no entry is added (the latch calls
 * this every frame to keep its value in place). MEM_ALREADY when the bytes equal `value`; otherwise, only when they
 * equal that entry's original (the game wrote it back), `value` is written, becomes what the entry holds, and the result
 * is MEM_SWAPPED; anything else is MEM_DIFFERENT. `expect` is not consulted then, and a full journal does not matter.
 * An entry of `owner` at `address` with another size makes the call MEM_FAILED without a write.
 *
 * A write that fails is MEM_FAILED. When it may have changed bytes (they read back different, or cannot be read), the
 * bytes from before the swap are written back. When that rollback fails too (and the bytes do not read back as they
 * were), the change is journaled under `owner` anyway (a re-assert updates its entry), as {original = the bytes before
 * the swap, written = the bytes read back after the failed rollback, or `value` when they cannot be read}, so that a
 * later mem_restore puts the original back while the bytes still hold that. */
MemSwap mem_swap(uintptr_t address, const void* expect, const void* value, size_t size, MemOwner owner);

/* Puts back every change of `owner`, newest first. An original is written back only while the bytes still hold what the
 * entry says the mod left there; otherwise they are left alone. Returns how many entries it could not put back (the read
 * failed, the write failed, or the bytes had changed). All of the owner's entries leave the journal either way. Owners
 * whose changes overlap must be restored newer owners first (see the top of this header). */
int mem_restore(MemOwner owner);

/* The same for every owner, in one newest-first pass over the whole journal. */
int mem_restore_all(void);

#endif
