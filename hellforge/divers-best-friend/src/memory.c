/* memory: guarded reads and restorable writes (see memory.h). Portable C11, standard headers only. */
#include <stdint.h>
#include <string.h>
#include "memory.h"

typedef struct JournalEntry {
    uintptr_t address;
    size_t size;
    MemOwner owner;
    uint8_t original[MEM_SWAP_MAX]; /* what the game had */
    uint8_t written[MEM_SWAP_MAX];  /* what the mod put there */
} JournalEntry;

static MemPort g_port;
static JournalEntry g_journal[MEM_JOURNAL_ENTRIES]; /* oldest first */
static size_t g_count;

void mem_init(const MemPort* port)
{
    memset(&g_port, 0, sizeof g_port);
    if (port) g_port = *port;
    g_count = 0;
}

bool mem_read(uintptr_t address, void* out, size_t size)
{
    if (!g_port.read || !out || size == 0 || size - 1 > UINTPTR_MAX - address) return false;
    return g_port.read(address, out, size) == 0;
}

bool mem_u8(uintptr_t a, uint8_t* v)
{
    uint8_t x;
    if (!v || !mem_read(a, &x, sizeof x)) return false;
    *v = x;
    return true;
}

bool mem_u32(uintptr_t a, uint32_t* v)
{
    uint32_t x;
    if (!v || !mem_read(a, &x, sizeof x)) return false;
    *v = x;
    return true;
}

bool mem_u64(uintptr_t a, uint64_t* v)
{
    uint64_t x;
    if (!v || !mem_read(a, &x, sizeof x)) return false;
    *v = x;
    return true;
}

bool mem_ptr_aligned(uintptr_t a, uintptr_t* v, uintptr_t alignment)
{
    uint64_t x;
    if (alignment != 1 && alignment != 2 && alignment != 4 && alignment != 8) return false;
    if (!v || !mem_u64(a, &x)) return false;
    if (x < 0x10000 || x > 0x7FFFFFFFFFFFull || (x & (alignment - 1)) != 0) return false;
    *v = (uintptr_t)x;
    return true;
}

bool mem_ptr(uintptr_t a, uintptr_t* v)
{
    return mem_ptr_aligned(a, v, 8);
}

MemSwap mem_swap(uintptr_t address, const void* expect, const void* value, size_t size, MemOwner owner)
{
    uint8_t current[MEM_SWAP_MAX];
    JournalEntry* entry;
    if (size == 0 || size > MEM_SWAP_MAX || !expect || !value || (unsigned)owner >= (unsigned)MEM_OWNER_COUNT || !g_port.write)
        return MEM_FAILED;
    if (!mem_read(address, current, size)) return MEM_FAILED;
    if (memcmp(current, value, size) == 0) return MEM_ALREADY;
    if (memcmp(current, expect, size) != 0) return MEM_DIFFERENT;
    if (g_count >= MEM_JOURNAL_ENTRIES) return MEM_FAILED;

    if (g_port.write(address, value, size) != 0) {
        /* A write that fails may still have changed some of the bytes: put back what was there. */
        uint8_t now[MEM_SWAP_MAX];
        if (mem_read(address, now, size) && memcmp(now, current, size) != 0) (void)g_port.write(address, current, size);
        return MEM_FAILED;
    }
    entry = &g_journal[g_count++];
    entry->address = address;
    entry->size = size;
    entry->owner = owner;
    memcpy(entry->original, current, size);
    memcpy(entry->written, value, size);
    return MEM_SWAPPED;
}

/* True when the entry's original bytes are back: they are written only while the bytes still hold what the mod wrote. */
static bool put_back(const JournalEntry* entry)
{
    uint8_t now[MEM_SWAP_MAX];
    if (!mem_read(entry->address, now, entry->size) || memcmp(now, entry->written, entry->size) != 0) return false;
    return g_port.write && g_port.write(entry->address, entry->original, entry->size) == 0;
}

/* One newest-first pass; every entry it visits leaves the journal, whether it could be put back or not. */
static int restore_entries(bool every_owner, MemOwner owner)
{
    int not_restored = 0;
    size_t i = g_count;
    while (i > 0) {
        i--;
        if (!every_owner && g_journal[i].owner != owner) continue;
        if (!put_back(&g_journal[i])) not_restored++;
        memmove(&g_journal[i], &g_journal[i + 1], (g_count - i - 1) * sizeof g_journal[0]);
        g_count--;
    }
    return not_restored;
}

int mem_restore(MemOwner owner)
{
    return restore_entries(false, owner);
}

int mem_restore_all(void)
{
    return restore_entries(true, MEM_OWNER_LIST);
}
