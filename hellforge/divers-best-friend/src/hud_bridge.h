#ifndef DBF_HUD_BRIDGE_H
#define DBF_HUD_BRIDGE_H
#include "game.h"
#include "settings.h"

/* C tick / engine Lua update handoff. Only the tick may grant a lease after
 * releasing native list styling, entry bytes and the shortcut latch. */
typedef struct HudBridgePort {
    int (*read)(uintptr_t, void*, size_t);
    int (*read_code)(uintptr_t, void*, size_t);
    int (*rewrites)(uint32_t, uint32_t);
    void (*log)(const char*);
} HudBridgePort;
void hud_bridge_init(uintptr_t base, size_t size, const HudBridgePort* port);
bool hud_bridge_requested(void);
void hud_bridge_publish(const GameView* view, const DbfSettings* settings, int buttons,
                        bool verified, bool can_grant);
bool hud_bridge_owned(void);
#endif
