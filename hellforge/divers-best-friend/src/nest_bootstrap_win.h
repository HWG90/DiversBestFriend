#ifndef DBF_NEST_BOOTSTRAP_H
#define DBF_NEST_BOOTSTRAP_H
#include <stdbool.h>
#include "hellforge_mod.h"
#include "goose_overlay.h"

/* Called at GAME_LOADED, after initial plan modules have initialized. */
const OvApi* dbf_nest_connect(const HfApi* hf, HfMod* mod, bool* migration);
#endif
