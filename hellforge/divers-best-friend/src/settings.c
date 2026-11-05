/* settings: see settings.h. */
#include <string.h>
#include "addresses_25480438.h" /* the extern declaration of dbf_blacklist_kinds; admission.c holds its one definition */
#include "settings.h"
#include "hud_options.h"

/* --- text helpers: a Span is a piece of the caller's text, never terminated ----------------------------------------- */

typedef struct Span {
    const char* p;
    size_t n;
} Span;

static bool is_space(char c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\v' || c == '\f';
}

static char lower(char c)
{
    return c >= 'A' && c <= 'Z' ? (char)(c + ('a' - 'A')) : c;
}

static Span trim(const char* b, const char* e)
{
    Span s;
    while (b < e && is_space(*b)) b++;
    while (e > b && is_space(e[-1])) e--;
    s.p = b;
    s.n = (size_t)(e - b);
    return s;
}

/* The span up to a trailing comment: the first ; or # that follows a space or a tab (Plan 2, Task 12: settings.ini is
 * edited by hand, and "enabled = false ; off" must turn DBF off), trimmed. A ; or # with no space before it stays. */
static Span strip_comment(Span s)
{
    for (size_t i = 1; i < s.n; i++)
        if ((s.p[i] == ';' || s.p[i] == '#') && (s.p[i - 1] == ' ' || s.p[i - 1] == '\t')) return trim(s.p, s.p + i);
    return trim(s.p, s.p + s.n);
}

/* The span equals `lit` (written in lower case) apart from case. */
static bool is(Span s, const char* lit)
{
    size_t i;
    for (i = 0; i < s.n; i++)
        if (lit[i] == '\0' || lower(s.p[i]) != lit[i]) return false;
    return lit[i] == '\0';
}

/* The span starts with `lit` (lower case), apart from case; *rest is what follows it. */
static bool starts(Span s, const char* lit, Span* rest)
{
    size_t n = strlen(lit);
    if (s.n < n) return false;
    for (size_t i = 0; i < n; i++)
        if (lower(s.p[i]) != lit[i]) return false;
    rest->p = s.p + n;
    rest->n = s.n - n;
    return true;
}

/* A whole number written with digits only, at most 9 of them (anything longer is out of every range here). */
static bool parse_decimal(Span s, int* out)
{
    int v = 0;
    if (s.n == 0 || s.n > 9) return false;
    for (size_t i = 0; i < s.n; i++) {
        if (s.p[i] < '0' || s.p[i] > '9') return false;
        v = v * 10 + (s.p[i] - '0');
    }
    *out = v;
    return true;
}

/* --- the problem list ------------------------------------------------------------------------------------------------ */

/* One problem is put together in `cur`, then added to the caller's buffer whole or not at all. Once one did not fit, no
 * later one is added either: the text is always the first problems of the list. */
typedef struct Problems {
    char* out;
    size_t cap;
    size_t used;
    int count;
    bool full;
    char cur[200];
    size_t len;
} Problems;

#define SHOWN_MAX 40 /* bytes of the player's text a problem repeats */

static void cur_add(Problems* p, const char* s, size_t n)
{
    for (size_t i = 0; i < n && p->len < sizeof p->cur - 1; i++) p->cur[p->len++] = s[i];
}

static void cur_str(Problems* p, const char* s)
{
    cur_add(p, s, strlen(s));
}

static void cur_number(Problems* p, int v)
{
    char digits[12];
    size_t n = 0;
    do {
        digits[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v > 0);
    while (n > 0) cur_add(p, &digits[--n], 1);
}

/* The player's text, cut to SHOWN_MAX bytes and in printable ASCII (anything else shows as ?). */
static void cur_shown(Problems* p, Span s)
{
    size_t n = s.n < SHOWN_MAX ? s.n : SHOWN_MAX;
    for (size_t i = 0; i < n; i++) {
        char c = s.p[i] >= 0x20 && s.p[i] < 0x7f ? s.p[i] : '?';
        cur_add(p, &c, 1);
    }
    if (s.n > SHOWN_MAX) cur_str(p, "...");
}

static void cur_quoted(Problems* p, Span s)
{
    cur_str(p, "\"");
    cur_shown(p, s);
    cur_str(p, "\"");
}

static void problem_begin(Problems* p, int line)
{
    p->len = 0;
    cur_str(p, "line ");
    cur_number(p, line);
    cur_str(p, ": ");
}

static void problem_end(Problems* p)
{
    size_t need = p->len + (p->used > 0 ? 1 : 0); /* the separator */
    p->count++;
    if (p->out == NULL || p->cap == 0 || p->full) return;
    if (p->used + need + 1 > p->cap) { /* + 1: the terminator */
        p->full = true;
        return;
    }
    if (p->used > 0) p->out[p->used++] = '\n';
    memcpy(p->out + p->used, p->cur, p->len);
    p->used += p->len;
    p->out[p->used] = '\0';
}

/* --- defaults -------------------------------------------------------------------------------------------------------- */

void settings_defaults(DbfSettings* s)
{
    if (s == NULL) return;
    memset(s, 0, sizeof *s);
    for (unsigned i = 0; i < hud_option_count(); ++i)
        hud_option_set(s, i, hud_option_descriptor(i)->initial);
    for (int i = 0; i < dbf_blacklist_kind_count; i++) {
        uint32_t kind = dbf_blacklist_kinds[i].kind;
        if (kind < DBF_BLACKLIST_SLOTS) s->blacklist_kind[kind] = dbf_blacklist_kinds[i].default_on;
    }
    s->bind[BIND_NEXT].kind = BIND_WHEEL_DOWN;
    s->bind[BIND_PREVIOUS].kind = BIND_WHEEL_UP;
    s->bind[BIND_CONFIRM].kind = BIND_MOUSE;
    s->bind[BIND_CONFIRM].code = 1;
}

/* --- values ---------------------------------------------------------------------------------------------------------- */

static const char* const k_action_names[BIND_COUNT] = { "next", "previous", "confirm", "slot1", "slot2", "slot3", "slot4" };

static const struct {
    const char* name;
    uint16_t mask;
} k_pad_buttons[] = {
    { "a", BIND_PAD_A },
    { "b", BIND_PAD_B },
    { "x", BIND_PAD_X },
    { "y", BIND_PAD_Y },
    { "lb", BIND_PAD_LB },
    { "rb", BIND_PAD_RB },
    { "back", BIND_PAD_BACK },
    { "start", BIND_PAD_START },
    { "ls", BIND_PAD_LS },
    { "rs", BIND_PAD_RS },
    { "dpad_up", BIND_PAD_DPAD_UP },
    { "dpad_down", BIND_PAD_DPAD_DOWN },
    { "dpad_left", BIND_PAD_DPAD_LEFT },
    { "dpad_right", BIND_PAD_DPAD_RIGHT },
};

static int hex_digit(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    c = lower(c);
    return c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
}

/* key:0xN or key:0xNN (1..0xFE), key:<letter or digit>, key:f1 .. key:f24; `v` is what follows "key:". */
static bool parse_key(Span v, uint16_t* vk)
{
    if (v.n >= 3 && v.p[0] == '0' && lower(v.p[1]) == 'x') {
        int code = 0;
        if (v.n > 4) return false; /* at most two hex digits */
        for (size_t i = 2; i < v.n; i++) {
            int d = hex_digit(v.p[i]);
            if (d < 0) return false;
            code = code * 16 + d;
        }
        if (code < 1 || code > 0xFE) return false;
        *vk = (uint16_t)code;
        return true;
    }
    if (v.n == 1) {
        char c = v.p[0];
        if (c >= '0' && c <= '9') *vk = (uint16_t)c;
        else if (lower(c) >= 'a' && lower(c) <= 'z') *vk = (uint16_t)(lower(c) - 'a' + 'A');
        else return false;
        return true;
    }
    if ((v.n == 2 || v.n == 3) && lower(v.p[0]) == 'f' && v.p[1] >= '1' && v.p[1] <= '9') {
        Span digits = { v.p + 1, v.n - 1 };
        int number;
        if (!parse_decimal(digits, &number) || number < 1 || number > 24) return false;
        *vk = (uint16_t)(0x70 + number - 1); /* VK_F1 .. VK_F24 */
        return true;
    }
    return false;
}

static bool parse_binding(Span v, Binding* out)
{
    Span rest;
    out->kind = BIND_NONE;
    out->code = 0;
    if (is(v, "none")) return true;
    if (is(v, "wheel_up")) {
        out->kind = BIND_WHEEL_UP;
        return true;
    }
    if (is(v, "wheel_down")) {
        out->kind = BIND_WHEEL_DOWN;
        return true;
    }
    if (starts(v, "mouse", &rest)) {
        if (rest.n != 1 || rest.p[0] < '1' || rest.p[0] > '5') return false;
        out->kind = BIND_MOUSE;
        out->code = (uint16_t)(rest.p[0] - '0');
        return true;
    }
    if (starts(v, "key:", &rest)) {
        if (!parse_key(rest, &out->code)) return false;
        out->kind = BIND_KEY;
        return true;
    }
    if (starts(v, "pad:", &rest)) {
        for (size_t i = 0; i < sizeof k_pad_buttons / sizeof k_pad_buttons[0]; i++) {
            if (is(rest, k_pad_buttons[i].name)) {
                out->kind = BIND_PAD;
                out->code = k_pad_buttons[i].mask;
                return true;
            }
        }
    }
    return false;
}

/* The binding as a [bindings] value (settings.h). A value is at most "pad:dpad_right", 14 bytes. */
void bind_describe(const Binding* b, char* out, size_t n)
{
    static const char HEX[] = "0123456789ABCDEF";
    char text[24];
    size_t at = 0;
    const char* name = "none";
    if (out == NULL || n == 0) return;
    text[0] = '\0';
    if (b != NULL) {
        switch (b->kind) {
        case BIND_WHEEL_UP: name = "wheel_up"; break;
        case BIND_WHEEL_DOWN: name = "wheel_down"; break;
        case BIND_MOUSE:
            if (b->code < 1 || b->code > 5) break;
            memcpy(text, "mouse", 5);
            text[5] = (char)('0' + b->code);
            text[6] = '\0';
            name = text;
            break;
        case BIND_KEY:
            if (b->code < 1 || b->code > 0xFE) break;
            memcpy(text, "key:", 4);
            at = 4;
            if (b->code >= '0' && b->code <= '9') {
                text[at++] = (char)b->code;
            } else if (b->code >= 'A' && b->code <= 'Z') {
                text[at++] = (char)(b->code + ('a' - 'A'));
            } else if (b->code >= 0x70 && b->code <= 0x87) { /* VK_F1 .. VK_F24 */
                int number = b->code - 0x70 + 1;
                text[at++] = 'f';
                if (number >= 10) text[at++] = (char)('0' + number / 10);
                text[at++] = (char)('0' + number % 10);
            } else {
                text[at++] = '0';
                text[at++] = 'x';
                text[at++] = HEX[b->code >> 4];
                text[at++] = HEX[b->code & 15];
            }
            text[at] = '\0';
            name = text;
            break;
        case BIND_PAD:
            for (size_t i = 0; i < sizeof k_pad_buttons / sizeof k_pad_buttons[0]; i++) {
                if (k_pad_buttons[i].mask != b->code) continue;
                memcpy(text, "pad:", 4);
                memcpy(text + 4, k_pad_buttons[i].name, strlen(k_pad_buttons[i].name) + 1);
                name = text;
                break;
            }
            break;
        default: break;
        }
    }
    at = strlen(name);
    if (at > n - 1) at = n - 1;
    memcpy(out, name, at);
    out[at] = '\0';
}

/* --- the lines ------------------------------------------------------------------------------------------------------- */

typedef enum { SEC_NONE, SEC_DBF, SEC_BINDINGS, SEC_BLACKLIST, SEC_HUD, SEC_SKIP } Section;

static const char* section_name(Section s)
{
    if (s == SEC_HUD) return "hud";
    return s == SEC_DBF ? "dbf" : s == SEC_BINDINGS ? "bindings" : "blacklist";
}

static void unknown_key(Problems* p, int line, Section sec, Span key)
{
    problem_begin(p, line);
    cur_str(p, "unknown key ");
    cur_quoted(p, key);
    cur_str(p, " in [");
    cur_str(p, section_name(sec));
    cur_str(p, "]");
    problem_end(p);
}

static void bad_value(Problems* p, int line, Span key, Span value, const char* expected)
{
    problem_begin(p, line);
    cur_str(p, "bad value ");
    cur_quoted(p, value);
    cur_str(p, " for ");
    cur_shown(p, key);
    cur_str(p, " (");
    cur_str(p, expected);
    cur_str(p, ")");
    problem_end(p);
}

static void set_bool(Problems* p, int line, Span key, Span value, bool* field)
{
    if (is(value, "true") || is(value, "1")) *field = true;
    else if (is(value, "false") || is(value, "0")) *field = false;
    else bad_value(p, line, key, value, "use true or false");
}

static bool* dbf_bool_field(DbfSettings* s, Span key)
{
    if (is(key, "enabled")) return &s->enabled;
    if (is(key, "selection_sounds")) return &s->selection_sounds;
    if (is(key, "randomize_input_delay")) return &s->randomize_input_delay;
    if (is(key, "instant_stratagems")) return &s->instant_stratagems;
    if (is(key, "hide_sos")) return &s->hide_sos;
    if (is(key, "hide_eagle_rearm")) return &s->hide_eagle_rearm;
    return NULL;
}

static void do_dbf(DbfSettings* s, Problems* p, int line, Span key, Span value)
{
    bool* flag = dbf_bool_field(s, key);
    int ms;
    if (flag != NULL) {
        set_bool(p, line, key, value, flag);
    } else if (is(key, "input_interval_ms")) {
        if (parse_decimal(value, &ms) && ms <= DBF_INTERVAL_MAX_MS) {
            s->input_interval_ms = ms;
        } else { /* like every other key, a bad value keeps what an earlier line (or the default) gave */
            problem_begin(p, line);
            cur_str(p, "input_interval_ms must be a whole number from 0 to 250, not ");
            cur_quoted(p, value);
            cur_str(p, " (keeping ");
            cur_number(p, s->input_interval_ms);
            cur_str(p, ")");
            problem_end(p);
        }
    } else {
        unknown_key(p, line, SEC_DBF, key);
    }
}

static void do_hud(int edits[HUD_OPTION_COUNT], Problems* p, int line, Span key, Span value)
{
    for (unsigned i = 0; i < hud_option_count(); ++i) {
        const HudOption* d = hud_option_descriptor(i);
        if (!is(key, d->key)) continue;
        int n;
        if (d->widget == HUD_TOGGLE) {
            if (is(value, "true") || is(value, "1")) n = 1;
            else if (is(value, "false") || is(value, "0")) n = 0;
            else {
                bad_value(p, line, key, value, "use true or false");
                return;
            }
        } else {
            Span digits = value;
            bool negative = starts(value, "-", &digits);
            if (!parse_decimal(digits, &n)) {
                bad_value(p, line, key, value, "use a whole number");
                return;
            }
            if (negative) n = -n;
        }
        if (n >= d->min && n <= d->max) edits[i] = n;
        else bad_value(p, line, key, value, "outside the option range");
        return;
    }
    unknown_key(p, line, SEC_HUD, key);
}

static void do_bindings(DbfSettings* s, Problems* p, int line, Span key, Span value)
{
    for (int a = 0; a < BIND_COUNT; a++) {
        Binding b;
        if (!is(key, k_action_names[a])) continue;
        if (parse_binding(value, &b)) s->bind[a] = b;
        else bad_value(p, line, key, value, "use none, wheel_up, wheel_down, mouse1..5, key:... or pad:...");
        return;
    }
    unknown_key(p, line, SEC_BINDINGS, key);
}

static void do_blacklist(DbfSettings* s, Problems* p, int line, Span key, Span value)
{
    Span id_text;
    int id;
    if (starts(key, "kind_", &id_text) && parse_decimal(id_text, &id) && id < DBF_BLACKLIST_SLOTS) {
        for (int i = 0; i < dbf_blacklist_kind_count; i++) {
            if ((int)dbf_blacklist_kinds[i].kind == id) {
                set_bool(p, line, key, value, &s->blacklist_kind[id]);
                return;
            }
        }
    }
    unknown_key(p, line, SEC_BLACKLIST, key);
}

/* A section header: the line starts with [ . Returns the section the lines after it belong to. */
static Section do_header(Problems* p, int line, Span t)
{
    Span name;
    if (t.p[t.n - 1] != ']') {
        problem_begin(p, line);
        cur_str(p, "a section header needs a closing ]");
        problem_end(p);
        return SEC_SKIP;
    }
    name = trim(t.p + 1, t.p + t.n - 1);
    if (is(name, "hud")) return SEC_HUD;
    if (is(name, "dbf")) return SEC_DBF;
    if (is(name, "bindings")) return SEC_BINDINGS;
    if (is(name, "blacklist")) return SEC_BLACKLIST;
    problem_begin(p, line);
    cur_str(p, "unknown section ");
    cur_quoted(p, name);
    problem_end(p);
    return SEC_SKIP;
}

int settings_parse(DbfSettings* s, const char* text, size_t len, char* problems, size_t n)
{
    Problems p;
    /* The preferences writer owns [hud]; older [dbf] values are fallbacks independent of section order. */
    int hud_edits[HUD_OPTION_COUNT];
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i) hud_edits[i] = INT_MIN;
    Section sec = SEC_NONE;
    size_t at = 0;
    int line = 0;

    memset(&p, 0, sizeof p);
    p.out = problems;
    p.cap = n;
    if (problems != NULL && n > 0) problems[0] = '\0';
    if (s == NULL) return 0;
    settings_defaults(s);
    if (text == NULL) len = 0;
    if (len >= 3 && memcmp(text, "\xEF\xBB\xBF", 3) == 0) at = 3; /* a UTF-8 byte order mark */

    while (at < len) {
        const char* begin = text + at;
        const char* newline = memchr(begin, '\n', len - at);
        const char* end = newline != NULL ? newline : text + len;
        Span t = trim(begin, end), key, value;
        const char* eq;
        at = newline != NULL ? (size_t)(newline - text) + 1 : len;
        line++;

        if (t.n == 0 || t.p[0] == ';' || t.p[0] == '#') continue;
        if (t.p[0] == '[') {
            sec = do_header(&p, line, strip_comment(t));
            continue;
        }
        if (sec == SEC_SKIP) continue; /* inside a section that was listed already */
        eq = memchr(t.p, '=', t.n);
        if (eq == NULL) {
            problem_begin(&p, line);
            cur_str(&p, "expected key = value");
            problem_end(&p);
            continue;
        }
        key = trim(t.p, eq);
        value = strip_comment((Span){ eq + 1, (size_t)(t.p + t.n - (eq + 1)) });
        if (key.n == 0) {
            problem_begin(&p, line);
            cur_str(&p, "no key before =");
            problem_end(&p);
            continue;
        }
        if (sec == SEC_NONE) {
            problem_begin(&p, line);
            cur_quoted(&p, key);
            cur_str(&p, " is not in a section");
            problem_end(&p);
            continue;
        }
        if (sec == SEC_DBF) do_dbf(s, &p, line, key, value);
        else if (sec == SEC_HUD) do_hud(hud_edits, &p, line, key, value);
        else if (sec == SEC_BINDINGS) do_bindings(s, &p, line, key, value);
        else do_blacklist(s, &p, line, key, value);
    }
    for (unsigned i = 0; i < HUD_OPTION_COUNT; ++i)
        if (hud_edits[i] != INT_MIN) hud_option_set(s, i, hud_edits[i]);
    return p.count;
}
