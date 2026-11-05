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
static size_t g_partial_bytes; /* how many bytes a failing write still puts in before it fails */

static int in_ram(uintptr_t address, size_t size)
{
    return address >= RAM_BASE && size <= RAM_SIZE && address - RAM_BASE <= RAM_SIZE - size;
}

static int fake_read(uintptr_t address, void* out, size_t size)
{
    g_reads++;
    if (!in_ram(address, size)) return -1;
    memcpy(out, &g_ram[address - RAM_BASE], size);
    return 0;
}

static int fake_write(uintptr_t address, const void* data, size_t size)
{
    g_writes++;
    if (!in_ram(address, size)) return -1;
    if (g_fail_next_writes > 0) {
        g_fail_next_writes--;
        memcpy(&g_ram[address - RAM_BASE], data, g_partial_bytes < size ? g_partial_bytes : size);
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
    mem_init(&FAKE_PORT);
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

static void test_same_address_twice(void)
{
    const uint8_t one[4] = { 1, 1, 1, 1 }, two[4] = { 2, 2, 2, 2 }, three[4] = { 3, 3, 3, 3 };
    uint8_t original[4];
    reset();
    memcpy(original, ram_at(RAM_BASE + 0x600), 4);
    CHECK(mem_swap(RAM_BASE + 0x600, original, one, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "first swap of the address");
    CHECK(mem_swap(RAM_BASE + 0x600, one, two, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "second swap of the same address, same owner");
    CHECK(mem_swap(RAM_BASE + 0x600, two, three, 4, MEM_OWNER_CAMERA) == MEM_SWAPPED, "third swap of the same address, other owner");
    CHECK(mem_restore_all() == 0, "restore_all walks newest first and puts everything back");
    CHECK(memcmp(ram_at(RAM_BASE + 0x600), original, 4) == 0, "the address holds the original bytes");
    CHECK(mem_swap(RAM_BASE + 0x600, original, one, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "chain again for the one-owner case");
    CHECK(mem_swap(RAM_BASE + 0x600, one, two, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "chain, second link");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0 && memcmp(ram_at(RAM_BASE + 0x600), original, 4) == 0, "one owner restores a chain newest first");
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

static void test_failing_writes(void)
{
    const uint8_t value[4] = { 0x31, 0x32, 0x33, 0x34 };
    uint8_t original[4];
    reset();
    memcpy(original, ram_at(RAM_BASE + 0x800), 4);
    g_fail_next_writes = 1;
    g_partial_bytes = 0;
    CHECK(mem_swap(RAM_BASE + 0x800, original, value, 4, MEM_OWNER_LIST) == MEM_FAILED, "a swap whose write fails is MEM_FAILED");
    CHECK(memcmp(ram_at(RAM_BASE + 0x800), original, 4) == 0, "and the bytes are unchanged");
    g_fail_next_writes = 1;
    g_partial_bytes = 2;
    CHECK(mem_swap(RAM_BASE + 0x800, original, value, 4, MEM_OWNER_LIST) == MEM_FAILED, "a write that fails half way is MEM_FAILED");
    CHECK(memcmp(ram_at(RAM_BASE + 0x800), original, 4) == 0, "and the half-written bytes are put back");
    ram_at(RAM_BASE + 0x800)[3] ^= 0x01;
    CHECK(mem_restore(MEM_OWNER_LIST) == 0, "neither failed swap journaled anything");

    reset();
    CHECK(mem_swap(RAM_BASE + 0x800, original, value, 4, MEM_OWNER_LIST) == MEM_SWAPPED, "swap that will be restored against a failing write");
    g_fail_next_writes = 1;
    CHECK(mem_restore(MEM_OWNER_LIST) == 1, "a restore whose write fails counts the entry");
    CHECK(mem_restore(MEM_OWNER_LIST) == 0, "and the entry is gone");
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

int main(void)
{
    test_before_init();
    test_reads();
    test_ptr();
    test_swap_and_restore();
    test_swap_refusals();
    test_swap_sizes();
    test_owners();
    test_third_party_write();
    test_journal_full();
    test_same_address_twice();
    test_restore_all();
    test_failing_writes();
    test_init_clears_the_journal();
    TEST_MAIN_END
}
