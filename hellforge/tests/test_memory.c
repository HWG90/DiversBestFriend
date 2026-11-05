/* Tests for src/memory.c against a fake port over a 4 KiB array; reads and writes outside the array fail. */
#include <stdint.h>
#include <string.h>
#include "memory.h"
#include "test.h"

#define RAM_BASE ((uintptr_t)0x20000)
#define RAM_SIZE 4096u

static uint8_t g_ram[RAM_SIZE];
static int g_reads;
static int g_writes;
static int g_fail_next_writes; /* how many upcoming writes fail */
static size_t g_partial_bytes; /* how many bytes the first of them still puts in before it fails */
static size_t g_partial_later; /* and how many each later one puts in */
static int g_failed_in_run;    /* failing writes since the last fail_writes() */
static int g_reads_fail_after; /* reads fail once this many writes were made (0: reads never fail this way) */

static int in_ram(uintptr_t address, size_t size)
{
    return address >= RAM_BASE && size <= RAM_SIZE && address - RAM_BASE <= RAM_SIZE - size;
}

static int fake_read(uintptr_t address, void* out, size_t size)
{
    g_reads++;
    if (!in_ram(address, size)) return -1;
    if (g_reads_fail_after > 0 && g_writes >= g_reads_fail_after) return -1;
    memcpy(out, &g_ram[address - RAM_BASE], size);
    return 0;
}

static int fake_write(uintptr_t address, const void* data, size_t size)
{
    g_writes++;
    if (!in_ram(address, size)) return -1;
    if (g_fail_next_writes > 0) {
        size_t partial = g_failed_in_run++ == 0 ? g_partial_bytes : g_partial_later;
        g_fail_next_writes--;
        memcpy(&g_ram[address - RAM_BASE], data, partial < size ? partial : size);
        return -1;
    }
    memcpy(&g_ram[address - RAM_BASE], data, size);
    return 0;
}

static const MemPort FAKE_PORT = { fake_read, fake_write };

static uint8_t* ram_at(uintptr_t address) { return &g_ram[address - RAM_BASE]; }

static void put64(uintptr_t address, uint64_t v) { memcpy(ram_at(address), &v, sizeof v); }

static void reset(void)
{
    for (size_t i = 0; i < RAM_SIZE; i++) g_ram[i] = (uint8_t)(i * 7 + 3);
    g_reads = 0;
    g_writes = 0;
    g_fail_next_writes = 0;
    g_partial_bytes = 0;
    g_partial_later = 0;
    g_failed_in_run = 0;
    g_reads_fail_after = 0;
    mem_init(&FAKE_PORT);
}

/* The next `n` writes fail; the first still puts in `first` bytes, each later one `later` bytes. */
static void fail_writes(int n, size_t first, size_t later)
{
    g_fail_next_writes = n;
    g_partial_bytes = first;
    g_partial_later = later;
    g_failed_in_run = 0;
}

static void test_before_init(void)
{
    uint8_t b = 0x55;
    uint32_t w = 0x55555555u;
    uintptr_t p = 1;
    const uint8_t expect[4] = { 1, 2, 3, 4 }, value[4] = { 5, 6, 7, 8 };
    CHECK(!mem_read(RAM_BASE, &b, 1), "before mem_init a read fails");
    CHECK(!mem_u8(RAM_BASE, &b) && b == 0x55, "before mem_init mem_u8 fails and leaves the output");
    CHECK(!mem_u32(RAM_BASE, &w) && w == 0x55555555u, "before mem_init mem_u32 fails and leaves the output");
    CHECK(!mem_ptr(RAM_BASE, &p) && p == 1, "before mem_init mem_ptr fails and leaves the output");
    CHECK(mem_swap(RAM_BASE, expect, value, 4, MEM_OWNER_LIST) == MEM_FAILED, "before mem_init a swap fails");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0 && mem_restore_all() == 0, "before mem_init a restore has nothing to do");
}

static void test_reads(void)
{
    uint8_t b = 0;
    uint32_t w = 0;
    uint64_t q = 0;
    uint8_t buf[8];
    reset();
    memcpy(ram_at(RAM_BASE + 0x100), "\x11\x22\x33\x44\x55\x66\x77\x88", 8);
    CHECK(mem_u8(RAM_BASE + 0x100, &b) && b == 0x11, "mem_u8 reads one byte");
    CHECK(mem_u32(RAM_BASE + 0x100, &w) && w == 0x44332211u, "mem_u32 reads four bytes little-endian");
    CHECK(mem_u64(RAM_BASE + 0x100, &q) && q == 0x8877665544332211ull, "mem_u64 reads eight bytes little-endian");
    CHECK(mem_read(RAM_BASE + 0x100, buf, 8) && memcmp(buf, ram_at(RAM_BASE + 0x100), 8) == 0, "mem_read copies the bytes");
    CHECK(mem_read(RAM_BASE + RAM_SIZE - 1, buf, 1), "the last byte of the array reads");
    CHECK(!mem_read(RAM_BASE + RAM_SIZE - 1, buf, 2), "a read running past the end fails");
    CHECK(!mem_read(RAM_BASE - 1, buf, 1), "a read before the start fails");
    CHECK(!mem_read(0, buf, 1), "a read at 0 fails");
    b = 0xEE;
    CHECK(!mem_u8(RAM_BASE + RAM_SIZE, &b) && b == 0xEE, "a failed mem_u8 leaves the output");
    w = 0xEEEEEEEEu;
    CHECK(!mem_u32(RAM_BASE + RAM_SIZE - 2, &w) && w == 0xEEEEEEEEu, "a failed mem_u32 leaves the output");
    q = 0xEEEEEEEEEEEEEEEEull;
    CHECK(!mem_u64(0x10, &q) && q == 0xEEEEEEEEEEEEEEEEull, "a failed mem_u64 leaves the output");
    reset();
    CHECK(!mem_read(RAM_BASE, buf, 0), "a read of zero bytes fails");
    CHECK(!mem_read(RAM_BASE, NULL, 4), "a read into NULL fails");
    CHECK(g_reads == 0, "those two never reach the port");
    CHECK(!mem_read(UINTPTR_MAX - 1, buf, 8), "a read whose range wraps the address space fails before the port");
    CHECK(g_reads == 0, "the wrapping read never reaches the port");
}

static void test_ptr(void)
{
    uintptr_t p = 7;
    reset();
    put64(RAM_BASE + 0x00, 0);
    put64(RAM_BASE + 0x08, 0x8000);
    put64(RAM_BASE + 0x10, 0x800000000000ull);
    put64(RAM_BASE + 0x18, 0x7FFFF0001ull); /* above 0x10000, not 8-aligned */
    put64(RAM_BASE + 0x20, 0x7FFFFFFFFFF8ull);
    put64(RAM_BASE + 0x28, 0x10000);
    put64(RAM_BASE + 0x30, 0xFFF8);
    put64(RAM_BASE + 0x38, 0xFFFF800000000000ull);
    put64(RAM_BASE + 0x40, 0x7FFFFFFFFFFFull); /* the top of the range, but not 8-aligned */
    put64(RAM_BASE + 0x48, 0x000001F4A5B6C7D8ull);
    CHECK(!mem_ptr(RAM_BASE + 0x00, &p) && p == 7, "mem_ptr refuses 0 and leaves the output");
    CHECK(!mem_ptr(RAM_BASE + 0x08, &p), "mem_ptr refuses 0x8000");
    CHECK(!mem_ptr(RAM_BASE + 0x10, &p), "mem_ptr refuses 0x800000000000");
    CHECK(!mem_ptr(RAM_BASE + 0x18, &p), "mem_ptr refuses an unaligned value");
    CHECK(!mem_ptr(RAM_BASE + 0x30, &p), "mem_ptr refuses 0xFFF8, below 0x10000");
    CHECK(!mem_ptr(RAM_BASE + 0x38, &p), "mem_ptr refuses a kernel-half value");
    CHECK(!mem_ptr(RAM_BASE + 0x40, &p), "mem_ptr refuses 0x7FFFFFFFFFFF, not 8-aligned");
    CHECK(!mem_ptr(RAM_BASE + RAM_SIZE, &p), "mem_ptr fails when the read fails");
    CHECK(p == 7, "no refusal changed the output");
    CHECK(mem_ptr(RAM_BASE + 0x20, &p) && p == 0x7FFFFFFFFFF8ull, "mem_ptr accepts the highest aligned value");
    CHECK(mem_ptr(RAM_BASE + 0x28, &p) && p == 0x10000, "mem_ptr accepts 0x10000");
    CHECK(mem_ptr(RAM_BASE + 0x48, &p) && p == 0x1F4A5B6C7D8ull, "mem_ptr accepts an ordinary heap pointer");
}

/* R46 reads some data pointers with a weaker alignment (4: packed settings descriptors, code arrays, lookup slots). */
static void test_ptr_aligned(void)
{
    uintptr_t p = 7;
    reset();
    put64(RAM_BASE + 0x00, 0x1F4A5B6C7D4ull);  /* 4 mod 8 */
    put64(RAM_BASE + 0x08, 0x1F4A5B6C7D2ull);  /* 2 mod 4 */
    put64(RAM_BASE + 0x10, 0x10000);
    put64(RAM_BASE + 0x18, 0xFFFC);            /* 4-aligned, below 0x10000 */
    put64(RAM_BASE + 0x20, 0x7FFFFFFFFFFCull); /* the highest 4-aligned value */
    put64(RAM_BASE + 0x28, 0x800000000000ull);
    put64(RAM_BASE + 0x30, 0);
    put64(RAM_BASE + 0x38, 0x1F4A5B6C7D8ull);
    CHECK(mem_ptr_aligned(RAM_BASE + 0x00, &p, 4) && p == 0x1F4A5B6C7D4ull, "align 4 accepts a pointer 4 mod 8");
    p = 7;
    CHECK(!mem_ptr_aligned(RAM_BASE + 0x00, &p, 8) && p == 7, "align 8 refuses it and leaves the output");
    CHECK(!mem_ptr(RAM_BASE + 0x00, &p) && p == 7, "mem_ptr is align 8");
    CHECK(!mem_ptr_aligned(RAM_BASE + 0x08, &p, 4), "align 4 refuses a value 2 mod 4");
    CHECK(mem_ptr_aligned(RAM_BASE + 0x08, &p, 2) && p == 0x1F4A5B6C7D2ull, "align 2 accepts it");
    CHECK(mem_ptr_aligned(RAM_BASE + 0x10, &p, 4) && p == 0x10000, "align 4 accepts 0x10000");
    p = 7;
    CHECK(!mem_ptr_aligned(RAM_BASE + 0x18, &p, 4) && p == 7, "align 4 keeps the 0x10000 floor");
    CHECK(mem_ptr_aligned(RAM_BASE + 0x20, &p, 4) && p == 0x7FFFFFFFFFFCull, "align 4 accepts the highest value");
    CHECK(!mem_ptr_aligned(RAM_BASE + 0x28, &p, 4), "align 4 keeps the 0x7FFFFFFFFFFF ceiling");
    CHECK(!mem_ptr_aligned(RAM_BASE + 0x30, &p, 1), "align 1 still refuses 0");
    CHECK(mem_ptr_aligned(RAM_BASE + 0x38, &p, 8) && p == 0x1F4A5B6C7D8ull, "align 8 accepts an 8-aligned pointer");
    p = 7;
    CHECK(!mem_ptr_aligned(RAM_BASE + 0x38, &p, 0) && !mem_ptr_aligned(RAM_BASE + 0x38, &p, 3)
              && !mem_ptr_aligned(RAM_BASE + 0x38, &p, 16) && p == 7,
          "an alignment that is not 1, 2, 4 or 8 is refused");
    CHECK(!mem_ptr_aligned(RAM_BASE + RAM_SIZE, &p, 4) && p == 7, "align 4 fails when the read fails");
    CHECK(!mem_ptr_aligned(RAM_BASE, NULL, 4), "a NULL output is refused");
}

static void test_swap_and_restore(void)
{
    const uint8_t value[4] = { 0xDE, 0xAD, 0xBE, 0xEF };
    uint8_t expect[4], before[16];
    reset();
    memcpy(expect, ram_at(RAM_BASE + 0x40), 4);
    memcpy(before, ram_at(RAM_BASE + 0x38), 16);
    CHECK(mem_swap(RAM_BASE + 0x40, expect, value, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "a swap on matching bytes swaps");
    CHECK(memcmp(ram_at(RAM_BASE + 0x40), value, 4) == 0, "the new bytes are in place");
    CHECK(memcmp(ram_at(RAM_BASE + 0x38), before, 8) == 0 && memcmp(ram_at(RAM_BASE + 0x44), before + 12, 4) == 0,
          "the bytes around them are untouched");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0, "restore reports nothing left unrestored");
    CHECK(memcmp(ram_at(RAM_BASE + 0x38), before, 16) == 0, "the original bytes are back");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0 && memcmp(ram_at(RAM_BASE + 0x38), before, 16) == 0,
          "the entry is gone: a second restore does nothing");
}

static void test_swap_refusals(void)
{
    const uint8_t value[4] = { 1, 2, 3, 4 };
    uint8_t wrong[4], original[4], big[33] = { 0 };
    reset();
    memcpy(original, ram_at(RAM_BASE + 0x80), 4);
    memcpy(wrong, original, 4);
    wrong[2] ^= 0xFF;
    CHECK(mem_swap(RAM_BASE + 0x80, wrong, value, 4, MEM_OWNER_CAMERA) == MEM_DIFFERENT, "a wrong expect is MEM_DIFFERENT");
    CHECK(memcmp(ram_at(RAM_BASE + 0x80), original, 4) == 0 && g_writes == 0, "MEM_DIFFERENT wrote nothing");
    ram_at(RAM_BASE + 0x80)[0] ^= 0x01; /* a third party changes it: a journaled entry would now count as lost */
    CHECK(mem_restore(MEM_OWNER_CAMERA) == 0, "MEM_DIFFERENT journaled nothing");

    reset();
    memcpy(ram_at(RAM_BASE + 0x80), value, 4);
    CHECK(mem_swap(RAM_BASE + 0x80, original, value, 4, MEM_OWNER_ENTRY) == MEM_ALREADY, "bytes that already hold value are MEM_ALREADY");
    CHECK(g_writes == 0, "MEM_ALREADY wrote nothing");
    ram_at(RAM_BASE + 0x80)[0] ^= 0x01;
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0, "MEM_ALREADY journaled nothing");

    reset();
    CHECK(mem_swap(RAM_BASE + 0x80, original, value, 0, MEM_OWNER_LIST) == MEM_FAILED, "size 0 is MEM_FAILED");
    CHECK(mem_swap(RAM_BASE + 0x80, big, big, 33, MEM_OWNER_LIST) == MEM_FAILED, "size 33 is MEM_FAILED");
    CHECK(mem_swap(RAM_BASE + 0x80, original, value, 4, MEM_OWNER_COUNT) == MEM_FAILED, "an owner out of range is MEM_FAILED");
    CHECK(mem_swap(RAM_BASE + 0x80, NULL, value, 4, MEM_OWNER_LIST) == MEM_FAILED, "a NULL expect is MEM_FAILED");
    CHECK(mem_swap(RAM_BASE + 0x80, original, NULL, 4, MEM_OWNER_LIST) == MEM_FAILED, "a NULL value is MEM_FAILED");
    CHECK(g_writes == 0, "none of those wrote");
    CHECK(mem_swap(RAM_BASE + RAM_SIZE - 2, original, value, 4, MEM_OWNER_LIST) == MEM_FAILED, "a swap whose read fails is MEM_FAILED");
    CHECK(mem_swap(0, original, value, 4, MEM_OWNER_LIST) == MEM_FAILED, "a swap at address 0 is MEM_FAILED");
    CHECK(g_writes == 0, "a failed read wrote nothing");
}

static void test_swap_sizes(void)
{
    uint8_t expect[32], value[32], before[40];
    reset();
    memcpy(expect, ram_at(RAM_BASE + 0x100), 32);
    memset(value, 0xAB, 32);
    memcpy(before, ram_at(RAM_BASE + 0xFC), 40);
    CHECK(mem_swap(RAM_BASE + 0x100, expect, value, 32, MEM_OWNER_TERMINAL) == MEM_SWAPPED, "a 32-byte swap works");
    CHECK(memcmp(ram_at(RAM_BASE + 0x100), value, 32) == 0, "all 32 bytes are written");
    CHECK(mem_restore(MEM_OWNER_TERMINAL) == 0 && memcmp(ram_at(RAM_BASE + 0xFC), before, 40) == 0, "all 32 bytes come back");
    reset();
    CHECK(mem_swap(RAM_BASE + 0x100, expect, value, 1, MEM_OWNER_TERMINAL) == MEM_SWAPPED, "a 1-byte swap works");
    CHECK(ram_at(RAM_BASE + 0x100)[0] == 0xAB && ram_at(RAM_BASE + 0x101)[0] == expect[1], "only that byte changes");
}

static void test_owners(void)
{
    const uint8_t a_new[4] = { 0xA1, 0xA2, 0xA3, 0xA4 }, c_new[4] = { 0xC1, 0xC2, 0xC3, 0xC4 };
    uint8_t a_old[4], c_old[4];
    reset();
    memcpy(a_old, ram_at(RAM_BASE + 0x200), 4);
    memcpy(c_old, ram_at(RAM_BASE + 0x300), 4);
    CHECK(mem_swap(RAM_BASE + 0x200, a_old, a_new, 4, MEM_OWNER_LATCH) == MEM_SWAPPED, "latch swap");
    CHECK(mem_swap(RAM_BASE + 0x300, c_old, c_new, 4, MEM_OWNER_CAMERA) == MEM_SWAPPED, "camera swap");
    CHECK(mem_restore(MEM_OWNER_CAMERA) == 0, "restoring the camera owner reports 0");
    CHECK(memcmp(ram_at(RAM_BASE + 0x300), c_old, 4) == 0, "the camera entry is back");
    CHECK(memcmp(ram_at(RAM_BASE + 0x200), a_new, 4) == 0, "the latch entry is still swapped");
    CHECK(mem_restore(MEM_OWNER_CAMERA) == 0 && memcmp(ram_at(RAM_BASE + 0x200), a_new, 4) == 0, "restoring camera again leaves the latch alone");
    CHECK(mem_restore(MEM_OWNER_LATCH) == 0 && memcmp(ram_at(RAM_BASE + 0x200), a_old, 4) == 0, "the latch entry restores on its own");
}

static void test_third_party_write(void)
{
    const uint8_t value[4] = { 0x11, 0x22, 0x33, 0x44 }, theirs[4] = { 0x99, 0x98, 0x97, 0x96 };
    uint8_t original[4];
    reset();
    memcpy(original, ram_at(RAM_BASE + 0x500), 4);
    CHECK(mem_swap(RAM_BASE + 0x500, original, value, 4, MEM_OWNER_ENTRY) == MEM_SWAPPED, "swap before the third party writes");
    memcpy(ram_at(RAM_BASE + 0x500), theirs, 4);
    g_writes = 0;
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 1, "restore counts the entry whose bytes changed");
    CHECK(memcmp(ram_at(RAM_BASE + 0x500), theirs, 4) == 0 && g_writes == 0, "the third party's bytes are left, with no write");
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0, "the entry was removed anyway");
}

static void test_journal_full(void)
{
    const uint8_t value[4] = { 0x5A, 0x5A, 0x5A, 0x5A };
    uint8_t expect[4];
    uintptr_t address;
    int swapped = 0;
    reset();
    for (int i = 0; i < 64; i++) {
        address = RAM_BASE + (uintptr_t)i * 8;
        memcpy(expect, ram_at(address), 4);
        if (mem_swap(address, expect, value, 4, MEM_OWNER_LIST) == MEM_SWAPPED) swapped++;
    }
    CHECK(swapped == 64, "the first 64 swaps all succeed");
    address = RAM_BASE + 64 * 8;
    memcpy(expect, ram_at(address), 4);
    g_writes = 0;
    CHECK(mem_swap(address, expect, value, 4, MEM_OWNER_LIST) == MEM_FAILED, "the 65th swap is MEM_FAILED");
    CHECK(g_writes == 0 && memcmp(ram_at(address), expect, 4) == 0, "the 65th swap wrote nothing");
    CHECK(mem_swap(RAM_BASE, value, value, 4, MEM_OWNER_LIST) == MEM_ALREADY, "a full journal still answers MEM_ALREADY");
    CHECK(mem_swap(RAM_BASE + 7 * 8, expect, expect, 4, MEM_OWNER_LIST) == MEM_DIFFERENT, "a full journal still answers MEM_DIFFERENT");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0, "all 64 restore");
    CHECK(mem_swap(address, expect, value, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "the journal takes entries again once restored");
    CHECK(mem_restore_all() == 0 && memcmp(ram_at(address), expect, 4) == 0, "and that one restores too");
}

/* Two owners change one address in turn (LIST, then CAMERA over LIST's value): restore_all walks newest first. */
static void test_same_address_twice(void)
{
    const uint8_t one[4] = { 1, 1, 1, 1 }, three[4] = { 3, 3, 3, 3 };
    uint8_t original[4];
    reset();
    memcpy(original, ram_at(RAM_BASE + 0x600), 4);
    CHECK(mem_swap(RAM_BASE + 0x600, original, one, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "first swap of the address");
    CHECK(mem_swap(RAM_BASE + 0x600, one, three, 4, MEM_OWNER_CAMERA) == MEM_SWAPPED, "second swap of the same address, other owner");
    CHECK(mem_restore_all() == 0, "restore_all walks newest first and puts everything back");
    CHECK(memcmp(ram_at(RAM_BASE + 0x600), original, 4) == 0, "the address holds the original bytes");
}

/* The same owner swapping the same address and size again re-asserts its entry instead of adding one (the latch
 * refreshes every frame): it writes `value` only while the bytes hold the entry's original. */
static void test_reassert(void)
{
    const uint8_t value[4] = { 0x4A, 0x4B, 0x4C, 0x4D }, other[4] = { 0x5A, 0x5B, 0x5C, 0x5D };
    const uint8_t theirs[4] = { 0x99, 0x98, 0x97, 0x96 };
    uint8_t original[4], wrong[4], expect[4];
    uintptr_t at = RAM_BASE + 0x640;
    reset();
    memcpy(original, ram_at(at), 4);
    CHECK(mem_swap(at, original, value, 4, MEM_OWNER_LATCH) == MEM_SWAPPED, "re-assert: the first swap journals");
    g_writes = 0;
    CHECK(mem_swap(at, original, value, 4, MEM_OWNER_LATCH) == MEM_ALREADY && g_writes == 0,
          "re-assert: the second swap of the same address finds value there and writes nothing");
    memcpy(ram_at(at), original, 4); /* the game writes its original back */
    CHECK(mem_swap(at, original, value, 4, MEM_OWNER_LATCH) == MEM_SWAPPED && memcmp(ram_at(at), value, 4) == 0,
          "re-assert: after the game wrote the original back, the next swap writes value again");
    CHECK(mem_journal_count(MEM_OWNER_LATCH) == 1 && mem_restore(MEM_OWNER_LATCH) == 0
              && memcmp(ram_at(at), original, 4) == 0,
          "re-assert: one entry, and the original is back");
    CHECK(mem_restore(MEM_OWNER_LATCH) == 0 && memcmp(ram_at(at), original, 4) == 0, "re-assert: nothing left");

    /* The bytes hold neither the entry's original nor value. */
    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_LATCH);
    memcpy(ram_at(at), theirs, 4);
    g_writes = 0;
    CHECK(mem_swap(at, original, value, 4, MEM_OWNER_LATCH) == MEM_DIFFERENT && g_writes == 0
              && memcmp(ram_at(at), theirs, 4) == 0,
          "re-assert: a third party's bytes are MEM_DIFFERENT and left alone");
    CHECK(mem_restore(MEM_OWNER_LATCH) == 1 && memcmp(ram_at(at), theirs, 4) == 0,
          "re-assert: still one entry, which restore leaves (its bytes changed)");

    /* The entry's original decides, not `expect`. */
    reset();
    memcpy(original, ram_at(at), 4);
    memcpy(wrong, original, 4);
    wrong[0] ^= 0xFF;
    mem_swap(at, original, value, 4, MEM_OWNER_LATCH);
    memcpy(ram_at(at), original, 4);
    CHECK(mem_swap(at, wrong, value, 4, MEM_OWNER_LATCH) == MEM_SWAPPED && memcmp(ram_at(at), value, 4) == 0,
          "re-assert: compared with the entry's original, not with expect");
    memcpy(ram_at(at), wrong, 4);
    CHECK(mem_swap(at, wrong, value, 4, MEM_OWNER_LATCH) == MEM_DIFFERENT && memcmp(ram_at(at), wrong, 4) == 0,
          "re-assert: bytes equal to expect but not to the entry's original are MEM_DIFFERENT");
    CHECK(mem_restore(MEM_OWNER_LATCH) == 1, "re-assert: one entry");

    /* One owner cannot chain a second value over its own first one: it is not the entry's original. */
    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_LIST);
    CHECK(mem_swap(at, value, other, 4, MEM_OWNER_LIST) == MEM_DIFFERENT && memcmp(ram_at(at), value, 4) == 0,
          "re-assert: the same owner swapping its own value for another is MEM_DIFFERENT");
    /* While the original is there, a new value is written and becomes what the entry holds. */
    memcpy(ram_at(at), original, 4);
    CHECK(mem_swap(at, original, other, 4, MEM_OWNER_LIST) == MEM_SWAPPED && memcmp(ram_at(at), other, 4) == 0,
          "re-assert: on the original, a new value is written");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0 && memcmp(ram_at(at), original, 4) == 0,
          "re-assert: restore recognises the new value and puts the original back");

    /* A different size at the same address from the same owner is refused. */
    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_LATCH);
    memcpy(ram_at(at), original, 4);
    g_writes = 0;
    CHECK(mem_swap(at, original, value, 2, MEM_OWNER_LATCH) == MEM_FAILED && g_writes == 0
              && memcmp(ram_at(at), original, 4) == 0,
          "re-assert: the same address with another size is MEM_FAILED and writes nothing");
    CHECK(mem_journal_count(MEM_OWNER_LATCH) == 1 && mem_restore(MEM_OWNER_LATCH) == 0,
          "re-assert: the refused size added no entry (the one there holds its original: restored)");

    /* A re-assert adds no entry, so it works with a full journal. */
    reset();
    for (int i = 0; i < 64; i++) {
        uintptr_t a = RAM_BASE + (uintptr_t)i * 8;
        memcpy(expect, ram_at(a), 4);
        if (i == 5) memcpy(original, expect, 4);
        mem_swap(a, expect, value, 4, MEM_OWNER_LATCH);
    }
    memcpy(expect, ram_at(RAM_BASE + 64 * 8), 4);
    CHECK(mem_swap(RAM_BASE + 64 * 8, expect, value, 4, MEM_OWNER_LATCH) == MEM_FAILED, "re-assert: the journal is full");
    memcpy(ram_at(RAM_BASE + 5 * 8), original, 4); /* the game writes entry 5's original back */
    CHECK(mem_swap(RAM_BASE + 5 * 8, original, value, 4, MEM_OWNER_LATCH) == MEM_SWAPPED
              && memcmp(ram_at(RAM_BASE + 5 * 8), value, 4) == 0,
          "re-assert: with a full journal the owner's entry is still re-asserted");
    CHECK(mem_restore(MEM_OWNER_LATCH) == 0 && memcmp(ram_at(RAM_BASE + 5 * 8), original, 4) == 0,
          "re-assert: all 64 restore");
}

/* Two owners over one address: only newest-first restores give the original back (the order the header asks for). */
static void test_overlapping_owners(void)
{
    const uint8_t list[4] = { 0x1A, 0x1B, 0x1C, 0x1D }, camera[4] = { 0xCA, 0xCB, 0xCC, 0xCD };
    uint8_t original[4];
    uintptr_t at = RAM_BASE + 0x680;
    reset();
    memcpy(original, ram_at(at), 4);
    CHECK(mem_swap(at, original, list, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "overlap: LIST swaps first");
    CHECK(mem_swap(at, list, camera, 4, MEM_OWNER_CAMERA) == MEM_SWAPPED, "overlap: CAMERA swaps over LIST's value");
    CHECK(mem_restore(MEM_OWNER_CAMERA) == 0 && memcmp(ram_at(at), list, 4) == 0, "overlap: CAMERA first gives LIST's value");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0 && memcmp(ram_at(at), original, 4) == 0, "overlap: then LIST gives the original");

    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, list, 4, MEM_OWNER_LIST);
    mem_swap(at, list, camera, 4, MEM_OWNER_CAMERA);
    CHECK(mem_restore(MEM_OWNER_LIST) == 1 && memcmp(ram_at(at), camera, 4) == 0,
          "overlap, older owner first: LIST finds CAMERA's value and leaves it");
    CHECK(mem_restore(MEM_OWNER_CAMERA) == 0 && memcmp(ram_at(at), list, 4) == 0,
          "overlap, older owner first: CAMERA then puts back LIST's value, not the original");
}

/* mem_read refuses a range that wraps the address space before asking the port: the last 8 bytes still reach it. */
static void test_wrap_boundary(void)
{
    uint8_t buf[8];
    reset();
    CHECK(!mem_read(UINTPTR_MAX - 7, buf, 8) && g_reads == 1, "(UINTPTR_MAX-7, 8) ends at the top: it reaches the port");
    CHECK(!mem_read(UINTPTR_MAX - 6, buf, 8) && g_reads == 1, "(UINTPTR_MAX-6, 8) wraps: it never reaches the port");
    CHECK(!mem_read(UINTPTR_MAX, buf, 1) && g_reads == 2, "(UINTPTR_MAX, 1) reaches the port");
}

static void test_restore_all(void)
{
    const uint8_t value[4] = { 0x77, 0x77, 0x77, 0x77 }, theirs[4] = { 0x66, 0x66, 0x66, 0x66 };
    uint8_t first[4], second[4], third[4];
    reset();
    memcpy(first, ram_at(RAM_BASE + 0x700), 4);
    memcpy(second, ram_at(RAM_BASE + 0x710), 4);
    memcpy(third, ram_at(RAM_BASE + 0x720), 4);
    mem_swap(RAM_BASE + 0x700, first, value, 4, MEM_OWNER_LIST);
    mem_swap(RAM_BASE + 0x710, second, value, 4, MEM_OWNER_LATCH);
    mem_swap(RAM_BASE + 0x720, third, value, 4, MEM_OWNER_TERMINAL);
    memcpy(ram_at(RAM_BASE + 0x710), theirs, 4);
    CHECK(mem_restore_all() == 1, "restore_all counts the one it could not put back");
    CHECK(memcmp(ram_at(RAM_BASE + 0x700), first, 4) == 0 && memcmp(ram_at(RAM_BASE + 0x720), third, 4) == 0,
          "the others are back");
    CHECK(memcmp(ram_at(RAM_BASE + 0x710), theirs, 4) == 0, "the changed one is left");
    CHECK(mem_restore_all() == 0, "the journal is empty afterwards");
}

/* An older owner restores while a newer owner's entries stay journaled: the compaction moves the entries after it down. */
static void test_older_owner_restores_first(void)
{
    const uint8_t va[4] = { 0xA1, 0xA1, 0xA1, 0xA1 }, vb[4] = { 0xB2, 0xB2, 0xB2, 0xB2 }, vc[4] = { 0xC3, 0xC3, 0xC3, 0xC3 };
    const uint8_t vd[4] = { 0xD4, 0xD4, 0xD4, 0xD4 };
    uint8_t a[4], b[4], c[4], d[4];
    reset();
    memcpy(a, ram_at(RAM_BASE + 0xA00), 4);
    memcpy(b, ram_at(RAM_BASE + 0xA10), 4);
    memcpy(c, ram_at(RAM_BASE + 0xA20), 4);
    CHECK(mem_swap(RAM_BASE + 0xA00, a, va, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "A swaps (LIST, oldest)");
    CHECK(mem_swap(RAM_BASE + 0xA10, b, vb, 4, MEM_OWNER_CAMERA) == MEM_SWAPPED, "B swaps (CAMERA, middle)");
    CHECK(mem_swap(RAM_BASE + 0xA20, c, vc, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "C swaps (LIST, newest)");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0, "restoring LIST reports 0 while CAMERA stays journaled");
    CHECK(memcmp(ram_at(RAM_BASE + 0xA00), a, 4) == 0 && memcmp(ram_at(RAM_BASE + 0xA20), c, 4) == 0, "A and C are back");
    CHECK(memcmp(ram_at(RAM_BASE + 0xA10), vb, 4) == 0, "B is still swapped");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0 && memcmp(ram_at(RAM_BASE + 0xA10), vb, 4) == 0, "LIST has nothing left and B stays swapped");
    CHECK(mem_restore(MEM_OWNER_CAMERA) == 0, "restoring CAMERA reports 0 (B's entry survived the compaction intact)");
    CHECK(memcmp(ram_at(RAM_BASE + 0xA10), b, 4) == 0, "B is back");

    /* The oldest owner restores with three newer entries behind it, two of them from one owner. */
    reset();
    memcpy(a, ram_at(RAM_BASE + 0xA00), 4);
    memcpy(b, ram_at(RAM_BASE + 0xA10), 4);
    memcpy(c, ram_at(RAM_BASE + 0xA20), 4);
    memcpy(d, ram_at(RAM_BASE + 0xA30), 4);
    mem_swap(RAM_BASE + 0xA00, a, va, 4, MEM_OWNER_LIST);
    mem_swap(RAM_BASE + 0xA10, b, vb, 4, MEM_OWNER_CAMERA);
    mem_swap(RAM_BASE + 0xA20, c, vc, 4, MEM_OWNER_LATCH);
    mem_swap(RAM_BASE + 0xA30, d, vd, 4, MEM_OWNER_CAMERA);
    CHECK(mem_restore(MEM_OWNER_LIST) == 0 && memcmp(ram_at(RAM_BASE + 0xA00), a, 4) == 0, "the oldest entry restores first");
    CHECK(memcmp(ram_at(RAM_BASE + 0xA10), vb, 4) == 0 && memcmp(ram_at(RAM_BASE + 0xA20), vc, 4) == 0 &&
          memcmp(ram_at(RAM_BASE + 0xA30), vd, 4) == 0, "the three newer entries are untouched");
    CHECK(mem_restore(MEM_OWNER_LATCH) == 0 && memcmp(ram_at(RAM_BASE + 0xA20), c, 4) == 0, "the middle owner restores from the middle");
    CHECK(memcmp(ram_at(RAM_BASE + 0xA10), vb, 4) == 0 && memcmp(ram_at(RAM_BASE + 0xA30), vd, 4) == 0, "the two CAMERA entries are untouched");
    CHECK(mem_restore(MEM_OWNER_CAMERA) == 0, "both CAMERA entries are still journaled and restore");
    CHECK(memcmp(ram_at(RAM_BASE + 0xA10), b, 4) == 0 && memcmp(ram_at(RAM_BASE + 0xA30), d, 4) == 0, "B and D are back");
    CHECK(mem_restore_all() == 0, "the journal is empty afterwards");
}

static void test_failing_writes(void)
{
    const uint8_t value[4] = { 0x31, 0x32, 0x33, 0x34 };
    uint8_t original[4];
    reset();
    memcpy(original, ram_at(RAM_BASE + 0x800), 4);
    fail_writes(1, 0, 0);
    CHECK(mem_swap(RAM_BASE + 0x800, original, value, 4, MEM_OWNER_LIST) == MEM_FAILED, "a swap whose write fails is MEM_FAILED");
    CHECK(memcmp(ram_at(RAM_BASE + 0x800), original, 4) == 0, "and the bytes are unchanged");
    fail_writes(1, 2, 0);
    CHECK(mem_swap(RAM_BASE + 0x800, original, value, 4, MEM_OWNER_LIST) == MEM_FAILED, "a write that fails half way is MEM_FAILED");
    CHECK(memcmp(ram_at(RAM_BASE + 0x800), original, 4) == 0, "and the half-written bytes are put back");
    ram_at(RAM_BASE + 0x800)[3] ^= 0x01;
    CHECK(mem_restore(MEM_OWNER_LIST) == 0, "neither failed swap journaled anything");

    reset();
    CHECK(mem_swap(RAM_BASE + 0x800, original, value, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "swap that will be restored against a failing write");
    fail_writes(1, 0, 0);
    CHECK(mem_restore(MEM_OWNER_LIST) == 1, "a restore whose write fails counts the entry");
    CHECK(mem_journal_count(MEM_OWNER_LIST) == 1 && memcmp(ram_at(RAM_BASE + 0x800), value, 4) == 0,
          "and the entry stays journaled, the bytes still swapped");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0 && memcmp(ram_at(RAM_BASE + 0x800), original, 4) == 0
              && mem_journal_count(MEM_OWNER_LIST) == 0,
          "a later restore retries it and puts the original back");
}

/* Bytes that already hold the entry's original count as restored, with no write: while the latch holds, the game writes
 * its own value back every frame. */
static void test_restore_finds_the_original(void)
{
    const uint8_t value[4] = { 0x41, 0x42, 0x43, 0x44 };
    uint8_t original[4], other[4];
    uintptr_t at = RAM_BASE + 0xb00, at2 = RAM_BASE + 0xb10;
    reset();
    memcpy(original, ram_at(at), 4);
    memcpy(other, ram_at(at2), 4);
    CHECK(mem_swap(at, original, value, 4, MEM_OWNER_LATCH) == MEM_SWAPPED, "original back: the swap");
    memcpy(ram_at(at), original, 4); /* the game writes its original back */
    g_writes = 0;
    CHECK(mem_restore(MEM_OWNER_LATCH) == 0, "original back: counted as restored");
    CHECK(g_writes == 0 && memcmp(ram_at(at), original, 4) == 0, "original back: nothing written, the original stays");
    CHECK(mem_journal_count(MEM_OWNER_LATCH) == 0, "original back: the entry left the journal");

    reset();
    mem_swap(at, original, value, 4, MEM_OWNER_LATCH);
    mem_swap(at2, other, value, 4, MEM_OWNER_CAMERA);
    memcpy(ram_at(at), original, 4);
    g_writes = 0;
    CHECK(mem_restore_all() == 0 && g_writes == 1 && memcmp(ram_at(at), original, 4) == 0
              && memcmp(ram_at(at2), other, 4) == 0,
          "original back, restore_all: the same, and the other entry is written back");
}

/* A restore whose write fails keeps the entry for a later restore; bytes changed by someone else still leave it. */
static void test_restore_retries_a_failed_write(void)
{
    const uint8_t value[4] = { 0x51, 0x52, 0x53, 0x54 }, theirs[4] = { 0x99, 0x98, 0x97, 0x96 };
    uint8_t original[4], half[4];
    uintptr_t at = RAM_BASE + 0xc00;

    /* The write puts in two bytes before it fails: the entry takes the bytes read back. */
    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_ENTRY);
    fail_writes(1, 2, 0);
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 1 && mem_journal_count(MEM_OWNER_ENTRY) == 1,
          "half-written restore: counted, the entry kept");
    memcpy(half, original, 2);
    memcpy(half + 2, value + 2, 2);
    CHECK(memcmp(ram_at(at), half, 4) == 0, "half-written restore: two bytes of the original are in");
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0 && memcmp(ram_at(at), original, 4) == 0
              && mem_journal_count(MEM_OWNER_ENTRY) == 0,
          "half-written restore: the retry recognises the bytes read back and puts the original back");

    /* The write reports a failure but put every byte in: the original is back, so it is restored. */
    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_ENTRY);
    fail_writes(1, 4, 0);
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0 && memcmp(ram_at(at), original, 4) == 0
              && mem_journal_count(MEM_OWNER_ENTRY) == 0,
          "a failed write that put the original in anyway: restored, nothing kept");

    /* The write fails, then the game writes the original back: the retry counts it as restored. */
    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_ENTRY);
    fail_writes(1, 0, 0);
    mem_restore(MEM_OWNER_ENTRY);
    memcpy(ram_at(at), original, 4);
    g_writes = 0;
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0 && g_writes == 0 && mem_journal_count(MEM_OWNER_ENTRY) == 0,
          "failed restore, then the game's original: the retry writes nothing and counts it restored");

    /* The write fails, then someone else writes: the retry leaves their bytes and drops the entry. */
    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_ENTRY);
    fail_writes(1, 0, 0);
    mem_restore(MEM_OWNER_ENTRY);
    memcpy(ram_at(at), theirs, 4);
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 1 && memcmp(ram_at(at), theirs, 4) == 0
              && mem_journal_count(MEM_OWNER_ENTRY) == 0,
          "failed restore, then a third party: left alone, the entry dropped");

    /* restore_all keeps a failed entry too, and only that one. */
    reset();
    memcpy(original, ram_at(at), 4);
    memcpy(half, ram_at(at + 0x10), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_LATCH);
    mem_swap(at + 0x10, half, value, 4, MEM_OWNER_LIST);
    fail_writes(1, 0, 0); /* newest first: LIST's write fails, LATCH's works */
    CHECK(mem_restore_all() == 1 && mem_journal_count(MEM_OWNER_LIST) == 1 && mem_journal_count(MEM_OWNER_LATCH) == 0
              && memcmp(ram_at(at), original, 4) == 0,
          "restore_all: the failed entry stays, the other is back");
    CHECK(mem_restore_all() == 0 && memcmp(ram_at(at + 0x10), half, 4) == 0, "restore_all: the retry puts it back");

    /* Bytes that cannot be read at restore leave the journal unrestored, as before. */
    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_ENTRY);
    g_reads_fail_after = 1;
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 1 && mem_journal_count(MEM_OWNER_ENTRY) == 0,
          "unreadable at restore: counted and dropped");
    g_reads_fail_after = 0;
}

/* A write that fails and whose rollback fails too is journaled, so a later restore can retry. */
static void test_failed_rollback(void)
{
    const uint8_t value[4] = { 0x61, 0x62, 0x63, 0x64 };
    uint8_t original[4], now[4];
    uintptr_t at = RAM_BASE + 0x880;
    reset();
    memcpy(original, ram_at(at), 4);
    fail_writes(2, 2, 1); /* the write puts in 2 bytes and fails; the rollback puts back 1 and fails */
    CHECK(mem_swap(at, original, value, 4, MEM_OWNER_ENTRY) == MEM_FAILED, "failed rollback: the swap is MEM_FAILED");
    memcpy(now, original, 4);
    now[1] = value[1];
    CHECK(memcmp(ram_at(at), now, 4) == 0, "failed rollback: one byte of the write is still there");
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0 && memcmp(ram_at(at), original, 4) == 0,
          "failed rollback: journaled as the bytes read back; a restore with a working port puts the original back");

    reset();
    memcpy(original, ram_at(at), 4);
    fail_writes(2, 2, 1);
    mem_swap(at, original, value, 4, MEM_OWNER_ENTRY);
    ram_at(at)[3] ^= 0x01; /* the game changes them afterwards */
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 1 && ram_at(at)[3] == (uint8_t)(original[3] ^ 0x01),
          "failed rollback: a restore leaves bytes that changed since");

    /* The read-back fails too: journaled as holding value (the best guess). */
    reset();
    memcpy(original, ram_at(at), 4);
    fail_writes(2, 4, 0);  /* the write puts in all of value and still fails; the rollback puts in nothing */
    g_reads_fail_after = 2; /* reads fail once the rollback was tried */
    CHECK(mem_swap(at, original, value, 4, MEM_OWNER_ENTRY) == MEM_FAILED && memcmp(ram_at(at), value, 4) == 0,
          "failed rollback, failed read-back: MEM_FAILED, value in place");
    g_reads_fail_after = 0;
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0 && memcmp(ram_at(at), original, 4) == 0,
          "failed rollback, failed read-back: journaled as value, so a later restore puts the original back");

    /* The read after the failed write fails, but the rollback works: nothing is journaled. */
    reset();
    memcpy(original, ram_at(at), 4);
    fail_writes(1, 4, 0);
    g_reads_fail_after = 1;
    CHECK(mem_swap(at, original, value, 4, MEM_OWNER_ENTRY) == MEM_FAILED, "unreadable after a failed write: MEM_FAILED");
    g_reads_fail_after = 0;
    CHECK(memcmp(ram_at(at), original, 4) == 0, "unreadable after a failed write: the original is written back anyway");
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0 && g_writes == 2, "unreadable after a failed write: nothing journaled");

    /* A re-assert whose write and rollback both fail: the owner's entry takes the bytes read back. */
    reset();
    memcpy(original, ram_at(at), 4);
    mem_swap(at, original, value, 4, MEM_OWNER_LATCH);
    memcpy(ram_at(at), original, 4);
    fail_writes(2, 2, 1);
    CHECK(mem_swap(at, original, value, 4, MEM_OWNER_LATCH) == MEM_FAILED, "failed re-assert: MEM_FAILED");
    CHECK(mem_restore(MEM_OWNER_LATCH) == 0 && memcmp(ram_at(at), original, 4) == 0,
          "failed re-assert: its entry holds the bytes read back, so restore puts the original back");
}

/* mem_forget / mem_forget_all drop an owner's entries without writing (the latch, when the object it changed is no
 * longer the one it latched). */
static void test_forget(void)
{
    const uint8_t value[4] = { 0x71, 0x72, 0x73, 0x74 };
    uint8_t a[4], b[4], c[4];
    uintptr_t at = RAM_BASE + 0xd00;
    reset();
    memcpy(a, ram_at(at), 4);
    memcpy(b, ram_at(at + 0x10), 4);
    memcpy(c, ram_at(at + 0x20), 4);
    mem_swap(at, a, value, 4, MEM_OWNER_LATCH);
    mem_swap(at + 0x10, b, value, 1, MEM_OWNER_LATCH);
    mem_swap(at + 0x20, c, value, 4, MEM_OWNER_ENTRY);
    g_writes = 0;
    g_reads = 0;
    CHECK(mem_forget(MEM_OWNER_LATCH, at) && mem_journal_count(MEM_OWNER_LATCH) == 1 && g_writes == 0 && g_reads == 0,
          "forget: the owner's entry at the address leaves the journal, nothing read or written");
    CHECK(memcmp(ram_at(at), value, 4) == 0, "  the bytes stay as the mod left them");
    CHECK(!mem_forget(MEM_OWNER_LATCH, at) && !mem_forget(MEM_OWNER_LATCH, at + 0x20) && !mem_forget(MEM_OWNER_ENTRY, at + 0x10)
              && mem_journal_count(MEM_OWNER_LATCH) == 1 && mem_journal_count(MEM_OWNER_ENTRY) == 1,
          "  false for an address the owner has no entry at, and nothing else leaves");
    CHECK(mem_forget(MEM_OWNER_LATCH, at + 0x10) && mem_journal_count(MEM_OWNER_LATCH) == 0,
          "  an entry of another size goes the same way");
    CHECK(!mem_forget(MEM_OWNER_COUNT, at + 0x20) && mem_journal_count(MEM_OWNER_ENTRY) == 1, "  an owner out of range: false");
    CHECK(mem_restore(MEM_OWNER_ENTRY) == 0 && memcmp(ram_at(at + 0x20), c, 4) == 0, "  the other owner's entry still restores");

    reset();
    memcpy(a, ram_at(at), 4);
    memcpy(b, ram_at(at + 0x10), 4);
    memcpy(c, ram_at(at + 0x20), 4);
    mem_swap(at, a, value, 4, MEM_OWNER_LATCH);
    mem_swap(at + 0x10, b, value, 4, MEM_OWNER_ENTRY);
    mem_swap(at + 0x20, c, value, 4, MEM_OWNER_LATCH);
    g_writes = 0;
    CHECK(mem_forget_all(MEM_OWNER_LATCH) == 2 && mem_journal_count(MEM_OWNER_LATCH) == 0 && g_writes == 0
              && memcmp(ram_at(at), value, 4) == 0 && memcmp(ram_at(at + 0x20), value, 4) == 0,
          "forget_all: both of the owner's entries leave, nothing written");
    CHECK(mem_journal_count(MEM_OWNER_ENTRY) == 1 && mem_restore(MEM_OWNER_ENTRY) == 0
              && memcmp(ram_at(at + 0x10), b, 4) == 0,
          "  the other owner's entry (between them) is untouched and restores");
    CHECK(mem_forget_all(MEM_OWNER_LATCH) == 0 && mem_forget_all(MEM_OWNER_COUNT) == 0, "  nothing left: 0; out of range: 0");
}

static void test_init_clears_the_journal(void)
{
    const uint8_t value[4] = { 9, 9, 9, 9 };
    uint8_t original[4];
    reset();
    memcpy(original, ram_at(RAM_BASE + 0x900), 4);
    mem_swap(RAM_BASE + 0x900, original, value, 4, MEM_OWNER_LIST);
    mem_init(&FAKE_PORT);
    CHECK(mem_restore_all() == 0 && memcmp(ram_at(RAM_BASE + 0x900), value, 4) == 0, "mem_init starts an empty journal");
    mem_init(NULL);
    CHECK(!mem_u8(RAM_BASE, &original[0]), "mem_init(NULL) leaves no port");
}

/* mem_journal_count: each owner's entries, re-asserts not counted twice, restores and mem_init emptying it. */
static void test_journal_count(void)
{
    const uint8_t one[1] = { 1 }, value[4] = { 9, 8, 7, 6 };
    uint8_t zero[1], original[4], other[4];
    reset();
    CHECK(mem_journal_count(MEM_OWNER_ENTRY) == 0 && mem_journal_count(MEM_OWNER_LATCH) == 0, "an empty journal counts 0");
    memcpy(zero, ram_at(RAM_BASE + 0xa00), 1);
    memcpy(original, ram_at(RAM_BASE + 0xa10), 4);
    memcpy(other, ram_at(RAM_BASE + 0xa20), 4);
    mem_swap(RAM_BASE + 0xa00, zero, one, 1, MEM_OWNER_ENTRY);
    mem_swap(RAM_BASE + 0xa10, original, value, 4, MEM_OWNER_LATCH);
    mem_swap(RAM_BASE + 0xa20, other, value, 4, MEM_OWNER_LATCH);
    CHECK(mem_journal_count(MEM_OWNER_ENTRY) == 1 && mem_journal_count(MEM_OWNER_LATCH) == 2
              && mem_journal_count(MEM_OWNER_CAMERA) == 0,
          "each owner counts its own entries");
    memcpy(ram_at(RAM_BASE + 0xa10), original, 4);
    CHECK(mem_swap(RAM_BASE + 0xa10, original, value, 4, MEM_OWNER_LATCH) == MEM_SWAPPED
              && mem_journal_count(MEM_OWNER_LATCH) == 2,
          "a re-assert adds no entry");
    CHECK(mem_journal_count(MEM_OWNER_COUNT) == 0 && mem_journal_count((MemOwner)-1) == 0, "an owner out of range counts 0");
    mem_restore(MEM_OWNER_ENTRY);
    CHECK(mem_journal_count(MEM_OWNER_ENTRY) == 0 && mem_journal_count(MEM_OWNER_LATCH) == 2,
          "mem_restore empties that owner only");
    mem_init(&FAKE_PORT);
    CHECK(mem_journal_count(MEM_OWNER_LATCH) == 0, "mem_init empties the journal");
}

int main(void)
{
    test_before_init();
    test_reads();
    test_ptr();
    test_ptr_aligned();
    test_swap_and_restore();
    test_swap_refusals();
    test_swap_sizes();
    test_owners();
    test_third_party_write();
    test_journal_full();
    test_same_address_twice();
    test_reassert();
    test_overlapping_owners();
    test_wrap_boundary();
    test_restore_all();
    test_older_owner_restores_first();
    test_failing_writes();
    test_restore_finds_the_original();
    test_restore_retries_a_failed_write();
    test_failed_rollback();
    test_forget();
    test_init_clears_the_journal();
    test_journal_count();
    TEST_MAIN_END
}
