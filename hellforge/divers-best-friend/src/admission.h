/* admission: decides, per DBF feature, whether the game's code and data layouts are the ones DBF was written against.
 *
 * DBF's R46 port read game memory at addresses and offsets it found for one build. Admission compares what is in the live
 * game with what those addresses were taken from: the build stamps of game.dll and helldivers2.exe, then "witness" byte
 * spans (generated into addresses_25480438.h) read from game.dll's code. A feature whose witnesses do not match stays
 * off; the others keep working. Feature code calls adm_feature() before touching anything it needs, and the Status tab
 * shows adm_feature_name() with the reason.
 *
 * Statuses: ADMIT_OK (every witness of the feature matched and the build is right), ADMIT_REFUSED (final: the build is
 * wrong, a witness differs for good, or the feature has no witness yet), ADMIT_PENDING (not decided yet: a module is not
 * loaded or a header or witness is not readable, or a witness differs and may still be being unpacked or patched; adm_tick
 * retries it). A readable witness that differs is retried for 30000 ms after adm_init and then refused; one that cannot
 * be read stays pending however long it takes, because the game unpacks code late.
 *
 * Reading: witnesses are read through the port's read_code, the bytes before any HellForge hook, and a byte HellForge
 * itself may rewrite is not compared. A witness that matched, and a build that was verified, are never read again.
 *
 * Portable C11: standard headers and the generated address header only; no SDK and no platform header. Not thread-safe by
 * design: only the game thread calls it. The reason strings returned live in static storage and stay valid until the
 * next adm_init or adm_tick. */
#ifndef DBF_ADMISSION_H
#define DBF_ADMISSION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* The numbers are the generated header's DBF_FEATURE_* (admission.c asserts it): a witness's `features` is a mask of
 * (1u << Feature). */
typedef enum {
    FEAT_STATE,
    FEAT_STRATAGEMS,
    FEAT_HUD_READ,
    FEAT_LIST_OPACITY,
    FEAT_ENTRY,
    FEAT_SCRAMBLE,
    FEAT_POINTING,
    FEAT_CAMERA,
    FEAT_LATCH,
    FEAT_SOUND,
    FEAT_DOCK,
    FEAT_WEAPON,
    FEAT_TERMINAL,
    FEAT_COUNT
} Feature;

typedef enum { ADMIT_PENDING, ADMIT_OK, ADMIT_REFUSED } Admit;

typedef struct AdmPort {
    /* Base address of a loaded module ("game.dll", "helldivers2.exe") and, when the pointer is not NULL, its image size
     * (0 when unknown); 0 when the module is not loaded. */
    uintptr_t (*module_base)(const char* module, size_t* size);
    /* Reads game code as it was before any hook; 0 on success, non-zero when the range cannot be read. */
    int (*read_code)(uintptr_t address, void* out, size_t size);
    /* 1 when HellForge may rewrite the module bytes at [rva, rva + size) (a byte of a witness it patches). NULL: none. */
    int (*rewrites)(uint32_t rva, uint32_t size);
} AdmPort;

/* Starts admission (or restarts it, forgetting all earlier results) and runs the first check at `now_ms`, a monotonic
 * millisecond clock. The 30000 ms grace period for differing witnesses counts from this call. */
void adm_init(const AdmPort* port, uint64_t now_ms);

/* Call often (every frame is fine). At most once per 1000 ms it retries what is still pending: modules and witnesses that
 * were not readable, and witnesses that differed. A no-op before adm_init. */
void adm_tick(uint64_t now_ms);

/* True when both modules carry build 25480438's stamps. `reason` (may be NULL) is empty when true; otherwise it says
 * why not, e.g. "build 6ae0e5ff is not 25480438" or "game.dll is not loaded yet". Before adm_init: false, "not started". */
bool adm_build_ok(const char** reason);

/* The status of one feature. `reason` (may be NULL) is "" for ADMIT_OK, else the first refused (or, if none, the first
 * pending) reason: "witness <name> differs", "witness <name> differs (retrying)", "witness <name> not readable yet",
 * "not mapped yet" (the feature has no witness), or the build reason. Before adm_init: ADMIT_PENDING, "not started". An
 * out-of-range feature is ADMIT_REFUSED, "unknown feature". */
Admit adm_feature(Feature f, const char** reason);

/* A short player-facing name for the Status tab: "Selection state", "Stratagems", "HUD reads", ... ("Unknown" when out of
 * range). */
const char* adm_feature_name(Feature f);

#endif
