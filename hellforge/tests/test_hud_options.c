#include <string.h>
#include "fake_ov.h"
#include "hud_options.h"
#include "snapshot.h"
#include "test.h"
#include "ui_settings.h"

static void parser(void)
{
    DbfSettings s;
    char problems[512];
    const char ini[] =
        "[HuD]\nvertical_offset=-125 ; up\nvertical_offset=-601\nweapon_status_strip=false\n"
        "cooldown_display=3\ncooldown_display=0\nrelease_selection_mode=2\n"
        "selection_mode_ordered=9999999999999999\nwheel_size=true\nmissing=1\n"
        "input_interval_ms=85\nenabled=0\n[dbf]\nenabled=true\ninput_interval_ms=40\n"
        "selection_sounds=false\nhide_sos=1\nhide_eagle_rearm=1\n"
        "[bindings]\nnext=wheel_up\n[blacklist]\nkind_5=true\n";
    CHECK(settings_parse(&s, ini, sizeof ini - 1, problems, sizeof problems) == 5, "invalid lines counted");
    CHECK(strstr(problems, "unknown key") && strstr(problems, "[hud]"), "unknown HUD key diagnostic");
    CHECK(!s.enabled && s.input_interval_ms == 85 && !s.selection_sounds, "HUD values take priority over legacy fallbacks");
    CHECK(s.blacklist_kind[5] && s.bind[BIND_NEXT].kind == BIND_WHEEL_UP && hud_option_get(&s, "hide_sos") == 1 &&
          hud_option_get(&s, "hide_eagle_rearm") == 1, "existing blacklist, bindings and runtime filters");
    CHECK(!s.weapon_status_strip && s.vertical_offset == -125 && s.cooldown_display == 3 && s.release_selection_mode == 2,
          "signed offsets, bools and one-based choices, invalid duplicates preserve the previous value");
    CHECK(s.selection_mode_ordered == 1 && s.wheel_size == 100, "invalid values preserve defaults");
    CHECK(hud_option_get(&s, "") == INT_MIN && hud_option_get(NULL, "enabled") == INT_MIN &&
          hud_option_key(hud_option_count()) == NULL && !hud_option_set(&s, (unsigned)-1, 0), "unknown indices and keys");
}

static void descriptors(void)
{
    DbfSettings s, parsed;
    char ini[2048] = "[hud]\n";
    settings_defaults(&s);
    bool valid = true;
    for (unsigned i = 0; i < hud_option_count(); ++i) {
        const HudOption* d = hud_option_descriptor(i);
        valid &= hud_option_get(&s, d->key) == d->initial;
        valid &= hud_option_set(&s, i, d->min);
        valid &= !hud_option_set(&s, i, d->max + 1) && !hud_option_set(&s, i, d->min - 1);
        valid &= hud_option_get(&s, d->key) == d->min;
        valid &= hud_option_set(&s, i, d->max) && hud_option_get(&s, d->key) == d->max;
        for (unsigned j = 0; j < i; ++j) valid &= strcmp(d->key, hud_option_key(j)) != 0;
        size_t len = strlen(ini);
        int n = snprintf(ini + len, sizeof ini - len, "%s=%d\n", d->key, d->max);
        valid &= n > 0 && (size_t)n < sizeof ini - len;
    }
    CHECK(valid, "every descriptor has a unique key, initializes its default and validates its range");
    CHECK(settings_parse(&parsed, ini, strlen(ini), NULL, 0) == 0 && !memcmp(&s, &parsed, sizeof s),
          "writer-style enumeration round trips all controls");
}

/* Adversarial fake: even a disabled slider reports an edit. */
static bool disabled, list_enabled, icon_disabled;
static void begin_disabled(int flag) { disabled = flag != 0; }
static void end_disabled(void) { disabled = false; }
static int checkbox(const char* label, int* value)
{
    if (!strcmp(label, "Dim unselected stratagems")) list_enabled = !disabled;
    if (strcmp(label, "Show weapon status strip")) return 0;
    *value = 0;
    return 1;
}
static int slider(const char* label, int* value, int min, int max)
{
    if (!strcmp(label, "Icon size (%)")) icon_disabled = disabled;
    else if (strcmp(label, "Dock gap above stamina")) return 0;
    *value = min + 3;
    return 1;
}
static int combo(const char* label, int* value, const char* const* choices, int count)
{
    if (strcmp(label, "Selection mode")) return 0;
    CHECK(*value == 0 && count == 3 && !strcmp(choices[1], "List Select"), "R50 mode choices use zero-based ImGui indices");
    *value = 1;
    return 1;
}
static void render(void)
{
    DbfSnapshot snap = {0};
    UiEvent events[5];
    OvApi ov = *fake_ov_api();
    ov.begin_disabled = begin_disabled;
    ov.end_disabled = end_disabled;
    ov.checkbox = checkbox;
    ov.slider_int = slider;
    ov.combo = combo;
    fake_ov_reset();
    snap_init();
    settings_defaults(&snap.options);
    snap.hud_owned = true;
    ui_settings_draw(&ov, &snap);
    CHECK(fake_ov_find("tab:SETTINGS", 0) >= 0 && fake_ov_find("text:Private HUD: connected", 0) >= 0,
          "settings tab and connected archive diagnostic");
    CHECK(icon_disabled && list_enabled, "mode change updates dependent controls within the same draw");
    CHECK(snap.options.selection_mode_ordered == 1 && snap.options.weapon_status_strip && snap.options.dock_gap == 24,
          "edits never mutate the published snapshot");
    int n = ui_drain(events, 5);
    CHECK(n == 3, "three changed controls post; disabled slider stays silent");
    const char* expected[] = {"selection_mode_ordered", "weapon_status_strip", "dock_gap"};
    const int values[] = {2, 0, 4};
    for (int i = 0; i < n && i < 3; ++i) {
        const char* key = hud_option_key((unsigned)events[i].a);
        CHECK(events[i].kind == UI_HUD_OPTION && key && !strcmp(key, expected[i]) && events[i].b == values[i],
              "UI event carries the descriptor index and domain value");
    }
    snap.hud_owned = false;
    fake_ov_reset();
    ui_settings_draw(&ov, &snap);
    CHECK(fake_ov_find("text:Private HUD: waiting", 0) >= 0, "waiting archive diagnostic");
}
int main(void)
{
    parser();
    descriptors();
    render();
    TEST_MAIN_END
}
