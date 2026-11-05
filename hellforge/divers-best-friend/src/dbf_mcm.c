#include "dbf_mcm.h"
#include "dbf_mcm_schema.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Both mods are session-resident and every entry point runs on the game thread. */
static const McmApi *api;
static McmMod *mod;
static const DbfSettings *live;
static bool (*save_dbf)(const DbfSettings *);
static bool mirroring, have_checkpoint;
static DbfSettings last_sync;
/* Registration and set_many consume JSON synchronously. Their provider callbacks
 * never enter tick, so both can share this buffer off the game thread's stack. */
static char json_buffer[DBF_MCM_SCHEMA_CAP];

bool dbf_mcm_registered(void) { return mod != NULL; }
bool dbf_mcm_open(void) { return api && api->is_open && api->is_open(); }

static bool same(const McmValue *a, const McmValue *b)
{
    if (a->type != b->type) return false;
    switch (a->type) {
    case MCM_BOOL: return !!a->boolean == !!b->boolean;
    case MCM_NUMBER: return a->number == b->number;
    case MCM_TEXT: return a->text && b->text && !strcmp(a->text, b->text);
    default: return false;
    }
}

/* Schema IDs and binding tokens use only letters, digits and underscores.
 * Provider text values carry an @ prefix; set_many takes quoted JSON strings. */
static int append_value(char *dst, size_t cap, const char *key, const McmValue *v, bool json)
{
    const char *prefix = "", *suffix = "", *body;
    char number[32];
    switch (v->type) {
    case MCM_NUMBER:
        snprintf(number, sizeof number, "%d", (int)v->number);
        body = number;
        break;
    case MCM_BOOL: body = v->boolean ? "true" : "false"; break;
    case MCM_TEXT:
        prefix = json ? "\"" : "@";
        suffix = json ? "\"" : "";
        body = v->text;
        break;
    default: return -1;
    }
    int n = snprintf(dst, cap, json ? "\"%s\":%s%s%s," : "%s=%s%s%s\n", key, prefix, body, suffix);
    return n >= 0 && (size_t)n < cap ? n : -1;
}

static int load_values(void *user, char *buffer, size_t size)
{
    if (!buffer || !size) return -1;
    size_t at = 0;
    for (unsigned i = 0; i < dbf_mcm_count(); ++i) {
        char key[DBF_MCM_KEY_CAP], text[DBF_MCM_TEXT_CAP];
        McmValue value;
        if (!dbf_mcm_key(i, key) || !dbf_mcm_read(live, key, &value, text)) return -1;
        int n = append_value(buffer + at, size - at, key, &value, false);
        if (n < 0) return -1;
        at += n;
    }
    memcpy(&last_sync, live, sizeof last_sync);
    have_checkpoint = true;
    return (int)at;
}

static bool decode(const char *token, McmValue *v)
{
    if (*token == '@') {
        *v = (McmValue){.type = MCM_TEXT, .text = token + 1};
    } else if (!strcmp(token, "true") || !strcmp(token, "false")) {
        *v = (McmValue){.type = MCM_BOOL, .boolean = *token == 't'};
    } else {
        const char *digits = token + (*token == '-');
        if (!*digits || digits[strspn(digits, "0123456789")]) return false;
        /* Every DBF number fits comfortably in nine decimal digits. */
        if (strlen(digits) > 9) return false;
        *v = (McmValue){.type = MCM_NUMBER, .number = strtol(token, NULL, 10)};
    }
    return true;
}

static int save_values(void *user, const char *data, size_t length)
{
    if (mirroring) return 1; /* DBF already saved these values. */
    if (!mod || !data || !length || length > 65536 || memchr(data, 0, length)) return 0;
    DbfSettings candidate = *live, checkpoint = last_sync;
    bool changed = false;
    const char *end = data + length;
    while (data < end) {
        const char *line_end = memchr(data, '\n', (size_t)(end - data));
        if (!line_end) line_end = end;
        const char *eq = memchr(data, '=', (size_t)(line_end - data));
        char key[DBF_MCM_KEY_CAP], token[DBF_MCM_TEXT_CAP + 1];
        if (!eq || eq == data || (size_t)(eq - data) >= sizeof key) return 0;
        size_t len = (size_t)(line_end - eq - 1);
        if (len && eq[len] == '\r') --len;
        if (!len || len >= sizeof token) return 0;
        memcpy(key, data, (size_t)(eq - data));
        key[eq - data] = 0;
        memcpy(token, eq + 1, len);
        token[len] = 0;
        McmValue before, after;
        if (!decode(token, &after) || !api->get(mod, key, &before)) return 0;
        /* MCM submits its entire saved map. Apply only its actual edits to the
         * latest DBF snapshot, including F7 edits made since our previous tick. */
        if (!same(&before, &after)) {
            if (!dbf_mcm_write(&candidate, key, &after) || !dbf_mcm_write(&checkpoint, key, &after)) return 0;
            changed = true;
        }
        data = line_end + (line_end != end);
    }
    if (changed && memcmp(&candidate, live, sizeof candidate) && !save_dbf(&candidate)) return 0;
    last_sync = checkpoint;
    return 1;
}

static int validate(void *user, const char *id, const McmValue *value)
{
    DbfSettings candidate = *live;
    return dbf_mcm_write(&candidate, id, value);
}

static int condition(void *user, const char *handler, const char *id)
{
    if (!handler || strcmp(handler, DBF_MCM_CONDITION) || !id) return -1;
    if (mirroring) return 1;
    McmMod *owner = mod ? mod : api->find(DBF_MCM_ID);
    if (!owner) return -1;
    /* The inputs to hud_option_requirement. An unconfirmed choice on any
     * page already affects which controls the user can edit. */
    static const char *const inputs[] = {
        "selection_mode_ordered", "experimental_layout", "appearance_preset",
        "cooldown_icons", "cooldown_display", "short_status_placement", "cooldown_timers",
        "instant_stratagems", "auto_terminal_complete", "terminal_input", "randomize_input_delay"
    };
    DbfSettings draft = *live;
    for (size_t i = 0; i < sizeof inputs / sizeof *inputs; ++i) {
        McmValue v;
        if (!api->preview(owner, inputs[i], &v) || !dbf_mcm_write(&draft, inputs[i], &v)) return -1;
    }
    return dbf_mcm_available(&draft, id);
}

static bool sync_values(void)
{
    json_buffer[0] = '{';
    size_t at = 1;
    for (unsigned i = 0; i < dbf_mcm_count(); ++i) {
        char key[DBF_MCM_KEY_CAP], text[DBF_MCM_TEXT_CAP];
        McmValue saved, target;
        if (!dbf_mcm_key(i, key) || !dbf_mcm_read(live, key, &target, text)) return false;
        char old_text[DBF_MCM_TEXT_CAP];
        if (have_checkpoint && dbf_mcm_read(&last_sync, key, &saved, old_text) && same(&saved, &target)) continue;
        if (!api->get(mod, key, &saved)) return false;
        if (same(&saved, &target)) continue;
        int n = append_value(json_buffer + at, sizeof json_buffer - at, key, &target, true);
        if (n < 0) return false;
        at += n;
    }
    if (at == 1) return true;
    json_buffer[at - 1] = '}';
    /* set_many updates saved values without discarding page drafts. Its v1
     * implementation checks enabled_if even for programmatic writes. */
    mirroring = true;
    api->refresh_conditions(mod);
    bool ok = api->set_many(mod, json_buffer, at) != 0;
    mirroring = false;
    api->refresh_conditions(mod);
    return ok;
}

void dbf_mcm_tick(const DbfSettings *current, bool (*persist)(const DbfSettings *),
                  const McmApi *(*resolve)(void))
{
    if (!api) api = resolve ? resolve() : mcm_connect();
    if (!api || !current || !persist) return;
    live = current;
    save_dbf = persist;
    if (!mod) {
        /* An incompatible schema or occupied id can persist for the session.
         * Avoid parsing and logging a failed registration on every game frame. */
        static unsigned retry_ticks;
        if (retry_ticks) { --retry_ticks; return; }
        size_t size = dbf_mcm_schema(json_buffer, sizeof json_buffer);
        McmCallbacks callbacks = {.size = sizeof callbacks, .validate = validate, .condition = condition,
                                  .load = load_values, .save = save_values};
        have_checkpoint = false;
        if (size) mod = api->register_mod(json_buffer, size, &callbacks);
        if (!mod) { retry_ticks = 300; return; }
    }
    if (have_checkpoint && !memcmp(&last_sync, current, sizeof last_sync)) return;
    if (sync_values()) {
        memcpy(&last_sync, current, sizeof last_sync);
        have_checkpoint = true;
    }
}
