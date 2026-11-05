/* entry: code entry through the game's input path (see entry.h), ported from R46's input.lua:240-282 (begin, advance)
 * and selection.lua:13-16, 48-56, 92-93 (the aborts and the timing), with Instant from the 26251122 tree's
 * input.lua:24-36. Portable C11: standard headers, memory.h, admission.h, native.h, codes.h, game.h, logic.h and the
 * generated address header only. Every game number is a DBF_OFF_* / DBF_VAL_* of that header, with its R46 line there;
 * the input component's count is the u32 at the component itself (+0, R46 input.lua:241, 258). INSTANT_SETTLE_MS is
 * DBF's own (below). */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "addresses_25480438.h"
#include "admission.h"
#include "codes.h"
#include "entry.h"
#include "game.h"
#include "logic.h"
#include "memory.h"
#include "native.h"

/* The 26251122 tree's input.lua:24 (INSTANT_SETTLE_MS=100): an Instant job holds its last direction until the binding
 * that started it has been up this long, so a Confirm that is also Throw does not start the throw wind-up. */
#define INSTANT_SETTLE_MS 100u

_Static_assert(DBF_VAL_CODE_MAX <= DBF_CODE_CAPACITY, "a job's code fits DbfCode.dir");
_Static_assert(DBF_OFF_COMPONENT_DIRECTION_BASE + DBF_VAL_CODE_MAX < DBF_OFF_COMPONENT_MATCHED_OFFSET,
               "the direction bytes (component + 3 + i) end before the matched kind");

/* The four direction actions (R46 input.lua:187-188, a = 1..4). */
static const uint32_t ACTIONS[] = { DBF_VAL_ACTION_LEFT, DBF_VAL_ACTION_RIGHT, DBF_VAL_ACTION_UP, DBF_VAL_ACTION_DOWN };

/* The action that enters code direction d (1 up, 2 right, 3 down, 4 left), R46 input.lua:264. */
static const uint32_t ACTION_OF[DBF_VAL_DIRECTION_MAX + 1] = {
    0, DBF_VAL_DIRECTION_1_ACTION, DBF_VAL_DIRECTION_2_ACTION, DBF_VAL_DIRECTION_3_ACTION, DBF_VAL_DIRECTION_4_ACTION,
};

static const uint8_t PRESSED = DBF_VAL_ACTION_PRESSED, RELEASED = DBF_VAL_ACTION_RELEASED;

/* The journal outlives a failed job (including reuse of its EntryJob by a shortcut). */
static GameLocal release_owner;

void entry_retry_release(const GameView* v)
{
    if (!mem_journal_count(MEM_OWNER_ENTRY) || !v || !v->local_ok) return;
    const GameLocal* l = &v->local;
    if (l->manager != release_owner.manager || l->key != release_owner.key ||
        l->component != release_owner.component || l->actions != release_owner.actions ||
        l->avatar != release_owner.avatar) {
        mem_forget_all(MEM_OWNER_ENTRY);
        return;
    }
    mem_restore(MEM_OWNER_ENTRY);
}

/* --- reasons --------------------------------------------------------------------------------------------------- */

/* Ends the job: ENTRY_FAILED with the reason a b, cut to fit. False, for `return fail(...)`. */
static bool fail2(EntryJob* job, const char* a, const char* b)
{
    size_t at = 0;
    for (const char* p = a; p && *p && at < sizeof job->reason - 1; p++) job->reason[at++] = *p;
    for (const char* p = b; p && *p && at < sizeof job->reason - 1; p++) job->reason[at++] = *p;
    job->reason[at] = '\0';
    job->state = ENTRY_FAILED;
    return false;
}

static bool fail(EntryJob* job, const char* why)
{
    return fail2(job, why, NULL);
}

/* ENTRY admitted; else the job fails with "<feature name>: <admission's reason>", as game_read words it. */
static bool entry_admitted(EntryJob* job)
{
    const char* why = NULL;
    char name[48];
    size_t at = 0;
    if (adm_feature(FEAT_ENTRY, &why) == ADMIT_OK) return true;
    for (const char* p = adm_feature_name(FEAT_ENTRY); *p && at < sizeof name - 3; p++) name[at++] = *p;
    name[at++] = ':';
    name[at++] = ' ';
    name[at] = '\0';
    return fail2(job, name, why && *why ? why : "not admitted");
}

/* --- reads ----------------------------------------------------------------------------------------------------- */

/* The four direction action bytes released (R46's idle_actions, input.lua:187-188). */
static bool actions_idle(EntryJob* job, uintptr_t actions)
{
    for (size_t i = 0; i < sizeof ACTIONS / sizeof ACTIONS[0]; i++) {
        uint8_t byte;
        if (!mem_u8(actions + (uintptr_t)DBF_OFF_ACTION_ENTRY_STRIDE * ACTIONS[i], &byte))
            return fail(job, "direction actions unreadable");
        if (byte != RELEASED) return fail(job, "manual direction input");
    }
    return true;
}

/* The local payload holds `kind` (R46 input.lua:245-248): a u32 count of at most 32 at +0x788, the kinds at +0x188 +
 * k * 0x30. `gone` is the reason when it does not. */
static bool payload_holds(EntryJob* job, uintptr_t payload, uint32_t kind, const char* gone)
{
    uint32_t count, at;
    if (!mem_u32(payload + DBF_OFF_PAYLOAD_COUNT_OFFSET, &count)) return fail(job, "stratagem entries unreadable");
    if (count > DBF_VAL_PAYLOAD_ENTRY_MAX) return fail(job, "invalid stratagem entry count");
    for (uint32_t k = 0; k < count; k++) {
        if (!mem_u32(payload + DBF_OFF_PAYLOAD_KINDS_OFFSET + (uintptr_t)k * DBF_OFF_PAYLOAD_ENTRY_STRIDE, &at))
            return fail(job, "stratagem entries unreadable");
        if (at == kind) return true;
    }
    return fail(job, gone);
}

/* The menu-active bit, read now (R46 input.lua:118-120, which every advance's context(true) checked): the game may
 * close the menu inside a handler call, between two directions of one Instant step. */
static bool menu_still_active(EntryJob* job, uintptr_t avatar)
{
    uint32_t word;
    if (!mem_u32(avatar + DBF_OFF_AVATAR_MENU_OFFSET, &word)) return fail(job, "menu state unreadable");
    if ((word & DBF_VAL_MENU_ACTIVE_MASK) == 0) return fail(job, "menu inactive");
    return true;
}

/* --- one direction (R46 input.lua:251-282) --------------------------------------------------------------------- */

/* Sends the job's next direction; false when the job failed (it is then ENTRY_FAILED). */
static bool send_direction(EntryJob* job, const GameLocal* l)
{
    DbfCode code;
    char why[DBF_REASON_SIZE];
    uint32_t count, matched;
    uintptr_t component = l->component, address;
    uint8_t direction, byte;
    const char* problem = NULL;
    bool called = false, last;

    if (!entry_admitted(job) || !menu_still_active(job, l->avatar)) return false;
    /* The code, read again (with the scramble remap), must still be the job's: entry never sends a direction of a code
     * the game no longer expects (input.lua:253-257). */
    if (!codes_read(job->kind, l, &code, why, sizeof why)) return fail2(job, "code changed: ", why);
    if (code.len != job->code.len || memcmp(code.dir, job->code.dir, code.len) != 0) return fail(job, "code changed");
    /* The game's own record of this entry (input.lua:258-260): the directions taken so far, nothing matched, and the
     * direction bytes the ones sent. */
    if (!mem_u32(component, &count) || !mem_u32(component + DBF_OFF_COMPONENT_MATCHED_OFFSET, &matched))
        return fail(job, "input component unreadable");
    if (count != job->sent || matched != 0) return fail(job, "the game's input changed");
    for (uint32_t i = 1; i <= job->sent; i++) {
        if (!mem_u8(component + DBF_OFF_COMPONENT_DIRECTION_BASE + i, &byte)) return fail(job, "input component unreadable");
        if (byte != job->code.dir[i - 1]) return fail(job, "the game's code sequence changed");
    }
    if (!actions_idle(job, l->actions)) return false;
    direction = job->code.dir[job->sent];
    if (direction < DBF_VAL_DIRECTION_MIN || direction > DBF_VAL_DIRECTION_MAX) return fail(job, "invalid direction");

    /* Press, handle, release (input.lua:263-272): the byte is put back whatever happened in between. ENTRY was admitted
     * above, so a handler call that does not happen means the port has no handler. */
    if (mem_journal_count(MEM_OWNER_ENTRY)) return fail(job, "previous direction release pending");
    release_owner = *l;
    address = l->actions + (uintptr_t)DBF_OFF_ACTION_ENTRY_STRIDE * ACTION_OF[direction];
    if (mem_swap(address, &RELEASED, &PRESSED, 1, MEM_OWNER_ENTRY) != MEM_SWAPPED)
        problem = "direction could not be pressed";
    else if (!(called = nat_input_handler(component)))
        problem = "input handler unavailable";
    /* A byte the game released itself inside the call counts as put back. What matters is that the byte reads released
     * now; when the release could not be written, its entry stays journaled for an owner-checked retry. */
    (void)mem_restore(MEM_OWNER_ENTRY);
    if (!mem_u8(address, &byte) || byte != RELEASED) problem = "direction could not be released";
    if (called) job->sent++;
    if (problem) return fail(job, problem);

    /* The game counted the direction, and matched the job's kind (the one asked for, not a scramble's) only after the
     * last (input.lua:273-281). */
    last = job->sent == job->code.len;
    if (!mem_u32(component, &count) || !mem_u32(component + DBF_OFF_COMPONENT_MATCHED_OFFSET, &matched))
        return fail(job, "input component unreadable");
    if (count != job->sent) return fail(job, "the game did not take the direction");
    if (matched != (last ? job->kind : 0u))
        return fail(job, last ? "the game did not accept the code" : "the game matched another stratagem");
    if (last) job->state = ENTRY_DONE;
    return true;
}

/* --- the job --------------------------------------------------------------------------------------------------- */

bool entry_begin(EntryJob* job, const GameView* v, uint32_t kind, uint32_t interval_ms, bool instant, bool latched,
                 uint64_t now)
{
    const GameLocal* l;
    uint32_t count, matched, queued;
    char why[DBF_REASON_SIZE];
    if (!job || job->state == ENTRY_RUNNING) return false;
    memset(job, 0, sizeof *job);
    job->kind = kind;
    job->instant = instant;
    job->latched = latched;
    if (mem_journal_count(MEM_OWNER_ENTRY)) return fail(job, "previous direction release pending");
    if (!entry_admitted(job)) return false;
    /* R46's context(true) (input.lua:96-139): the menu open and active, the code-entry chain whole. */
    if (!v || !v->menu_open) return fail(job, "menu closed");
    if (!v->local_ok) return fail(job, "local player unavailable");
    l = &v->local;
    if (!l->menu_active) return fail(job, "menu inactive");
    /* input.lua:241-243: a component the game is still using (a code begun by hand, a match not yet consumed). */
    if (!mem_u32(l->component, &count) || !mem_u32(l->component + DBF_OFF_COMPONENT_MATCHED_OFFSET, &matched)
        || !mem_u32(l->component + DBF_OFF_COMPONENT_QUEUED_OFFSET, &queued))
        return fail(job, "input component unreadable");
    if (count != 0 || matched != 0 || queued != 0) return fail(job, "close and reopen the menu");
    if (!actions_idle(job, l->actions) || !payload_holds(job, l->payload, kind, "stratagem not in the mission"))
        return false;
    if (!codes_read(kind, l, &job->code, why, sizeof why)) return fail(job, why);
    if (job->code.len < DBF_VAL_CODE_MIN || job->code.len > DBF_VAL_CODE_MAX) return fail(job, "invalid code array");

    job->interval_ms = instant ? 0u : interval_ms;
    job->next_at = now; /* the first direction on the next step (R46 selection.lua:93) */
    job->deadline = logic_deadline(job->code.len, job->interval_ms, now);
    job->identity_manager = l->manager;
    job->identity_key = l->key;
    job->component = l->component;
    job->state = ENTRY_RUNNING;
    return true;
}

/* What ends a running job on any step, before anything is sent: R46 selection.lua:13-16 (the menu, the owner) and 49
 * (the deadline), context(true)'s menu and chain checks, and the payload check of begin (input.lua:245-248). */
static bool still_valid(EntryJob* job, const GameView* v, uint64_t now)
{
    if (!v || !v->menu_open) return fail(job, "menu closed");
    if (!v->local_ok) return fail(job, "local player unavailable");
    if (!v->local.menu_active) return fail(job, "menu inactive");
    if (v->local.manager != job->identity_manager || v->local.key != job->identity_key
        || v->local.component != job->component)
        return fail(job, "player changed");
    if (now > job->deadline) return fail(job, "timed out");
    return payload_holds(job, v->local.payload, job->kind, "stratagem no longer in the mission");
}

void entry_step(EntryJob* job, const GameView* v, uint64_t now, bool trigger_down)
{
    if (!job || job->state != ENTRY_RUNNING || !still_valid(job, v, now)) return;
    if (!job->instant) {
        /* Paced (selection.lua:52-56): one direction when it is due. */
        if (now >= job->next_at && send_direction(job, &v->local)) job->next_at = now + job->interval_ms;
        return;
    }
    /* Instant (the 26251122 tree's input.lua:24-36): every direction but the last now; the last once the trigger has
     * been up for INSTANT_SETTLE_MS without a break. Each send_direction that returns true sent one direction. */
    while (job->state == ENTRY_RUNNING) {
        if (job->sent + 1u == job->code.len) {
            if (trigger_down) {
                job->settle_at = 0;
                return;
            }
            if (job->settle_at == 0) job->settle_at = now + INSTANT_SETTLE_MS;
            if (now < job->settle_at) return;
        }
        if (!send_direction(job, &v->local)) return;
    }
}

void entry_cancel(EntryJob* job, const char* reason)
{
    if (!job || job->state != ENTRY_RUNNING) return;
    fail(job, reason ? reason : "cancelled");
}
