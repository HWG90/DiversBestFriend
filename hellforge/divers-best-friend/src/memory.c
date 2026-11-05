/* memory: guarded reads and restorable writes (see memory.h). Portable C11, standard headers only. */
#include <stdint.h>
#include <string.h>
#include "memory.h"

typedef struct JournalEntry {
    uintptr_t address;
    size_t size;
    MemOwner owner;
    uint8_t original[MEM_SWAP_MAX]; /* what the game had */
    uint8_t written[MEM_SWAP_MAX];  /* what the mod left there (a failed write: what it read back, see mem_swap) */
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

/* The owner's entry for `address`, or NULL. An owner has at most one entry per address (mem_swap re-asserts it). */
static JournalEntry* owner_entry(uintptr_t address, MemOwner owner)
{
    for (size_t i = 0; i < g_count; i++)
        if (g_journal[i].owner == owner && g_journal[i].address == address) return &g_journal[i];
    return NULL;
}

/* The write of `value` failed with `before` there before it. Puts `before` back when the bytes may have changed; when
 * that fails too, returns true with `now` set to what to journal as written: the bytes read back, or `value` when they
 * cannot be read. False when nothing needs journaling (the bytes are known to be `before` again). */
static bool roll_back(uintptr_t address, const uint8_t* before, const void* value, size_t size, uint8_t* now)
{
    if (mem_read(address, now, size) && memcmp(now, before, size) == 0) return false; /* nothing changed */
    if (g_port.write(address, before, size) == 0) return false;                       /* put back */
    if (!mem_read(address, now, size)) {
        memcpy(now, value, size); /* the best guess: what the failed write meant to leave */
        return true;
    }
    return memcmp(now, before, size) != 0;
}

/* A new entry for `owner` with `original`; the caller checked there is room and fills in `written`. */
static JournalEntry* add_entry(uintptr_t address, size_t size, MemOwner owner, const uint8_t* original)
{
    JournalEntry* entry = &g_journal[g_count++];
    entry->address = address;
    entry->size = size;
    entry->owner = owner;
    memcpy(entry->original, original, size);
    return entry;
}

MemSwap mem_swap(uintptr_t address, const void* expect, const void* value, size_t size, MemOwner owner)
{
    uint8_t current[MEM_SWAP_MAX], now[MEM_SWAP_MAX];
    JournalEntry* entry;
    if (size == 0 || size > MEM_SWAP_MAX || !expect || !value || (unsigned)owner >= (unsigned)MEM_OWNER_COUNT || !g_port.write)
        return MEM_FAILED;
    entry = owner_entry(address, owner); /* set: this is a re-assert */
    if (entry && entry->size != size) return MEM_FAILED;
    if (!mem_read(address, current, size)) return MEM_FAILED;
    if (memcmp(current, value, size) == 0) return MEM_ALREADY;
    if (memcmp(current, entry ? entry->original : expect, size) != 0) return MEM_DIFFERENT;
    if (!entry && g_count >= MEM_JOURNAL_ENTRIES) return MEM_FAILED;

    if (g_port.write(address, value, size) != 0) {
        /* The rollback failed too: journal what is there now, so a later restore can retry. */
        if (roll_back(address, current, value, size, now)) {
            if (!entry) entry = add_entry(address, size, owner, current);
            memcpy(entry->written, now, size);
        }
        return MEM_FAILED;
    }
    if (!entry) entry = add_entry(address, size, owner, current);
    memcpy(entry->written, value, size);
    return MEM_SWAPPED;
}

/* Drops journal entry i, keeping the others in order. */
static void drop(size_t i)
{
    memmove(&g_journal[i], &g_journal[i + 1], (g_count - i - 1) * sizeof g_journal[0]);
    g_count--;
}

typedef enum { PUT_BACK, PUT_GONE, PUT_RETRY } PutBack;

/* Puts one entry's original back (see mem_restore): PUT_BACK when the original is there now (already, or written),
 * PUT_GONE when the bytes cannot be read or are someone else's (neither the original nor what the entry holds), and
 * PUT_RETRY when the write failed; the entry then takes the bytes read back as what it holds, so a write that changed
 * some of them is still recognised by the retry. */
static PutBack put_back(JournalEntry* entry)
{
    uint8_t now[MEM_SWAP_MAX];
    if (!mem_read(entry->address, now, entry->size)) return PUT_GONE;
    if (memcmp(now, entry->original, entry->size) == 0) return PUT_BACK; /* the game wrote its own value back */
    if (memcmp(now, entry->written, entry->size) != 0) return PUT_GONE;
    if (g_port.write && g_port.write(entry->address, entry->original, entry->size) == 0) return PUT_BACK;
    if (mem_read(entry->address, now, entry->size)) {
        if (memcmp(now, entry->original, entry->size) == 0) return PUT_BACK;
        memcpy(entry->written, now, entry->size);
    }
    return PUT_RETRY;
}

/* One newest-first pass; every entry it visits leaves the journal, except one whose write failed (it stays for a later
 * restore to retry). */
static int restore_entries(bool every_owner, MemOwner owner)
{
    int not_restored = 0;
    size_t i = g_count;
    while (i > 0) {
        PutBack result;
        i--;
        if (!every_owner && g_journal[i].owner != owner) continue;
        result = put_back(&g_journal[i]);
        if (result != PUT_BACK) not_restored++;
        if (result == PUT_RETRY) continue;
        drop(i);
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

bool mem_forget(MemOwner owner, uintptr_t address)
{
    for (size_t i = 0; i < g_count; i++) {
        if (g_journal[i].owner != owner || g_journal[i].address != address) continue;
        drop(i);
        return true;
    }
    return false;
}

int mem_forget_all(MemOwner owner)
{
    int dropped = 0;
    size_t i = g_count;
    while (i > 0) {
        i--;
        if (g_journal[i].owner != owner) continue;
        drop(i);
        dropped++;
    }
    return dropped;
}

int mem_journal_count(MemOwner owner)
{
    int n = 0;
    for (size_t i = 0; i < g_count; i++) n += g_journal[i].owner == owner;
    return n;
}
