#ifndef DBF_HUD_OPTIONS_H
#define DBF_HUD_OPTIONS_H

#include <limits.h>
#include "settings.h"

typedef enum { HUD_TOGGLE, HUD_CHOICE, HUD_SLIDER } HudWidget;
typedef struct {
    const char *key, *label, *group;
    HudWidget widget;
    int initial, min, max, step;
    const char* const* choices; /* choice min is 1 */
    size_t offset;             /* bool for toggles, int otherwise */
} HudOption;

enum { HUD_OPTION_COUNT = 33 };
unsigned hud_option_count(void);
const HudOption* hud_option_descriptor(unsigned index);
const char* hud_option_key(unsigned index); /* NULL outside the table */
int hud_option_get(const DbfSettings* s, const char* key); /* INT_MIN on unknown key or NULL */
bool hud_option_set(DbfSettings* s, unsigned index, int value); /* false leaves s unchanged */
const char* hud_option_requirement(const DbfSettings* s, unsigned index); /* NULL when editable */
bool hud_option_available(const DbfSettings* s, unsigned index); /* R50 menu dependencies */
#endif
