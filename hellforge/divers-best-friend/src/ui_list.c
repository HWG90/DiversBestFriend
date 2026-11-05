/* ui_list: see ui_list.h. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "text.h"
#include "ui_list.h"

/* Sizes in 1080p pixels, scaled by OvFrame.scale. Where they come from: the rounding and the bar are DESIGN.md tokens
 * (HD2-UI-Style's DESIGN.md, "Size"); DESIGN.md has no HUD text size, margin, padding or gaps, and R46 drew no
 * list of its own (it rearranged the game's), so the other five are DBF's own choices for Plan 2's plain list (Task 11),
 * to be looked at in game in Task 13; Plan 3 replaces the list. */
#define LIST_TEXT_PX 22.0f            /* DBF's own: the text size */
#define LIST_MARGIN_PX 24.0f          /* DBF's own: the plate's distance from the left edge of the screen */
#define LIST_PAD_PX 12.0f             /* DBF's own: inside the plate (DESIGN.md has no padding for HUD plates) */
#define LIST_COLUMN_GAP_PX 18.0f      /* DBF's own: between the name, code and timer columns */
#define LIST_ROW_GAP_PX 6.0f          /* DBF's own: between two rows */
#define LIST_PLATE_ROUNDING_PX 6.0f   /* DESIGN.md hud_plate_rounding */
#define LIST_BAR_PX 3.0f              /* DESIGN.md selected_bar */
#define THEME_ABSENT 0xFFFFFFFFu      /* what a host answers for a token it does not have (goose_overlay.h: before 0.4.0) */

/* One row's texts and colours, ready to draw. */
typedef struct Item {
    char name[DBF_LIST_NAME_SIZE + 1];
    char code[2 * DBF_CODE_CAPACITY];
    char timer[16];
    uint32_t color;       /* the name and the timer */
    uint32_t unsent;      /* the code, or its directions not sent yet */
    unsigned sent;        /* directions to draw filled: 0 unless this row's job is running */
} Item;

/* Appends the decimal digits of `value` and the unit "s" to dst (size bytes, terminated). */
static void seconds_text(char* dst, size_t size, uint32_t value)
{
    char digits[11];
    size_t n = 0, at = 0;
    do {
        digits[n++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value != 0);
    while (n > 0 && at < size - 1) dst[at++] = digits[--n];
    if (at < size - 1) dst[at++] = 's';
    dst[at] = '\0';
}

/* The row's name, cut at its field's end if it has no terminator. */
static void name_text(char* dst, const char* src)
{
    size_t n = 0;
    while (n < DBF_LIST_NAME_SIZE && src[n] != '\0') {
        dst[n] = src[n];
        n++;
    }
    dst[n] = '\0';
}

static void timer_text(char* dst, size_t size, const DbfTimer* t)
{
    dst[0] = '\0';
    if (t->unavailable) snap_copy_text(dst, size, "unavailable");
    else if ((t->incoming || t->cooldown) && t->seconds > 0) seconds_text(dst, size, t->seconds);
}

static float width_of(const OvApi* ov, float size, const char* text)
{
    float w = 0.0f, h = 0.0f;
    if (text[0] == '\0') return 0.0f;
    ov->text_size(0, size, text, &w, &h);
    return w;
}

static float max_f(float a, float b)
{
    return b > a ? b : a;
}

/* The height of a line of text. */
static float height_of(const OvApi* ov, float size)
{
    float w = 0.0f, h = 0.0f;
    ov->text_size(0, size, "Ag", &w, &h);
    return h > 0.0f ? h : size;
}

/* The directions sent so far drawn in the accent, the rest after them in the row's unsent colour; none sent: all of it in
 * that colour. */
static void draw_code(const OvApi* ov, float x, float y, float size, const Item* it, uint32_t accent)
{
    char head[2 * DBF_CODE_CAPACITY];
    size_t length = strlen(it->code), cut;
    if (it->sent == 0) {
        ov->draw_text(x, y, it->unsent, 0, size, it->code);
        return;
    }
    cut = 2u * (size_t)it->sent - 1u; /* "^ >" is two directions in three bytes */
    if (cut >= length) {
        ov->draw_text(x, y, accent, 0, size, it->code);
        return;
    }
    memcpy(head, it->code, cut);
    head[cut] = '\0';
    ov->draw_text(x, y, accent, 0, size, head);
    ov->draw_text(x + width_of(ov, size, head), y, it->unsent, 0, size, it->code + cut);
}

void ui_list_draw(const OvApi* ov, const OvFrame* f, const DbfSnapshot* s)
{
    const ListView* l;
    Item items[DBF_LIST_ROWS];
    uint32_t text, accent, off, plate, shadow;
    float scale, size, pad, gap, row_gap, line_h, name_w = 0.0f, code_w = 0.0f, timer_w = 0.0f;
    float x0, y0, x1, name_x, code_x, timer_x, plate_h, y;
    int n, running = -1;
    if (ov == NULL || f == NULL || s == NULL) return;
    if (ov->draw_rect_filled == NULL || ov->draw_text == NULL || ov->text_size == NULL || ov->theme == NULL) return;
    l = &s->list;
    if (!l->valid || !l->enabled || !s->game.in_gameplay || !s->game.hud_ready || !s->game.menu_open) return;
    n = l->row_count < DBF_LIST_ROWS ? l->row_count : DBF_LIST_ROWS;
    if (n <= 0) return;

    scale = f->scale > 0.0f ? f->scale : 1.0f; /* also false for NaN */
    size = LIST_TEXT_PX * scale;
    pad = LIST_PAD_PX * scale;
    gap = LIST_COLUMN_GAP_PX * scale;
    row_gap = LIST_ROW_GAP_PX * scale;
    plate = ov->theme(OV_THEME_HUD_PLATE);
    if (plate == THEME_ABSENT) plate = ov->theme(OV_THEME_PANEL);
    shadow = ov->theme(OV_THEME_HUD_SHADOW);
    text = ov->theme(OV_THEME_TEXT);
    accent = ov->theme(OV_THEME_ACCENT);
    off = ov->theme(OV_THEME_TEXT_OFF);
    if (off == THEME_ABSENT) off = ov->theme(OV_THEME_TEXT_DIM);

    if (l->entry_state == ENTRY_RUNNING)
        for (int i = 0; i < n && running < 0; i++)
            if (l->rows[i].kind == l->entry_kind) running = i;

    for (int i = 0; i < n; i++) {
        const ListRowView* r = &l->rows[i];
        Item* it = &items[i];
        bool chosen = i == l->chosen;
        name_text(it->name, r->name);
        dbf_code_arrows(r->code, r->code_len, it->code, sizeof it->code);
        if (it->code[0] == '\0') snap_copy_text(it->code, sizeof it->code, "no code");
        timer_text(it->timer, sizeof it->timer, &r->timer);
        it->color = chosen ? accent : r->eligible ? text : off;
        it->unsent = chosen && i == running ? text : it->color; /* the accent would hide the progress */
        it->sent = i == running ? l->entry_sent : 0; /* draw_code stops at the code's end */
        name_w = max_f(name_w, width_of(ov, size, it->name));
        code_w = max_f(code_w, width_of(ov, size, it->code));
        timer_w = max_f(timer_w, width_of(ov, size, it->timer));
    }
    line_h = height_of(ov, size);

    x0 = LIST_MARGIN_PX * scale;
    name_x = x0 + pad;
    code_x = name_x + name_w + gap;
    timer_x = code_x + code_w + gap;
    x1 = (timer_w > 0.0f ? timer_x + timer_w : code_x + code_w) + pad;
    plate_h = 2.0f * pad + (float)n * line_h + (float)(n - 1) * row_gap;
    y0 = (f->height - plate_h) * 0.5f;

    ov->draw_rect_filled(x0, y0, x1, y0 + plate_h, plate, LIST_PLATE_ROUNDING_PX * scale);
    y = y0 + pad;
    for (int i = 0; i < n; i++) {
        const Item* it = &items[i];
        if (i == l->chosen) {
            float top = y - row_gap * 0.5f, bottom = y + line_h + row_gap * 0.5f;
            ov->draw_rect_filled(x0, top, x1, bottom, ov->theme(OV_THEME_ACCENT_DIM), LIST_PLATE_ROUNDING_PX * scale);
            ov->draw_rect_filled(x0, top, x0 + LIST_BAR_PX * scale, bottom, accent, 0.0f);
        }
        if (shadow != THEME_ABSENT) {
            ov->draw_text(name_x + scale, y + scale, shadow, 0, size, it->name);
            ov->draw_text(code_x + scale, y + scale, shadow, 0, size, it->code);
            if (it->timer[0] != '\0') ov->draw_text(timer_x + scale, y + scale, shadow, 0, size, it->timer);
        }
        ov->draw_text(name_x, y, it->color, 0, size, it->name);
        draw_code(ov, code_x, y, size, it, accent);
        if (it->timer[0] != '\0') ov->draw_text(timer_x, y, it->color, 0, size, it->timer);
        y += line_h + row_gap;
    }
}
