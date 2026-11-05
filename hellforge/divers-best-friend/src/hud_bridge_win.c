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

#define HUD_EXPORT __declspec(dllexport)
static SRWLOCK lock = SRWLOCK_INIT;
static uintptr_t image;
static size_t image_size;
static HudBridgePort port;
static bool verified, granted;
static const void* claimant;
static DbfSettings options;
static int levels = -1;
static char last_message[192];

/* Retained until the next C tick. Publish only the current HUD's validated
 * definitions and codes; the Lua VM never races codes_read's per-pass state. */
typedef struct HudRow {
    uintptr_t definition;
    uint32_t kind;
    uint8_t length, directions[DBF_CODE_CAPACITY];
} HudRow;
static HudRow rows[DBF_VAL_CARD_COUNT];
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

void hud_bridge_publish(const GameView* v, const DbfSettings* s, int buttons, bool build_ok, bool can_grant)
{
    HudRow current[DBF_VAL_CARD_COUNT];
    unsigned count = 0;
    if (build_ok && hud_bridge_requested() && v->local_ok && v->hud_ready && v->in_gameplay) {
        for (int i = 0; i < v->row_count && i < (int)DBF_VAL_CARD_COUNT; ++i) {
            const DbfRow* row = &v->rows[i];
            if (!row->active || !row->kind || row->code_len > DBF_CODE_CAPACITY) continue;
            HudRow* out = &current[count++];
            out->definition = codes_definition(row->kind);
            out->kind = row->kind;
            out->length = row->code_len;
            memcpy(out->directions, row->code, out->length);
        }
    }
    AcquireSRWLockExclusive(&lock);
    verified = build_ok;
    options = *s;
    row_count = count;
    memcpy(rows, current, count * sizeof *current);
    levels = buttons;
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
