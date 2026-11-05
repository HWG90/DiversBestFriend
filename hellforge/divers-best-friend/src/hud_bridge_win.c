#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <limits.h>
#include <string.h>
#include "hud_bridge.h"
#include "hud_options.h"
#include "logic.h"
#include "snapshot.h"
#include "codes.h"
#include "memory.h"

#define HUD_EXPORT __declspec(dllexport)
static SRWLOCK lock = SRWLOCK_INIT;
static uintptr_t image;
static size_t image_size;
static HudBridgePort port;
static bool verified, granted, terminal_active;
static const void* claimant;
static DbfSettings options;
static int levels = -1;
static char last_message[192];

/* Retained until the next C tick. Publish only the current HUD's validated
 * definitions and codes; the Lua VM never races codes_read's per-pass state. */
typedef struct HudRow {
    uintptr_t definition;
    uint32_t kind, code_kind;
    uint8_t length, directions[DBF_CODE_CAPACITY];
} HudRow;
/* Equipped entries without cards have definition zero: code lookup may use
 * them, while row lookup still admits only a stock HUD card. */
#define HUD_ENTRIES (DBF_VAL_CARD_COUNT + DBF_VAL_SLOT_MAX)
static HudRow rows[HUD_ENTRIES];
static unsigned row_count;

void hud_bridge_init(uintptr_t base, size_t size, const HudBridgePort* api)
{
    AcquireSRWLockExclusive(&lock);
    image = base;
    image_size = size;
    port = *api;
    ReleaseSRWLockExclusive(&lock);
}

HUD_EXPORT uint64_t dbf_hud_base(void)
{
    AcquireSRWLockShared(&lock);
    uintptr_t base = verified ? image : 0;
    ReleaseSRWLockShared(&lock);
    return base;
}

HUD_EXPORT int dbf_hud_read(uint64_t address, void* out, unsigned bytes)
{
    return dbf_hud_base() && address >= 65536 && out && bytes && bytes <= 65536 &&
           address < UINT64_C(0x800000000000) - bytes && port.read(address, out, bytes) == 0;
}

/* Compare the pre-hook bytes from the loader. A mismatching range is only
 * admissible for the individual bytes HellForge reports it rewrote. */
HUD_EXPORT int dbf_hud_guard(unsigned rva, const void* expected, unsigned length)
{
    unsigned char actual[256];
    uintptr_t base = dbf_hud_base();
    if (!base || !expected || !length || length > sizeof actual || length > image_size ||
        rva > image_size - length || port.read_code(base + rva, actual, length) != 0) return 0;
    if (!memcmp(actual, expected, length)) return 1;
    if (!port.rewrites || !port.rewrites(rva, length)) return 0;
    for (unsigned i = 0; i < length; ++i)
        if (actual[i] != ((const unsigned char*)expected)[i] && !port.rewrites(rva + i, 1)) return 0;
    return 1;
}

HUD_EXPORT int dbf_hud_acquire(const void* token)
{
    AcquireSRWLockExclusive(&lock);
    if (token && verified && !claimant) claimant = token;
    int result = token && claimant == token && granted;
    ReleaseSRWLockExclusive(&lock);
    return result;
}

HUD_EXPORT void dbf_hud_release(const void* token)
{
    AcquireSRWLockExclusive(&lock);
    if (claimant == token) {
        granted = false;
        claimant = NULL;
        levels = -1;
        terminal_active = false;
        row_count = 0;
    }
    ReleaseSRWLockExclusive(&lock);
}

bool hud_bridge_requested(void)
{
    AcquireSRWLockShared(&lock);
    bool result = claimant != NULL;
    ReleaseSRWLockShared(&lock);
    return result;
}

bool hud_bridge_owned(void)
{
    AcquireSRWLockShared(&lock);
    bool result = granted;
    ReleaseSRWLockShared(&lock);
    return result;
}

static unsigned append_equipped(HudRow* current, unsigned count, const GameLocal* local)
{
    uint32_t entries;
    if (!mem_u32(local->payload + DBF_OFF_PAYLOAD_COUNT_OFFSET, &entries)
        || entries < DBF_VAL_PAYLOAD_SLOTS_MIN || entries > DBF_VAL_PAYLOAD_ENTRY_MAX) return count;
    for (unsigned slot = DBF_VAL_SLOT_MIN; slot <= DBF_VAL_SLOT_MAX; ++slot) {
        uintptr_t index = slot + DBF_VAL_PAYLOAD_SLOT_BASE;
        uint32_t kind;
        if (!mem_u32(local->payload + DBF_OFF_PAYLOAD_KINDS_OFFSET + index * DBF_OFF_PAYLOAD_ENTRY_STRIDE, &kind)
            || !kind) continue;
        unsigned i = 0;
        while (i < count && current[i].kind != kind) ++i;
        if (i < count) continue;
        DbfCode code;
        if (!codes_read(kind, local, &code, NULL, 0)) continue;
        HudRow* out = &current[count++];
        *out = (HudRow){ .kind = kind, .code_kind = code.kind_used, .length = code.len };
        memcpy(out->directions, code.dir, code.len);
    }
    return count;
}

void hud_bridge_publish(const GameView* v, const DbfSettings* s, int buttons, bool terminal_allowed,
                        bool build_ok, bool can_grant)
{
    HudRow current[HUD_ENTRIES];
    unsigned count = 0;
    if (build_ok && hud_bridge_requested() && v->local_ok && v->hud_ready && v->in_gameplay) {
        for (int i = 0; i < v->row_count && i < (int)DBF_VAL_CARD_COUNT; ++i) {
            const DbfRow* row = &v->rows[i];
            if (!row->active || !row->kind || row->code_len > DBF_CODE_CAPACITY) continue;
            HudRow* out = &current[count++];
            out->definition = codes_definition(row->kind);
            out->kind = row->kind;
            out->code_kind = row->code_kind;
            out->length = row->code_len;
            memcpy(out->directions, row->code, out->length);
        }
        if (v->table_rva) count = append_equipped(current, count, &v->local);
        /* An equipped-only code can reveal a shared loader array after the
         * active row was read. Withdraw both before publishing this tick. */
        for (unsigned i = 0; i < count; ++i)
            if (codes_shared(current[i].code_kind)) current[i].length = 0;
    }
    AcquireSRWLockExclusive(&lock);
    verified = build_ok;
    options = *s;
    row_count = count;
    memcpy(rows, current, count * sizeof *current);
    levels = buttons;
    terminal_active = terminal_allowed;
    if (claimant && can_grant && verified) granted = true;
    ReleaseSRWLockExclusive(&lock);
}

HUD_EXPORT int dbf_hud_option(const char* key)
{
    AcquireSRWLockShared(&lock);
    int value = verified && key ? hud_option_get(&options, key) : INT_MIN;
    ReleaseSRWLockShared(&lock);
    return value;
}

HUD_EXPORT int dbf_hud_blacklisted(unsigned kind)
{
    AcquireSRWLockShared(&lock);
    int hidden = logic_blacklisted(kind, &options);
    ReleaseSRWLockShared(&lock);
    return hidden;
}

/* 1 bound, 0 explicitly unbound, -1 while the companion is waiting. */
HUD_EXPORT int dbf_hud_bound(unsigned action)
{
    AcquireSRWLockShared(&lock);
    int value = granted && action < BIND_COUNT ? options.bind[action].kind != BIND_NONE : -1;
    ReleaseSRWLockShared(&lock);
    return value;
}

HUD_EXPORT int dbf_hud_terminal_active(const void* token)
{
    AcquireSRWLockShared(&lock);
    int active = token && claimant == token && granted && verified && terminal_active;
    ReleaseSRWLockShared(&lock);
    return active;
}

HUD_EXPORT int dbf_hud_buttons(void)
{
    AcquireSRWLockShared(&lock);
    int value = granted ? levels : -1;
    ReleaseSRWLockShared(&lock);
    return value;
}

static const HudRow* find_row(unsigned kind)
{
    if (granted)
        for (unsigned i = 0; i < row_count; ++i)
            if (rows[i].kind == kind) return &rows[i];
    return NULL;
}

HUD_EXPORT uint64_t dbf_hud_row(unsigned kind)
{
    AcquireSRWLockShared(&lock);
    const HudRow* row = find_row(kind);
    uintptr_t value = row ? row->definition : 0;
    ReleaseSRWLockShared(&lock);
    return value;
}

HUD_EXPORT int dbf_hud_code(unsigned kind, unsigned char* dirs, unsigned capacity)
{
    AcquireSRWLockShared(&lock);
    const HudRow* row = find_row(kind);
    int length = row && dirs && row->length <= capacity ? row->length : 0;
    if (length) memcpy(dirs, row->directions, length);
    ReleaseSRWLockShared(&lock);
    return length;
}

HUD_EXPORT void dbf_hud_log(const char* line)
{
    if (!line || !dbf_hud_base()) return;
    AcquireSRWLockExclusive(&lock);
    snap_copy_text(last_message, sizeof last_message, line);
    ReleaseSRWLockExclusive(&lock);
    if (port.log) port.log(line);
}

void hud_bridge_status(char* out, size_t size)
{
    AcquireSRWLockShared(&lock);
    snap_copy_text(out, size, last_message);
    ReleaseSRWLockShared(&lock);
}
#endif
