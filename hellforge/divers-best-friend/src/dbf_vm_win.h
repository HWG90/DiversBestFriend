#ifndef DBF_VM_WIN_H
#define DBF_VM_WIN_H
#include "hellforge_mod.h"

/* On DBF's game-thread tick only. The tick never calls into a Lua VM. */
void dbf_vm_tick(const HfApi* hf, HfMod* mod);
#endif
