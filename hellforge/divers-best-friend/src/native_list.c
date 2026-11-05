#include "native_list.h"
#include "logic.h"
#include <string.h>

typedef struct Scale { float x, y; } Scale;

/* The native setters also update derived widget state. Never restore these fields
 * through the generic byte journal: it has no way to identify a recycled widget. */
#ifdef DBF_TEST_NATIVE_LIST
extern void list_test_set(uintptr_t widget, bool scale, const float* values);
#endif
static uintptr_t game_base;
static void (*logger)(const char*);

/* Same hexadecimal checkpoint format as native.c. Scalar values are their float bits. */
static char* hex_arg(char* end, uint64_t value)
{
    static const char digits[] = "0123456789abcdef";
    char reversed[16];
    unsigned n = 0;
    *end++ = '0';
    *end++ = 'x';
    do {
        reversed[n++] = digits[value & 15u];
        value >>= 4;
    } while (value);
    while (n) *end++ = reversed[--n];
    return end;
}

static void set(uintptr_t base, uintptr_t widget, bool scale, const float* values)
{
    if (logger) {
        char message[128];
        strcpy(message, scale ? "call widget_scale(" : "call text_colour(");
        char* end = hex_arg(message + strlen(message), widget);
        for (int i = 0; i < (scale ? 2 : 3); ++i) {
            uint32_t bits;
            memcpy(&bits, values + i, sizeof bits);
            *end++ = ',';
            *end++ = ' ';
            end = hex_arg(end, bits);
        }
        strcpy(end, ")");
        logger(message);
    }
#ifdef DBF_TEST_NATIVE_LIST
    list_test_set(widget, scale, values);
#elif defined(_WIN32)
    if (scale) {
        typedef void (*Setter)(uintptr_t, Scale);
        ((Setter)(base + DBF_FN_WIDGET_SCALE))(widget, (Scale){values[0], values[1]});
    } else {
        typedef void (*Setter)(uintptr_t, const float*);
        ((Setter)(base + DBF_FN_TEXT_COLOUR))(widget, values);
    }
#endif
}

enum { NAME, STATUS, ARROWS, SCALE, PROPERTIES };
static const unsigned containers[] = {DBF_OFF_NAME_CONTAINER, DBF_OFF_STATUS_CONTAINER, DBF_OFF_ARROW_CONTAINER};
static const unsigned children[] = {DBF_OFF_NAME_CHILD, DBF_OFF_STATUS_CHILD, DBF_OFF_ARROW_CHILD};

typedef struct Change {
    bool held;
    float original[3], applied[3];
} Change;
typedef struct Row {
    uint32_t entry, kind;
    Change changes[PROPERTIES];
} Row;
static Row saved[DBF_VAL_CARD_COUNT];
static uintptr_t owner;

void native_list_init(uintptr_t base, void (*log)(const char*))
{
    game_base = base;
    logger = log;
    memset(saved, 0, sizeof saved);
    owner = 0;
}

/* Admission allows bytes masked by HellForge hooks. For these native widget
 * calls require the live entry and tween instructions themselves to still match. */
static bool setter_intact(bool scale)
{
    uint32_t entry = scale ? DBF_FN_WIDGET_SCALE : DBF_FN_TEXT_COLOUR;
    bool checked_entry = false, checked_tween = false;
    for (int i = 0; i < dbf_witness_count; ++i) {
        const DbfWitness* w = &dbf_witnesses[i];
        bool tween = scale && !strcmp(w->name, "scale_tween_slot");
        if (w->rva != entry && !tween) continue;
        uint8_t bytes[64];
        if (!w->size || w->size > sizeof bytes || !mem_read(game_base + w->rva, bytes, w->size) ||
            memcmp(bytes, w->bytes, w->size)) return false;
        if (tween) checked_tween = true;
        else checked_entry = true;
    }
    return checked_entry && (!scale || checked_tween);
}

/* 25480438 set_scale +0xbe: see scale_tween_slot in the build receipt. */
static bool scale_idle(uintptr_t card)
{
    uint32_t flags;
    uint64_t slots;
    return mem_u32(card, &flags) && (!(flags & 0x02000000u) ||
           (mem_u64(card + 0xa8u, &slots) && ((slots >> 33) & 0x7ffu) == 0));
}

static bool parent(uintptr_t at, uintptr_t expected)
{
    uintptr_t p;
    return mem_ptr(at + DBF_OFF_NODE_PARENT_OFFSET, &p) && p == expected;
}

static bool hierarchy(uintptr_t base, uintptr_t hud, uint8_t* open)
{
    uintptr_t root, state;
    uint32_t mode;
    uint8_t ready;
    if (!mem_ptr(base + DBF_RVA_HUD_ROOT, &root) || root != hud ||
        !mem_u8(root + DBF_OFF_HUD_READY_OFFSET, &ready) || ready != DBF_VAL_HUD_READY ||
        !mem_ptr(base + DBF_RVA_GAME_STATE, &state) ||
        !mem_u32(state + DBF_OFF_GAME_MODE_OFFSET, &mode) || mode != DBF_VAL_GAMEPLAY_MODE) return false;

    uintptr_t panel = root + DBF_OFF_HUD_PANEL_OFFSET, list = panel + DBF_OFF_LIST_OFFSET;
    if (!mem_u8(panel + DBF_OFF_OPEN_BYTE_OFFSET, open) || *open > 1 ||
        !parent(root + DBF_OFF_HUD_CONTAINER_OFFSET, root + DBF_OFF_HUD_VIEWPORT_OFFSET) ||
        !parent(panel, root + DBF_OFF_HUD_CONTAINER_OFFSET) || !parent(panel + DBF_OFF_PANEL_FADE_OFFSET, panel) ||
        !parent(panel + DBF_OFF_PANEL_CONTENT_OFFSET, panel + DBF_OFF_PANEL_FADE_OFFSET) ||
        !parent(list, panel + DBF_OFF_PANEL_CONTENT_OFFSET)) return false;
    for (unsigned i = 0; i < DBF_VAL_CARD_COUNT; ++i)
        if (!parent(list + DBF_OFF_CARD_FIRST + i * DBF_OFF_CARD_STRIDE, list)) return false;
    return true;
}

static bool same_row(const DbfRow* row)
{
    uint8_t active;
    uint32_t entry;
    return row->active && mem_u8(row->card + DBF_OFF_CARD_ACTIVE_OFFSET, &active) && active == DBF_VAL_CARD_ACTIVE &&
           mem_u32(row->card + DBF_OFF_CARD_ENTRY_OFFSET, &entry) && entry == row->entry;
}

static bool text_layout(uintptr_t card)
{
    for (int i = NAME; i <= ARROWS; ++i) {
        uintptr_t at = card + containers[i];
        if (!parent(card + children[i], at)) return false;
        for (int depth = 0; depth < 8; ++depth) {
            uintptr_t p;
            if (!mem_ptr(at + DBF_OFF_NODE_PARENT_OFFSET, &p) || p < card || p >= card + DBF_OFF_CARD_STRIDE || p == at)
                return false;
            at = p;
            if (at == card) break;
        }
        if (at != card) return false;
    }
    return true;
}

static bool bounded(float v)
{
    return v >= -(float)DBF_VAL_CARD_POSITION_MAX && v <= (float)DBF_VAL_CARD_POSITION_MAX;
}

static bool values(uintptr_t widget, bool scale, float* out)
{
    if (scale)
        return mem_read(widget + DBF_OFF_WIDGET_SCALE, out, 2 * sizeof(float)) && bounded(out[0]) && bounded(out[1]);
    float style[4];
    if (!mem_read(widget + DBF_OFF_WIDGET_STYLE, style, sizeof style)) return false;
    for (int i = 0; i < 4; ++i)
        if (!(style[i] >= 0 && style[i] <= 1)) return false;
    memcpy(out, style + 1, 3 * sizeof(float));
    return true;
}

static bool available(const DbfRow* row)
{
    DbfTimer timer;
    logic_timer(row, &timer);
    return row->kind && !timer.incoming && !timer.cooldown && !timer.unavailable;
}

/* Revalidate on transitions, including after a preceding native call. An unchanged
 * selection leaves the native tick alone (R46 style_key). Alpha is never owned. */
static void transition(uintptr_t base, const DbfRow* row, const DbfRow* selected, int property, bool want, Change* change)
{
    if (want == change->held) return;
    bool scale = property == SCALE;
    uintptr_t widget = scale ? row->card : row->card + containers[property];
    size_t bytes = (scale ? 2u : 3u) * sizeof(float);
    float current[3], target[3];
    uint8_t open;
    if (!hierarchy(base, owner, &open) || !same_row(row) || (!scale && !text_layout(row->card)) ||
        !values(widget, scale, current) || (scale && !scale_idle(widget)) || !setter_intact(scale)) return;
    if (want) {
        DbfRow live = {.kind = row->kind};
        if (!open || !same_row(selected) ||
            !mem_read(row->card + DBF_OFF_CARD_TIMER_OFFSET, live.timer, sizeof live.timer) || !available(&live)) return;
        for (unsigned i = 0; i < bytes / sizeof(float); ++i) {
            target[i] = (float)(current[i] * (scale ? 1.10 : 0.35));
            if (!bounded(target[i])) return;
        }
        if (!memcmp(current, target, bytes)) return;
        memcpy(change->original, current, bytes);
        memcpy(change->applied, target, bytes);
    } else {
        if (memcmp(current, change->applied, bytes)) {
            change->held = false;
            return;
        }
        memcpy(target, change->original, bytes);
    }
    if (want) change->held = true; /* keep ownership if readback becomes temporarily unavailable */
    set(base, widget, scale, target);
    /* A refused apply can retry. A refused restore retains its exact ownership. */
    if (values(widget, scale, current)) change->held = !memcmp(current, change->applied, bytes);
}

void native_list_update(const GameView* view, int chosen)
{
    const DbfRow* slots[DBF_VAL_CARD_COUNT] = {0};
    uintptr_t base = game_base;
    uint8_t open;
    /* With no owned values, a closed or disabled menu has no cleanup to do. */
    if (!owner && (!view || !view->menu_open || chosen < 0 || chosen >= view->row_count)) return;
    if (!base || adm_feature(FEAT_STATE, NULL) != ADMIT_OK) return;
    if (owner) {
        /* A readable root change ends this generation even when the next view is
         * incomplete, or the allocator later puts a new HUD at the old address. */
        uintptr_t state;
        uint32_t mode;
        uint64_t live;
        if (!mem_u64(base + DBF_RVA_HUD_ROOT, &live)) return;
        bool left_game = mem_ptr(base + DBF_RVA_GAME_STATE, &state) &&
                         mem_u32(state + DBF_OFF_GAME_MODE_OFFSET, &mode) && mode != DBF_VAL_GAMEPLAY_MODE;
        if (live != owner || left_game) {
            memset(saved, 0, sizeof saved);
            owner = 0;
        }
    }
    if (!view || !view->build_ok || !view->in_gameplay || !view->hud_ready ||
        view->row_count < 0 || view->row_count > (int)DBF_VAL_CARD_COUNT ||
        adm_feature(FEAT_HUD_READ, NULL) != ADMIT_OK ||
        adm_feature(FEAT_LIST_OPACITY, NULL) != ADMIT_OK || adm_feature(FEAT_STRATAGEMS, NULL) != ADMIT_OK ||
        !hierarchy(base, view->hud, &open)) return;

    uintptr_t first = view->hud + DBF_OFF_HUD_PANEL_OFFSET + DBF_OFF_LIST_OFFSET + DBF_OFF_CARD_FIRST;
    for (int i = 0; i < view->row_count; ++i) {
        const DbfRow* row = &view->rows[i];
        uintptr_t delta = row->card - first, slot = delta / DBF_OFF_CARD_STRIDE;
        if (slot >= DBF_VAL_CARD_COUNT || delta % DBF_OFF_CARD_STRIDE || slots[slot]) return;
        if (!same_row(row)) {
            /* A stale view can itself be the observation of a slot replacement. */
            uint8_t active;
            uint32_t entry;
            if ((mem_u8(row->card + DBF_OFF_CARD_ACTIVE_OFFSET, &active) && active == DBF_VAL_CARD_INACTIVE) ||
                (mem_u32(row->card + DBF_OFF_CARD_ENTRY_OFFSET, &entry) && entry != saved[slot].entry))
                memset(&saved[slot], 0, sizeof saved[slot]);
            return;
        }
        slots[slot] = row;
    }
    if (view->hud != owner) memset(saved, 0, sizeof saved);
    owner = view->hud;
    const DbfRow* selected = open && view->menu_open && chosen >= 0 && chosen < view->row_count &&
                             available(&view->rows[chosen]) ? &view->rows[chosen] : NULL;
    for (unsigned i = 0; i < DBF_VAL_CARD_COUNT; ++i) {
        const DbfRow* row = slots[i];
        Row* state = &saved[i];
        if (!row) {
            uint8_t active;
            uintptr_t card = first + i * DBF_OFF_CARD_STRIDE;
            if (mem_u8(card + DBF_OFF_CARD_ACTIVE_OFFSET, &active) && active == DBF_VAL_CARD_INACTIVE)
                memset(state, 0, sizeof *state);
            continue; /* game_read may have skipped a temporarily unreadable active card */
        }
        if (!row->kind) continue; /* incomplete payload; cannot prove identity */
        if (row->entry != state->entry || row->kind != state->kind) memset(state, 0, sizeof *state);
        state->kind = row->kind;
        state->entry = row->entry;
        bool dim = selected && selected != row && available(row);
        for (int p = NAME; p < PROPERTIES; ++p)
            transition(base, row, selected, p, p == SCALE ? row == selected : dim, &state->changes[p]);
    }
    for (unsigned i = 0; i < DBF_VAL_CARD_COUNT; ++i)
        for (int p = NAME; p < PROPERTIES; ++p)
            if (saved[i].changes[p].held) return;
    owner = 0;

}
