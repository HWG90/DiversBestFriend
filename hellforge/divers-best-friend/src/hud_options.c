/* Portable settings shared by the UI, INI reader and native HUD bridge. */
#include <string.h>
#include "hud_options.h"

static const char* const selection_mode_ordered_choices[] = { "Wedge Wheel", "List Select", "Native wheel" };
static const char* const experimental_layout_choices[] = { "Cards - copied list rows", "Expanded wedges" };
static const char* const appearance_preset_choices[] = { "Custom", "Compact", "Standard", "Large" };
static const char* const cooldown_timer_choices[] = { "Off", "Above icon", "Below icon", "Inside icon" };
static const char* const short_timer_style_choices[] = { "Use cooldown position", "Large inside icon" };
static const char* const cooldown_display_choices[] = { "Icon dock", "Compact overview", "Compact row" };
static const char* const short_status_placement_choices[] = { "Together", "Left of dock", "Right of dock", "Below stamina bar" };
static const char* const release_selection_mode_choices[] = { "Automatic (controller)", "On", "Off" };

#define OPTION(field, label, group, widget, initial, min, max, step, choices) \
    { #field, label, group, widget, initial, min, max, step, choices, offsetof(DbfSettings, field) }
static const HudOption options[] = {
    OPTION(enabled, "Enable Mod", "SELECTION", HUD_TOGGLE, true, 0, 1, 1, NULL),
    OPTION(selection_sounds, "Sound feedback", "SELECTION", HUD_TOGGLE, true, 0, 1, 1, NULL),
    OPTION(release_selection_mode, "Select on Release", "SELECTION", HUD_CHOICE, 1, 1, 3, 1, release_selection_mode_choices),
    OPTION(selection_mode_ordered, "Mode", "APPEARANCE", HUD_CHOICE, 1, 1, 3, 1, selection_mode_ordered_choices),
    OPTION(experimental_layout, "Wedge Wheel layout", "APPEARANCE", HUD_CHOICE, 2, 1, 2, 1, experimental_layout_choices),
    OPTION(appearance_preset, "Preset", "APPEARANCE", HUD_CHOICE, 1, 1, 4, 1, appearance_preset_choices),
    OPTION(wheel_size, "Wheel size (%)", "APPEARANCE", HUD_SLIDER, 100, 70, 130, 5, NULL),
    OPTION(icon_size, "Icon size (%)", "APPEARANCE", HUD_SLIDER, 100, 70, 130, 5, NULL),
    OPTION(label_size, "Center label size (%)", "APPEARANCE", HUD_SLIDER, 100, 70, 130, 5, NULL),
    OPTION(native_opacity, "Native wheel opacity (%)", "APPEARANCE", HUD_SLIDER, 100, 0, 100, 5, NULL),
    OPTION(wedge_darkness, "Expanded wedge darkness (%)", "APPEARANCE", HUD_SLIDER, 70, 0, 100, 5, NULL),
    OPTION(wedge_opacity, "Wedge opacity (%)", "APPEARANCE", HUD_SLIDER, 50, 0, 100, 5, NULL),
    OPTION(dim_unselected, "Dim unselected stratagems", "APPEARANCE", HUD_TOGGLE, true, 0, 1, 1, NULL),
    OPTION(hide_blacklisted_list, "Hide blacklisted stratagems", "APPEARANCE", HUD_TOGGLE, false, 0, 1, 1, NULL),
    OPTION(hide_cooldown_list, "Hide stratagems on cooldown", "APPEARANCE", HUD_TOGGLE, false, 0, 1, 1, NULL),
    OPTION(hide_closed_status, "Hide top-left status notices", "APPEARANCE", HUD_TOGGLE, true, 0, 1, 1, NULL),
    OPTION(vertical_offset, "Radial vertical offset (down)", "APPEARANCE", HUD_SLIDER, 0, -600, 600, 25, NULL),
    OPTION(weapon_status_strip, "Show weapon status strip", "APPEARANCE", HUD_TOGGLE, true, 0, 1, 1, NULL),
    OPTION(cooldown_timers, "Show cooldown timers", "COOLDOWN DISPLAY", HUD_TOGGLE, true, 0, 1, 1, NULL),
    OPTION(cooldown_timer, "Cooldown timer position", "COOLDOWN DISPLAY", HUD_CHOICE, 2, 1, 4, 1, cooldown_timer_choices),
    OPTION(short_timer_style, "Short countdown style", "COOLDOWN DISPLAY", HUD_CHOICE, 2, 1, 2, 1, short_timer_style_choices),
    OPTION(brief_timer_limit, "Brief cooldown threshold", "COOLDOWN DISPLAY", HUD_SLIDER, 10, 1, 30, 1, NULL),
    OPTION(dock_gap, "Dock gap above stamina", "COOLDOWN DISPLAY", HUD_SLIDER, 24, 0, 80, 2, NULL),
    OPTION(cooldown_icons, "Show cooldown display", "COOLDOWN DISPLAY", HUD_TOGGLE, true, 0, 1, 1, NULL),
    OPTION(cooldown_display, "Cooldown display style", "COOLDOWN DISPLAY", HUD_CHOICE, 1, 1, 3, 1, cooldown_display_choices),
    OPTION(short_status_placement, "Short status placement", "COOLDOWN DISPLAY", HUD_CHOICE, 3, 1, 4, 1, short_status_placement_choices),
    OPTION(track_unavailable, "Track unavailable / ineligible", "COOLDOWN DISPLAY", HUD_TOGGLE, false, 0, 1, 1, NULL),
    OPTION(balance_separated_dock, "Center Cooldown Separator", "COOLDOWN DISPLAY", HUD_TOGGLE, true, 0, 1, 1, NULL),
    OPTION(input_interval_ms, "Input interval (ms)", "ADVANCED", HUD_SLIDER, DBF_INTERVAL_DEFAULT_MS, 0, DBF_INTERVAL_MAX_MS, 5, NULL),
    OPTION(randomize_input_delay, "Randomize input delay", "ADVANCED", HUD_TOGGLE, false, 0, 1, 1, NULL),
    OPTION(instant_stratagems, "Instant complete Stratagems", "ADVANCED", HUD_TOGGLE, false, 0, 1, 1, NULL),
};

_Static_assert(HUD_OPTION_COUNT == sizeof options / sizeof options[0], "HUD parser capacity");

unsigned hud_option_count(void)
{
    return sizeof options / sizeof options[0];
}

const HudOption* hud_option_descriptor(unsigned index)
{
    return index < hud_option_count() ? &options[index] : NULL;
}

const char* hud_option_key(unsigned index)
{
    return index < hud_option_count() ? options[index].key : NULL;
}

int hud_option_get(const DbfSettings* s, const char* key)
{
    if (!s || !key) return INT_MIN;
    /* Existing [dbf] filters are read by the bridge but are not HUD editor controls. */
    if (!strcmp(key, "hide_sos")) return s->hide_sos;
    if (!strcmp(key, "hide_eagle_rearm")) return s->hide_eagle_rearm;
    for (unsigned i = 0; i < hud_option_count(); ++i) {
        const HudOption* d = &options[i];
        if (strcmp(key, d->key) != 0) continue;
        const void* field = (const char*)s + d->offset;
        return d->widget == HUD_TOGGLE ? *(const bool*)field : *(const int*)field;
    }
    return INT_MIN;
}

bool hud_option_set(DbfSettings* s, unsigned index, int value)
{
    const HudOption* d = hud_option_descriptor(index);
    if (!s || !d || value < d->min || value > d->max) return false;
    void* field = (char*)s + d->offset;
    if (d->widget == HUD_TOGGLE) *(bool*)field = value != 0;
    else *(int*)field = value;
    return true;
}

bool hud_option_available(const DbfSettings* s, unsigned index)
{
    const HudOption* d = hud_option_descriptor(index);
    if (!s || !d) return false;
    bool wedge = s->selection_mode_ordered == 1;
    bool list = s->selection_mode_ordered == 2;
    bool native = s->selection_mode_ordered == 3;
    bool expanded = wedge && s->experimental_layout == 2;
    bool custom = s->appearance_preset == 1;
    bool dock = s->cooldown_icons && s->cooldown_display == 1;
#define FIELD(name) offsetof(DbfSettings, name)
    switch (d->offset) {
    case FIELD(input_interval_ms): return !s->randomize_input_delay && !s->instant_stratagems;
    case FIELD(randomize_input_delay): return !s->instant_stratagems;
    case FIELD(experimental_layout): return wedge;
    case FIELD(wedge_darkness): case FIELD(wedge_opacity): return expanded;
    case FIELD(native_opacity): return native;
    case FIELD(wheel_size): return !list && custom;
    case FIELD(icon_size): case FIELD(label_size): return (expanded || native) && custom;
    case FIELD(vertical_offset): return !list;
    case FIELD(dim_unselected): case FIELD(hide_blacklisted_list): case FIELD(hide_cooldown_list): return list;
    case FIELD(cooldown_display): case FIELD(dock_gap): case FIELD(track_unavailable):
    case FIELD(cooldown_timers): case FIELD(brief_timer_limit): return s->cooldown_icons;
    case FIELD(short_status_placement): return dock;
    case FIELD(balance_separated_dock):
        return dock && (s->short_status_placement == 2 || s->short_status_placement == 3);
    case FIELD(cooldown_timer): case FIELD(short_timer_style): return s->cooldown_icons && s->cooldown_timers;
    default: return true;
    }
#undef FIELD
}
