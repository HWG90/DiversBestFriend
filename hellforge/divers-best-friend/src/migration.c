#include "migration.h"
#include "addresses_25480438.h"
#include "hud_options.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>

/* ModOptionsMenu and mission_blacklist.lua store tab-separated key/value pairs.
 * Keep pointers to the last value per key, just as Lua's saved table does. */
typedef struct {
    const char* option[HUD_OPTION_COUNT];
    const char* mode;
    const char* release;
    const char* slots[8];
    const char* sos;
    const char* rearm;
} MenuValues;

static bool pair(char** cursor, char** key, char** value)
{
    while (*cursor && **cursor) {
        char* line = *cursor;
        char* end = strpbrk(line, "\r\n");
        if (end) *end++ = 0;
        *cursor = end;
        char* tab = strchr(line, '\t');
        if (tab && tab != line) {
            *tab = 0;
            *key = line;
            *value = tab + 1;
            return true;
        }
    }
    return false;
}

static int number(const char* value)
{
    if (!value || !*value) return INT_MIN;
    char* end;
    errno = 0;
    long n = strtol(value, &end, 10);
    return !errno && !*end && n > INT_MIN && n <= INT_MAX ? (int)n : INT_MIN;
}

static int toggle(const char* value)
{
    if (value && !strcmp(value, "true")) return 1;
    if (value && !strcmp(value, "false")) return 0;
    return INT_MIN;
}

static bool hide(DbfSettings* s, int kind)
{
    if (kind == DBF_VAL_HIDE_SOS_KIND) s->hide_sos = true;
    else if (kind == DBF_VAL_HIDE_EAGLE_REARM_KIND) s->hide_eagle_rearm = true;
    else {
        for (int i = 0; i < dbf_blacklist_kind_count; ++i) {
            if (kind >= 0 && kind < DBF_BLACKLIST_SLOTS && dbf_blacklist_kinds[i].kind == (unsigned)kind) {
                s->blacklist_kind[kind] = true;
                return true;
            }
        }
        return false;
    }
    return true;
}

/* Inverse of R50 stratagems.lua old_to_current[0..149]. These four inserted
 * current-build IDs have no target equivalent. Never infer a custom kind. */
static int target_kind(int current)
{
    if (current < 0 || current > 153 || current == 28 || current == 50 || current == 66 || current == 145)
        return -1;
    return current - (current > 28) - (current > 50) - (current > 66) - (current > 145);
}

static void menu_values(MenuValues* menu, char* input)
{
    static const char prefix[] = "native_stratagem_radial.";
    static const char slot_prefix[] = "blacklist_kind_";
    char *key, *v;
    while (pair(&input, &key, &v)) {
        if (strncmp(key, prefix, sizeof prefix - 1)) continue;
        key += sizeof prefix - 1;
        if (!strcmp(key, "selection_mode")) menu->mode = v;
        else if (!strcmp(key, "select_on_release")) menu->release = v;
        else if (!strcmp(key, "hide_sos")) menu->sos = v;
        else if (!strcmp(key, "hide_eagle_rearm")) menu->rearm = v;
        else if (!strncmp(key, slot_prefix, sizeof slot_prefix - 1)) {
            const char* index = key + sizeof slot_prefix - 1;
            if (*index >= '1' && *index <= '8' && !index[1]) menu->slots[*index-'1'] = v;
        } else {
            for (unsigned i=0; i<hud_option_count(); ++i)
                if (!strcmp(key, hud_option_key(i))) { menu->option[i] = v; break; }
        }
    }
}

static bool blacklist_values(DbfSettings* s, const MenuValues* menu, char* input)
{
    const char* saved[154] = {0}; /* includes every R50 ID and the three v1 slots */
    const char* version = NULL;
    char *key, *v;
    while (pair(&input, &key, &v)) {
        if (!strcmp(key, "version")) version = v;
        else {
            int index = number(key);
            if (index >= 0 && index < 154) saved[index] = v;
        }
    }
    if (version && !strcmp(version, "1")) {
        for (int i=1; i<=3; ++i) hide(s, number(saved[i]));
        return true;
    }
    if (version && (!strcmp(version, "2") || !strcmp(version, "3"))) {
        for (int i=0; i<154; ++i)
            if (toggle(saved[i]) == 1) hide(s, *version == '3' ? target_kind(i) : i);
        return true; /* even an empty versioned file overrides all legacy slots */
    }
    int sos = toggle(menu->sos), rearm = toggle(menu->rearm);
    bool found = sos != INT_MIN || rearm != INT_MIN;
    for (int i=0; i<8; ++i)
        if (hide(s, number(menu->slots[i]))) found = true;
    if (sos == 1) s->hide_sos = true;
    if (rearm == 1) s->hide_eagle_rearm = true;
    return found;
}

bool migration_parse(DbfSettings* s, char* options, char* blacklist)
{
    MenuValues menu = {0};
    menu_values(&menu, options);
    bool found = blacklist_values(s, &menu, blacklist);
    int mode = number(menu.mode), release = toggle(menu.release);
    if (mode >= 1 && mode <= 3) {
        s->selection_mode_ordered = 4-mode;
        found = true;
    }
    if (release != INT_MIN) {
        s->release_selection_mode = release ? 2 : 1;
        found = true;
    }
    for (unsigned i=0; i<hud_option_count(); ++i) {
        if (!menu.option[i]) continue;
        const HudOption* d = hud_option_descriptor(i);
        int value = d->widget == HUD_TOGGLE ? toggle(menu.option[i]) : number(menu.option[i]);
        if (hud_option_set(s, i, value)) found = true;
    }
    if (mode == 4) { /* entry.lua's migration after canary_settings registration */
        s->selection_mode_ordered = 1;
        s->experimental_layout = 2;
        found = true;
    }
    return found;
}
