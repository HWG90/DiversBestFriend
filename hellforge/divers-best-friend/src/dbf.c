/* Diver's Best Friend (goose.divers-best-friend), the native HellForge port for game build 25480438.
 *
 * This is the entry point. It keeps the loader's pointers and says which build it is; the rest of the mod registers from
 * here as it is added. It needs SDK 13's read_code (the bytes of game code as they were before any hook), so a HellForge
 * older than that gets a line in the log and nothing registered. */
#include <stddef.h>
#include "hellforge_mod.h"

#define DBF_VERSION "R50-hellforge.1"
#define DBF_GAME_BUILD "25480438"

static const HfApi* g_hf;
static HfMod* g_mod;

HF_MOD_EXPORT int hellforge_mod_init(const HfApi* hf, HfMod* mod)
{
    g_hf = hf;
    g_mod = mod;
    if (hf->size < offsetof(HfApi, read_code) + sizeof hf->read_code) {
        hf->log(mod, "Diver's Best Friend needs HellForge SDK 13 or later");
        return 0;
    }
    g_hf->log(g_mod, "Diver's Best Friend " DBF_VERSION " (game " DBF_GAME_BUILD ")");
    return 0;
}
