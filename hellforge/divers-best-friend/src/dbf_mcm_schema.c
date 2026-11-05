#include "dbf_mcm_schema.h"
#include "hud_options.h"
#include "logic.h"
#include "addresses_25480438.h"
#include <stdio.h>
#include <string.h>

unsigned dbf_mcm_count(void)
{
    return hud_option_count() + BIND_COUNT + (unsigned)dbf_blacklist_kind_count;
}

bool dbf_mcm_key(unsigned index, char out[DBF_MCM_KEY_CAP])
{
    if (!out) return false;
    out[0] = 0;
    if (index >= dbf_mcm_count()) return false;
    int n;
    if (index < hud_option_count()) n = snprintf(out, DBF_MCM_KEY_CAP, "%s", hud_option_key(index));
    else {
        index -= hud_option_count();
        if (index < BIND_COUNT)
            n = snprintf(out, DBF_MCM_KEY_CAP, "bind_%s", settings_action_key(index));
        else n = snprintf(out, DBF_MCM_KEY_CAP, "kind_%u", dbf_blacklist_kinds[index - BIND_COUNT].kind);
    }
    return n > 0 && n < DBF_MCM_KEY_CAP;
}

typedef enum { UNKNOWN, HUD, BINDING, EXCLUSION } RowType;
typedef struct { RowType type; unsigned index; } Row;

static Row lookup(const char* id)
{
    if (id) {
        for (unsigned i = 0; i < hud_option_count(); ++i)
            if (!strcmp(id, hud_option_key(i))) return (Row){ HUD, i };
        if (!strncmp(id, "bind_", 5)) {
            for (unsigned i = 0; i < BIND_COUNT; ++i)
                if (!strcmp(id + 5, settings_action_key(i))) return (Row){ BINDING, i };
        }
        if (!strncmp(id, "kind_", 5)) {
            const char* p = id + 5;
            unsigned kind = 0;
            if (*p < '1' || *p > '9') return (Row){ UNKNOWN, 0 };
            for (; *p; ++p) {
                if (*p < '0' || *p > '9') return (Row){ UNKNOWN, 0 };
                kind = 10 * kind + (unsigned)(*p - '0');
                if (kind >= DBF_BLACKLIST_SLOTS) return (Row){ UNKNOWN, 0 };
            }
            for (int i = 0; i < dbf_blacklist_kind_count; ++i)
                if (dbf_blacklist_kinds[i].kind == kind) return (Row){ EXCLUSION, kind };
        }
    }
    return (Row){ UNKNOWN, 0 };
}

/* MCM v1 input accepts letters, digits, spaces, underscores and hyphens.
 * Only the device separator changes: pad:dpad_up <-> pad_dpad_up. */
static void binding_text(const Binding* binding, char text[DBF_MCM_TEXT_CAP])
{
    bind_describe(binding, text, DBF_MCM_TEXT_CAP);
    char* colon = strchr(text, ':');
    if (colon) *colon = '_';
}

static bool parse_input(const char* text, Binding* binding)
{
    if (!text) return false;
    char value[DBF_MCM_TEXT_CAP];
    size_t n = 0;
    for (; text[n]; ++n) {
        char c = text[n];
        if (n >= sizeof value - 1 || !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '_' || c == '-' || c == ' ')) return false;
        value[n] = c;
    }
    value[n] = 0;
    if (n > 4 && value[3] == '_') value[3] = ':';
    return settings_parse_binding(value, binding);
}

bool dbf_mcm_read(const DbfSettings* s, const char* id, McmValue* out, char text[DBF_MCM_TEXT_CAP])
{
    if (!s || !out) return false;
    Row row = lookup(id);
    switch (row.type) {
    case HUD: {
        int value = hud_option_get(s, id);
        if (hud_option_descriptor(row.index)->widget == HUD_TOGGLE)
            *out = (McmValue){ .type = MCM_BOOL, .boolean = value };
        else *out = (McmValue){ .type = MCM_NUMBER, .number = value };
        return true;
    }
    case BINDING:
        if (!text) return false;
        binding_text(&s->bind[row.index], text);
        *out = (McmValue){ .type = MCM_TEXT, .text = text };
        return true;
    case EXCLUSION:
        *out = (McmValue){ .type = MCM_BOOL, .boolean = logic_blacklisted(row.index, s) };
        return true;
    default: return false;
    }
}

bool dbf_mcm_write(DbfSettings* s, const char* id, const McmValue* value)
{
    if (!s || !value) return false;
    Row row = lookup(id);
    switch (row.type) {
    case HUD: {
        const HudOption* d = hud_option_descriptor(row.index);
        if (d->widget == HUD_TOGGLE)
            return value->type == MCM_BOOL && hud_option_set(s, row.index, value->boolean);
        if (value->type != MCM_NUMBER) return false;
        double v = value->number;
        return v >= d->min && v <= d->max && v == (int)v &&
               hud_option_set(s, row.index, (int)v);
    }
    case BINDING: {
        Binding b;
        return value->type == MCM_TEXT && parse_input(value->text, &b) && settings_set_binding(s, row.index, b);
    }
    case EXCLUSION:
        return value->type == MCM_BOOL && settings_set_blacklisted(s, row.index, value->boolean);
    default: return false;
    }
}

bool dbf_mcm_available(const DbfSettings* s, const char* id)
{
    Row row = lookup(id);
    return s && row.type != UNKNOWN && (row.type != HUD || hud_option_available(s, row.index));
}

/* Bounded JSON writer. Descriptors supply the strings; escape them as data. */
typedef struct { char* out; size_t cap, used; bool failed; } Json;

static void append(Json* j, const char* s)
{
    size_t n = strlen(s);
    if (j->failed || n >= j->cap - j->used) { j->failed = true; return; }
    memcpy(j->out + j->used, s, n + 1);
    j->used += n;
}

static void quoted(Json* j, const char* s)
{
    append(j, "\"");
    for (; *s && !j->failed; ++s) {
        if ((unsigned char)*s < 32) { j->failed = true; return; }
        if (*s == '"' || *s == '\\') append(j, "\\");
        append(j, (char[]){ *s, 0 });
    }
    append(j, "\"");
}

static void integer(Json* j, int n)
{
    char buf[24];
    snprintf(buf, sizeof buf, "%d", n);
    append(j, buf);
}

static void control(Json* j, const char* id, const char* label, const char* type)
{
    append(j, "{\"id\":"); quoted(j, id);
    append(j, ",\"label\":"); quoted(j, label);
    append(j, ",\"type\":"); quoted(j, type);
}

static void hud_control(Json* j, const HudOption* d)
{
    const char* type = d->widget == HUD_TOGGLE ? "toggle" : d->widget == HUD_CHOICE ? "choice" : "slider";
    control(j, d->key, d->label, type);
    append(j, ",\"enabled_if\":\"" DBF_MCM_CONDITION "\",\"default\":");
    if (d->widget == HUD_TOGGLE) append(j, d->initial ? "true" : "false");
    else integer(j, d->initial);
    if (d->widget == HUD_CHOICE) {
        append(j, ",\"presentation\":\"dropdown\",\"choices\":[");
        for (int i = d->min; i <= d->max; ++i) {
            if (i != d->min) append(j, ",");
            quoted(j, d->choices[i - d->min]);
        }
        append(j, "]");
    } else if (d->widget == HUD_SLIDER) {
        append(j, ",\"min\":"); integer(j, d->min);
        append(j, ",\"max\":"); integer(j, d->max);
        append(j, ",\"step\":"); integer(j, d->step);
        append(j, ",\"fine_step\":1"); /* DBF's INI accepts every integer in range. */
    }
    append(j, "}");
}

static void page(Json* j, const char* id, const char* label, const char* category)
{
    append(j, "{\"id\":"); quoted(j, id);
    append(j, ",\"name\":"); quoted(j, label);
    append(j, ",\"category\":"); quoted(j, category);
    append(j, ",\"controls\":[");
}

size_t dbf_mcm_schema(char* out, size_t cap)
{
    if (!out || !cap) return 0;
    Json j = { .out = out, .cap = cap };
    append(&j, "{\"id\":\"" DBF_MCM_ID "\",\"name\":\"Diver's Best Friend\",\"storage\":true,"
               "\"categories\":[{\"id\":\"settings\",\"name\":\"Settings\"},"
               "{\"id\":\"configuration\",\"name\":\"Controls and exclusions\"}],\"pages\":[");
    static const struct { const char *group, *id, *label; } pages[] = {
        {"SELECTION", "selection", "Selection"}, {"APPEARANCE", "appearance", "Appearance"},
        {"LIST SELECT", "list_select", "List Select"}, {"HUD LAYOUT", "hud_layout", "HUD layout"},
        {"COOLDOWN DISPLAY", "cooldown", "Cooldown display"}, {"TERMINALS", "terminals", "Terminals"},
        {"ADVANCED", "advanced", "Advanced"}
    };
    unsigned emitted = 0;
    for (unsigned p = 0; p < sizeof pages / sizeof pages[0]; ++p) {
        if (p) append(&j, ",");
        page(&j, pages[p].id, pages[p].label, "settings");
        bool first = true;
        for (unsigned i = 0; i < hud_option_count(); ++i) {
            const HudOption* d = hud_option_descriptor(i);
            if (strcmp(d->group, pages[p].group)) continue;
            if (!first) append(&j, ",");
            hud_control(&j, d);
            first = false;
            ++emitted;
        }
        append(&j, "]}");
    }
    append(&j, ",");
    page(&j, "bindings", "Bindings", "configuration");
    static const char* const actions[BIND_COUNT] = {
        "Next stratagem", "Previous stratagem", "Confirm", "Slot 1", "Slot 2", "Slot 3", "Slot 4"
    };
    DbfSettings defaults;
    settings_defaults(&defaults);
    char key[DBF_MCM_KEY_CAP], text[DBF_MCM_TEXT_CAP];
    for (unsigned i = 0; i < BIND_COUNT; ++i) {
        if (i) append(&j, ",");
        if (!dbf_mcm_key(hud_option_count() + i, key)) j.failed = true;
        control(&j, key, actions[i], "input");
        append(&j, ",\"description\":\"Examples: key_f1, mouse1, wheel_up, pad_dpad_right or none.\",\"default\":");
        binding_text(&defaults.bind[i], text);
        quoted(&j, text);
        append(&j, "}");
    }
    append(&j, "]},");
    page(&j, "exclusions", "Mission exclusions", "configuration");
    for (int i = 0; i < dbf_blacklist_kind_count; ++i) {
        const DbfBlacklistKind* k = &dbf_blacklist_kinds[i];
        if (i) append(&j, ",");
        if (!dbf_mcm_key(hud_option_count() + BIND_COUNT + (unsigned)i, key)) j.failed = true;
        char label[128];
        int n = snprintf(label, sizeof label, "%s (%u)", k->name, k->kind);
        if (n < 0 || (size_t)n >= sizeof label) j.failed = true;
        control(&j, key, label, "toggle");
        append(&j, k->default_on ? ",\"default\":true}" : ",\"default\":false}");
    }
    append(&j, "]}]}");
    if (j.failed || emitted != hud_option_count()) { out[0] = 0; return 0; }
    return j.used;
}
