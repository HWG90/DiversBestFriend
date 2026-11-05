/* latch: the Hold->Press lease of the menu binding and the slot hotkeys (see latch.h), ported from R46's menu_latch.lua
 * (9-87), input.lua (283-395) and release.lua (13-55). Portable C11: standard headers, memory.h, admission.h, native.h,
 * codes.h, game.h, entry.h and the generated address header only. Every game number is a DBF_OFF_* / DBF_VAL_* of that
 * header, with its R46 line there; the bucket's key, a record's flags and the local menu action's byte are the
 * u32 / u8 at the object itself (+0: menu_latch.lua:16 and 68, input.lua:289). SHORTCUT_FINISH_MS is R46's tuning
 * (below). */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "codes.h"
#include "entry.h"
#include "game.h"
#include "latch.h"
#include "memory.h"
#include "native.h"

/* R46 release.lua:51: once the code is in, the game has this long to close the menu before the shortcut gives up. */
#define SHORTCUT_FINISH_MS 2000u

#define RECORD_SIZE DBF_OFF_BINDING_ENTRY_SIZE

_Static_assert(DBF_OFF_BINDING_ENTRY_SIZE <= MEM_SWAP_MAX, "a binding record is swapped whole");
_Static_assert(DBF_OFF_BINDING_BUCKET_ENTRIES_OFFSET + DBF_VAL_BINDING_COUNT_MAX * DBF_OFF_BINDING_ENTRY_SIZE
                   <= DBF_OFF_BINDING_BUCKET_STRIDE,
               "a bucket's records end inside the bucket");
_Static_assert(DBF_OFF_BINDING_ENTRY_TRIGGER_OFFSET + 4 <= DBF_OFF_BINDING_ENTRY_SIZE,
               "the trigger is inside a record");
_Static_assert(DBF_VAL_SLOT_MAX + DBF_VAL_PAYLOAD_SLOT_BASE < DBF_VAL_PAYLOAD_SLOTS_MIN,
               "every equipped slot's entry is below the payload count required");

/* The lease (menu_latch.lua:23-25: the controls, the actions, the records it patched). Kept until its last journal
 * entry is gone, so a release that retries an entry still knows whose it was. */
static struct {
    bool held;
    uintptr_t controls, actions;
    uintptr_t manager, component; /* the player it was taken for */
    uint32_t key;
    uintptr_t table, bucket; /* the bucket table and Display Stratagem List's bucket in it */
    int entries;             /* the LATCH journal entries it made */
    bool unreadable_logged;  /* a release found the controls pointer unreadable and said so */
    uint32_t records;
    uint32_t index[DBF_VAL_BINDING_COUNT_MAX];
    uint8_t original[DBF_VAL_BINDING_COUNT_MAX][RECORD_SIZE];
    uint8_t patched[DBF_VAL_BINDING_COUNT_MAX][RECORD_SIZE];
} g_latch;

/* The active shortcut (R46 release.lua's job for it). */
static struct {
    bool active;
    bool opened;     /* DBF opened the menu (input.lua:317-322) */
    bool finishing;  /* the job is done: waiting for the game to close the menu */
    uint64_t finish_by;
    uintptr_t manager, component, avatar;
    uint32_t key;
} g_shortcut;

static uintptr_t g_base;               /* game.dll: the controls pointer is at + DBF_RVA_CONTROLS */
static void (*g_log)(const char* line); /* NULL: no log */

static const uint32_t PRESS = DBF_VAL_TRIGGER_PRESS;

/* --- reasons --------------------------------------------------------------------------------------------------- */

/* Writes "a b" to out (cut to n); false, for `return say(...)`. */
static bool say(char* out, size_t n, const char* a, const char* b)
{
    size_t at = 0;
    if (!out || n == 0) return false;
    for (const char* p = a; p && *p && at + 1 < n; p++) out[at++] = *p;
    for (const char* p = b; p && *p && at + 1 < n; p++) out[at++] = *p;
    out[at] = '\0';
    return false;
}

/* Feature `f` admitted; else the reason is "<feature name>: <admission's reason>", as game_read and entry word it. */
static bool admitted(Feature f, char* out, size_t n)
{
    const char* why = NULL;
    char name[48];
    size_t at = 0;
    if (adm_feature(f, &why) == ADMIT_OK) return true;
    for (const char* p = adm_feature_name(f); *p && at < sizeof name - 3; p++) name[at++] = *p;
    name[at++] = ':';
    name[at++] = ' ';
    name[at] = '\0';
    return say(out, n, name, why && *why ? why : "not admitted");
}

static void log_line(const char* line)
{
    if (g_log) g_log(line);
}

/* --- the lease ------------------------------------------------------------------------------------------------- */

/* The controls object the game points at now (R46 menu_latch.lua:10, 27: b.pointer(base + 0x347cf18)). */
static bool controls_now(uintptr_t* controls)
{
    return g_base != 0 && mem_ptr(g_base + DBF_RVA_CONTROLS, controls);
}

/* `l` is the player the latch was taken for. */
static bool latch_player(const GameLocal* l)
{
    return l && l->manager == g_latch.manager && l->key == g_latch.key && l->component == g_latch.component;
}

static uint32_t le32(const uint8_t* p)
{
    uint32_t v;
    memcpy(&v, p, sizeof v);
    return v;
}

static bool hold_trigger(uint32_t trigger)
{
    return trigger == DBF_VAL_TRIGGER_HOLD || trigger == DBF_VAL_TRIGGER_LONG_HOLD;
}

/* The two evaluated trigger dwords (menu_latch.lua:53): the controls' menu action's and the local player's. */
static void trigger_dwords(uintptr_t controls, uintptr_t actions, uintptr_t out[2])
{
    out[0] = controls + DBF_OFF_CONTROLS_MENU_TRIGGER_OFFSET;
    out[1] = actions + DBF_OFF_ACTION_TRIGGER_OFFSET;
}

/* Display Stratagem List's bucket (menu_latch.lua:9-22): the table, the bucket and its record count. */
static bool find_bucket(uintptr_t controls, uintptr_t* table, uintptr_t* bucket, uint32_t* count, char* out, size_t n)
{
    uintptr_t map = controls + DBF_OFF_BINDING_MAP_OFFSET;
    uint32_t capacity, key;
    if (!mem_u32(map + DBF_OFF_BINDING_MAP_CAPACITY_OFFSET, &capacity))
        return say(out, n, "menu bindings unreadable", NULL);
    if (capacity != DBF_VAL_BINDING_MAP_CAPACITY) return say(out, n, "menu binding map unrecognised", NULL);
    if (!mem_ptr(map, table)) return say(out, n, "menu bindings unreadable", NULL);
    for (uint32_t i = 0; i < DBF_VAL_BINDING_MAP_CAPACITY; i++) {
        uintptr_t at = *table + (uintptr_t)i * DBF_OFF_BINDING_BUCKET_STRIDE;
        if (!mem_u32(at, &key)) return say(out, n, "menu bindings unreadable", NULL);
        if (key != DBF_VAL_BINDING_MENU_KEY) continue;
        if (!mem_u32(at + DBF_OFF_BINDING_BUCKET_COUNT_OFFSET, count))
            return say(out, n, "menu bindings unreadable", NULL);
        if (*count > DBF_VAL_BINDING_COUNT_MAX) return say(out, n, "invalid menu bindings", NULL);
        *bucket = at;
        return true;
    }
    return say(out, n, "menu binding missing", NULL);
}

static uintptr_t record_at(uintptr_t bucket, uint32_t index)
{
    return bucket + DBF_OFF_BINDING_BUCKET_ENTRIES_OFFSET + (uintptr_t)index * RECORD_SIZE;
}

/* A trigger dword's value, which must be Press, Hold or LongHold (menu_latch.lua:54-55). */
static bool read_trigger(uintptr_t at, uint32_t* value, char* out, size_t n)
{
    if (!mem_u32(at, value)) return say(out, n, "menu trigger unreadable", NULL);
    if (*value != PRESS && !hold_trigger(*value)) return say(out, n, "unexpected menu trigger state", NULL);
    return true;
}

/* Puts back what acquire swapped (the same tick, the same objects); false with `why`, for `return undo(...)`. */
static bool undo(char* out, size_t n, const char* why)
{
    (void)latch_release(true);
    return say(out, n, why, NULL);
}

void latch_init(uintptr_t game_dll, void (*log)(const char* line))
{
    memset(&g_latch, 0, sizeof g_latch);
    memset(&g_shortcut, 0, sizeof g_shortcut);
    g_base = game_dll;
    g_log = log;
}

bool latch_acquire(const GameLocal* l, char* reason, size_t n)
{
    uintptr_t table, bucket, dword[2], controls;
    uint32_t count, records = 0, value[2];
    uint8_t action;
    say(reason, n, "", NULL);
    if (g_latch.held) return say(reason, n, "menu latch already held", NULL);
    /* An earlier release that could not write everything back: retry it before anything new is changed. */
    if (mem_journal_count(MEM_OWNER_LATCH) > 0) (void)latch_release(latch_player(l));
    if (mem_journal_count(MEM_OWNER_LATCH) > 0) return say(reason, n, "the last menu latch is not restored yet", NULL);
    if (!admitted(FEAT_LATCH, reason, n)) return false;
    if (!l) return say(reason, n, "local player unavailable", NULL);
    if (l->controls == 0 || !controls_now(&controls)) return say(reason, n, "controls unreadable", NULL);
    if (controls != l->controls) return say(reason, n, "controls changed", NULL);
    if (!l->unobstructed) return say(reason, n, "UI obstructed", NULL);
    /* input.lua:314-315: the controls' menu action byte. */
    if (!mem_u8(l->controls + DBF_OFF_CONTROLS_MENU_ACTION_OFFSET, &action))
        return say(reason, n, "menu action unreadable", NULL);
    if (action != DBF_VAL_ACTION_RELEASED && action != DBF_VAL_ACTION_PRESSED)
        return say(reason, n, "invalid menu action", NULL);
    if (!find_bucket(l->controls, &table, &bucket, &count, reason, n)) return false;

    /* Every Hold / LongHold record and its Press form (menu_latch.lua:64-74), all checked before anything is
     * written. */
    for (uint32_t i = 0; i < count; i++) {
        uint8_t* original = g_latch.original[records];
        uint8_t* patched = g_latch.patched[records];
        uint32_t flags, trigger, format, field;
        if (!mem_read(record_at(bucket, i), original, RECORD_SIZE))
            return say(reason, n, "menu bindings unreadable", NULL);
        flags = le32(original);
        trigger = le32(original + DBF_OFF_BINDING_ENTRY_TRIGGER_OFFSET);
        if (!hold_trigger(trigger)) continue;
        format = flags / DBF_VAL_BINDING_FLAGS_FORMAT_DIVISOR % DBF_VAL_BINDING_FLAGS_FIELD_MODULUS;
        field = flags / DBF_VAL_BINDING_FLAGS_TRIGGER_DIVISOR % DBF_VAL_BINDING_FLAGS_FIELD_MODULUS;
        if (format != DBF_VAL_BINDING_FLAGS_FORMAT || field != trigger)
            return say(reason, n, "unexpected Hold binding format", NULL);
        flags -= trigger * DBF_VAL_BINDING_FLAGS_TRIGGER_DIVISOR;
        memcpy(patched, original, RECORD_SIZE);
        memcpy(patched, &flags, sizeof flags);
        memcpy(patched + DBF_OFF_BINDING_ENTRY_TRIGGER_OFFSET, &PRESS, sizeof PRESS);
        g_latch.index[records++] = i;
    }
    if (records == 0) return say(reason, n, "no Hold mapping", NULL);
    trigger_dwords(l->controls, l->actions, dword);
    for (int d = 0; d < 2; d++)
        if (!read_trigger(dword[d], &value[d], reason, n)) return false;

    /* The writes (menu_latch.lua:73, 58), each restorable. */
    g_latch.controls = l->controls;
    g_latch.actions = l->actions;
    g_latch.manager = l->manager;
    g_latch.component = l->component;
    g_latch.key = l->key;
    g_latch.table = table;
    g_latch.bucket = bucket;
    g_latch.records = records;
    for (uint32_t r = 0; r < records; r++)
        if (mem_swap(record_at(bucket, g_latch.index[r]), g_latch.original[r], g_latch.patched[r], RECORD_SIZE,
                     MEM_OWNER_LATCH)
            != MEM_SWAPPED)
            return undo(reason, n, "menu binding could not be latched");
    for (int d = 0; d < 2; d++)
        if (value[d] != PRESS && mem_swap(dword[d], &value[d], &PRESS, sizeof PRESS, MEM_OWNER_LATCH) != MEM_SWAPPED)
            return undo(reason, n, "menu trigger could not be latched");
    g_latch.entries = mem_journal_count(MEM_OWNER_LATCH);
    g_latch.held = true;
    return true;
}

bool latch_refresh(const GameLocal* l, char* reason, size_t n)
{
    uintptr_t table, map, dword[2];
    uint32_t capacity, key, count, value;
    say(reason, n, "", NULL);
    if (!g_latch.held) return say(reason, n, "menu latch not held", NULL);
    if (mem_journal_count(MEM_OWNER_LATCH) != g_latch.entries) {
        /* Someone restored the journal (mem_restore_all), perhaps not all of it: re-asserting now would patch again
         * what was put back, as new entries. What is left is latch_release's. */
        g_latch.held = false;
        return say(reason, n, "menu latch restored elsewhere", NULL);
    }
    if (!admitted(FEAT_LATCH, reason, n)) return false;
    if (!l || l->controls != g_latch.controls) return say(reason, n, "controls changed", NULL);
    /* The same map and bucket (menu_latch.lua:46-50): the bucket still Display Stratagem List's, every patched record
     * below its count. */
    map = g_latch.controls + DBF_OFF_BINDING_MAP_OFFSET;
    if (!mem_u32(map + DBF_OFF_BINDING_MAP_CAPACITY_OFFSET, &capacity) || !mem_ptr(map, &table)
        || !mem_u32(g_latch.bucket, &key) || !mem_u32(g_latch.bucket + DBF_OFF_BINDING_BUCKET_COUNT_OFFSET, &count))
        return say(reason, n, "menu bindings unreadable", NULL);
    if (capacity != DBF_VAL_BINDING_MAP_CAPACITY || table != g_latch.table || key != DBF_VAL_BINDING_MENU_KEY
        || count > DBF_VAL_BINDING_COUNT_MAX)
        return say(reason, n, "menu binding changed", NULL);
    for (uint32_t r = 0; r < g_latch.records; r++) {
        MemSwap swap;
        if (g_latch.index[r] >= count) return say(reason, n, "menu binding changed", NULL);
        swap = mem_swap(record_at(g_latch.bucket, g_latch.index[r]), g_latch.original[r], g_latch.patched[r],
                        RECORD_SIZE, MEM_OWNER_LATCH);
        if (swap == MEM_FAILED) return say(reason, n, "menu binding could not be latched", NULL);
        if (swap != MEM_ALREADY && swap != MEM_SWAPPED) return say(reason, n, "menu binding changed", NULL);
    }
    /* The frame in flight may still carry the Hold trigger (menu_latch.lua:51-60). */
    trigger_dwords(g_latch.controls, g_latch.actions, dword);
    for (int d = 0; d < 2; d++) {
        MemSwap swap;
        if (!read_trigger(dword[d], &value, reason, n)) return false;
        if (value == PRESS) continue;
        swap = mem_swap(dword[d], &value, &PRESS, sizeof PRESS, MEM_OWNER_LATCH);
        g_latch.entries = mem_journal_count(MEM_OWNER_LATCH); /* a dword first seen nonzero is a new entry */
        if (swap == MEM_DIFFERENT) return say(reason, n, "menu trigger changed", NULL);
        if (swap != MEM_SWAPPED) return say(reason, n, "menu trigger could not be latched", NULL);
    }
    return true;
}

int latch_release(bool avatar_valid)
{
    uintptr_t controls;
    int lost = 0;
    g_latch.held = false;
    if (mem_journal_count(MEM_OWNER_LATCH) > 0) {
        if (!controls_now(&controls)) {
            /* Unreadable, 0 or not a pointer: maybe only for now. R46 returned here (menu_latch.lua:27) and never came
             * back; DBF retries, so everything is kept, unwritten, until the pointer can be checked again. */
            lost = mem_journal_count(MEM_OWNER_LATCH);
            if (!g_latch.unreadable_logged)
                log_line("latch: the controls pointer cannot be read; the menu latch is kept for a retry");
            g_latch.unreadable_logged = true;
        } else if (controls != g_latch.controls) {
            /* menu_latch.lua:27: another controls object: nothing of the old one is written. */
            lost = mem_forget_all(MEM_OWNER_LATCH);
            log_line("latch: the controls object changed; the menu latch was dropped without writing it back");
        } else {
            g_latch.unreadable_logged = false;
            /* menu_latch.lua:38: the actions dword only for the player the latch was taken for. */
            if (!avatar_valid && mem_forget(MEM_OWNER_LATCH, g_latch.actions + DBF_OFF_ACTION_TRIGGER_OFFSET)) {
                lost++;
                log_line("latch: the player changed; the old player's menu trigger was left alone");
            }
            lost += mem_restore(MEM_OWNER_LATCH);
        }
    }
    if (mem_journal_count(MEM_OWNER_LATCH) == 0) memset(&g_latch, 0, sizeof g_latch);
    else g_latch.entries = mem_journal_count(MEM_OWNER_LATCH);
    return lost;
}

bool latch_held(void)
{
    return g_latch.held;
}

/* What the latch remembers is cleared once its last entry is gone (latch_release), and a real player manager is never
 * 0 (mem_ptr), so with no latch and nothing left no player matches. */
bool latch_owner_is(const GameLocal* l)
{
    return latch_player(l);
}

/* --- slot hotkeys ---------------------------------------------------------------------------------------------- */

/* The job fails with `why` without entry (a refusal before entry_begin, or a done job cancelled). */
static void job_fail(EntryJob* job, const char* why)
{
    size_t at = 0;
    for (const char* p = why; p && *p && at < sizeof job->reason - 1; p++) job->reason[at++] = *p;
    job->reason[at] = '\0';
    job->state = ENTRY_FAILED;
}

/* A refusal of entry_begin_shortcut: the job fails with `why`, copied to `reason`. False. */
static bool refuse(EntryJob* job, char* reason, size_t n, const char* why)
{
    job_fail(job, why);
    return say(reason, n, why, NULL);
}

/* A failure after the latch was taken (R46 begin_latched, 342-345): release, then close the menu DBF opened. `valid`:
 * the player is still the one the shortcut began for (after the view was read again, it says so); otherwise the old
 * player's actions dword is left alone and its component not closed. */
static bool abort_begin(EntryJob* job, char* reason, size_t n, const char* why, bool opened, uintptr_t component,
                        bool valid)
{
    char kept[DBF_REASON_SIZE];
    say(kept, sizeof kept, why, NULL); /* why may be job->reason */
    (void)latch_release(valid);
    if (opened && valid) (void)nat_close_input(component);
    if (opened && !valid) log_line("latch: the menu DBF opened was left open: the player changed while it opened");
    return refuse(job, reason, n, kept);
}

/* The view shows the shortcut's player: the chain holds, with the same manager, key and component. */
static bool same_player(const GameView* v)
{
    return v && v->local_ok && v->local.manager == g_shortcut.manager && v->local.key == g_shortcut.key
        && v->local.component == g_shortcut.component;
}

/* The local menu action's byte (input.lua:289-291): released, else the reason (`held` when it is pressed). */
static bool menu_key_up(uintptr_t actions, const char* held, char* out, size_t n)
{
    uint8_t down;
    if (!mem_u8(actions, &down)) return say(out, n, "menu action unreadable", NULL);
    if (down == DBF_VAL_ACTION_PRESSED) return say(out, n, held, NULL);
    if (down != DBF_VAL_ACTION_RELEASED) return say(out, n, "invalid menu action", NULL);
    return true;
}

/* The four direction action bytes released (input.lua:293, entry's idle check). */
static bool directions_idle(uintptr_t actions, char* out, size_t n)
{
    static const uint32_t ACTIONS[] = {
        DBF_VAL_ACTION_LEFT, DBF_VAL_ACTION_RIGHT, DBF_VAL_ACTION_UP, DBF_VAL_ACTION_DOWN,
    };
    for (size_t i = 0; i < sizeof ACTIONS / sizeof ACTIONS[0]; i++) {
        uint8_t byte;
        if (!mem_u8(actions + (uintptr_t)DBF_OFF_ACTION_ENTRY_STRIDE * ACTIONS[i], &byte))
            return say(out, n, "direction actions unreadable", NULL);
        if (byte != DBF_VAL_ACTION_RELEASED) return say(out, n, "manual direction input", NULL);
    }
    return true;
}

bool entry_begin_shortcut(EntryJob* job, const GameView* v, int slot, uint32_t interval_ms, bool instant, uint64_t now,
                          char* reason, size_t n)
{
    GameView fresh;
    const GameLocal* l;
    DbfCode code;
    char why[DBF_REASON_SIZE];
    uint32_t count, matched, queued, entries, kind, owner, requested;
    uintptr_t weapon;
    uint8_t answer;
    bool opened = false;

    say(reason, n, "", NULL);
    if (!job) return say(reason, n, "no job", NULL);
    if (job->state == ENTRY_RUNNING || g_shortcut.active) return say(reason, n, "a code is being entered", NULL);
    memset(job, 0, sizeof *job);
    job->latched = true;
    if (slot < (int)DBF_VAL_SLOT_MIN || slot > (int)DBF_VAL_SLOT_MAX)
        return refuse(job, reason, n, "invalid equipped slot");
    if (!admitted(FEAT_ENTRY, why, sizeof why)) return refuse(job, reason, n, why);
    /* begin_shortcut (input.lua:355-364): the chain (release_state's context), then the equipped slot: payload entry
     * slot + 3, of 8 to 32 entries. */
    if (!v || !v->local_ok) return refuse(job, reason, n, "local player unavailable");
    l = &v->local;
    if (!mem_u32(l->payload + DBF_OFF_PAYLOAD_COUNT_OFFSET, &entries))
        return refuse(job, reason, n, "stratagem entries unreadable");
    if (entries < DBF_VAL_PAYLOAD_SLOTS_MIN || entries > DBF_VAL_PAYLOAD_ENTRY_MAX)
        return refuse(job, reason, n, "equipped stratagems unavailable");
    if (!mem_u32(l->payload + DBF_OFF_PAYLOAD_KINDS_OFFSET
                     + (uintptr_t)((uint32_t)slot + DBF_VAL_PAYLOAD_SLOT_BASE) * DBF_OFF_PAYLOAD_ENTRY_STRIDE,
                 &kind))
        return refuse(job, reason, n, "stratagem entries unreadable");
    if (kind == 0) return refuse(job, reason, n, "equipped slot is empty");
    job->kind = kind;
    /* begin_latched (input.lua:298-312): the menu key up, the UI clear, the component clean, the directions idle, the
     * code. */
    if (!menu_key_up(l->actions, "menu key held", why, sizeof why)) return refuse(job, reason, n, why);
    if (!l->unobstructed) return refuse(job, reason, n, "UI obstructed");
    if (!mem_u32(l->component, &count) || !mem_u32(l->component + DBF_OFF_COMPONENT_MATCHED_OFFSET, &matched)
        || !mem_u32(l->component + DBF_OFF_COMPONENT_QUEUED_OFFSET, &queued))
        return refuse(job, reason, n, "input component unreadable");
    if (count != 0 || matched != 0 || queued != 0) return refuse(job, reason, n, "close and reopen the menu");
    if (!directions_idle(l->actions, why, sizeof why)) return refuse(job, reason, n, why);
    if (!codes_read(kind, l, &code, why, sizeof why)) return refuse(job, reason, n, why);

    /* begin_latched (input.lua:313-340): the latch, the menu, the weapon's slot, then the job. */
    if (!latch_acquire(l, why, sizeof why)) return refuse(job, reason, n, why);
    if (!l->menu_active) {
        if (!nat_open_input(l->component, &answer))
            return abort_begin(job, reason, n, "the menu could not be opened", false, 0, true);
        if (answer == 0) return abort_begin(job, reason, n, "the game did not open the menu", false, 0, true);
        opened = true;
    }
    game_read(&fresh); /* the view passed in still says the menu is closed */
    if (!fresh.local_ok) return abort_begin(job, reason, n, "local player unavailable", opened, l->component, false);
    if (fresh.local.manager != l->manager || fresh.local.key != l->key || fresh.local.component != l->component)
        return abort_begin(job, reason, n, "player changed", opened, l->component, false);
    if (!fresh.menu_open) return abort_begin(job, reason, n, "menu closed", opened, l->component, true);
    if (!fresh.local.menu_active) return abort_begin(job, reason, n, "menu inactive", opened, l->component, true);
    weapon = fresh.local.avatar + DBF_OFF_WEAPON_OFFSET;
    if (!mem_u32(weapon, &owner) || !mem_u32(weapon + DBF_OFF_WEAPON_SLOT_OFFSET, &requested))
        return abort_begin(job, reason, n, "weapon unreadable", opened, l->component, true);
    if (owner != fresh.local.key) return abort_begin(job, reason, n, "weapon owner mismatch", opened, l->component, true);
    if (requested < DBF_VAL_WEAPON_SLOT_MIN || requested > DBF_VAL_WEAPON_SLOT_MAX)
        return abort_begin(job, reason, n, "invalid weapon slot", opened, l->component, true);
    if (requested != DBF_VAL_STRATAGEM_SLOT) {
        /* The opener skips its own slot request while the beacon is still the weapon (input.lua:325-328). */
        if (!nat_request_slot(weapon, DBF_VAL_STRATAGEM_SLOT))
            return abort_begin(job, reason, n, "stratagem slot could not be requested", opened, l->component, true);
        if (!mem_u32(weapon + DBF_OFF_WEAPON_SLOT_OFFSET, &requested) || requested != DBF_VAL_STRATAGEM_SLOT)
            return abort_begin(job, reason, n, "the game did not select the stratagem slot", opened, l->component, true);
    }
    if (!entry_begin(job, &fresh, kind, interval_ms, instant, true, now))
        return abort_begin(job, reason, n, job->reason, opened, l->component, true);

    memset(&g_shortcut, 0, sizeof g_shortcut);
    g_shortcut.active = true;
    g_shortcut.opened = opened;
    g_shortcut.manager = l->manager;
    g_shortcut.key = l->key;
    g_shortcut.component = l->component;
    g_shortcut.avatar = l->avatar;
    return true;
}

/* The menu-active bit, read now (R46's end_release reads the context again, input.lua:375): the tick's view is stale
 * once entry_step ran, since the game may close the menu inside a handler call. */
static bool menu_active_now(void)
{
    uint32_t word;
    return mem_u32(g_shortcut.avatar + DBF_OFF_AVATAR_MENU_OFFSET, &word) && (word & DBF_VAL_MENU_ACTIVE_MASK) != 0;
}

/* Ends the shortcut (R46 end_release, input.lua:374-379): the latch back (the actions dword only for the same player),
 * then the menu DBF opened closed while the view shows the same player and the menu-active bit, read now, is set. A
 * done shortcut ends only once the menu is inactive, so it never closes it. */
static void end_shortcut(const GameView* v)
{
    bool same = same_player(v), close = g_shortcut.opened && same && menu_active_now();
    uintptr_t component = g_shortcut.component;
    (void)latch_release(same);
    if (close) (void)nat_close_input(component);
    memset(&g_shortcut, 0, sizeof g_shortcut);
}

/* Cancels the shortcut with `why`: a running job through entry_cancel, any other turns ENTRY_FAILED with it. */
static void cancel(EntryJob* job, const GameView* v, const char* why)
{
    if (job && job->state == ENTRY_RUNNING) entry_cancel(job, why);
    else if (job) job_fail(job, why);
    end_shortcut(v);
}

/* R46's hold_release (input.lua:365-373) for the shortcut's own player: the UI clear, the menu key up, the latch
 * kept. */
static bool hold(const GameView* v, char* why, size_t n)
{
    if (!v->local.unobstructed) return say(why, n, "UI obstructed", NULL);
    if (!menu_key_up(v->local.actions, "menu key pressed", why, n)) return false;
    return latch_refresh(&v->local, why, n);
}

/* Why a done shortcut is cancelled this tick, or NULL; *done when the game has closed the menu. In R46's order: Confirm and
 * the deadline (release.lua:28), then release_complete (input.lua:380-392): the same player, the menu (inactive: done),
 * the kind still matched or queued, and hold_release. */
static const char* finishing(const EntryJob* job, const GameView* v, uint64_t now, bool confirm_down, bool* done,
                             char* why, size_t n)
{
    uint32_t matched, queued;
    *done = false;
    if (confirm_down) return "Confirm pressed";
    if (now > g_shortcut.finish_by) return "the menu did not close";
    if (!v || !v->local_ok) return "local player unavailable";
    if (!same_player(v)) return "player changed";
    if (!v->local.menu_active) {
        *done = true;
        return NULL;
    }
    if (!mem_u32(g_shortcut.component + DBF_OFF_COMPONENT_MATCHED_OFFSET, &matched)
        || !mem_u32(g_shortcut.component + DBF_OFF_COMPONENT_QUEUED_OFFSET, &queued))
        return "input component unreadable";
    if (matched != job->kind && queued != job->kind) return "the game dropped the stratagem";
    return hold(v, why, n) ? NULL : why;
}

void entry_step_shortcut(EntryJob* job, const GameView* v, uint64_t now, bool trigger_down, bool confirm_down)
{
    char why[DBF_REASON_SIZE];
    const char* problem = NULL;
    bool done;
    if (!g_shortcut.active) return;
    if (job && job->state == ENTRY_RUNNING) {
        /* release.lua:28 (an explicit Confirm), then hold_release and the step (release.lua:45-53). A player that
         * changed is entry_step's to fail ("player changed", "local player unavailable", "menu closed"). */
        if (confirm_down)
            problem = "Confirm pressed";
        else if (same_player(v) && !hold(v, why, sizeof why))
            problem = why;
        if (problem) {
            cancel(job, v, problem);
            return;
        }
        entry_step(job, v, now, trigger_down);
        if (job->state == ENTRY_FAILED) end_shortcut(v);
        if (job->state == ENTRY_DONE) {
            g_shortcut.finishing = true;
            g_shortcut.finish_by = now + SHORTCUT_FINISH_MS;
        }
        return;
    }
    if (!job || job->state != ENTRY_DONE || !g_shortcut.finishing) {
        end_shortcut(v); /* the job was cancelled by the caller */
        return;
    }
    problem = finishing(job, v, now, confirm_down, &done, why, sizeof why);
    if (done)
        end_shortcut(v);
    else if (problem)
        cancel(job, v, problem);
}

void entry_cancel_shortcut(EntryJob* job, const GameView* v, const char* reason)
{
    if (!g_shortcut.active) return;
    cancel(job, v, reason ? reason : "cancelled");
}

bool shortcut_active(void)
{
    return g_shortcut.active;
}
