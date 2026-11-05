/* platform: the one thing the portable units need from the operating system, a lock.
 *
 * The snapshot and the UI queue are shared by two threads (the game thread and the Overlay Host's render thread) and
 * guard their few shared words with a DbfLock. Portable code includes only this header; src/platform_win.c implements
 * it with a CRITICAL_SECTION (the DLL), tests/platform_posix.c with a pthread mutex (the Linux tests). A DbfLock is a
 * plain struct holding aligned storage that is large enough for either, so no platform header is needed here and a lock
 * can sit in a static.
 *
 * dbf_lock_init prepares an unlocked lock; initialise a lock once, before a second thread can see it. dbf_lock_enter
 * blocks until the lock is free; dbf_lock_leave frees it (only the thread that entered may leave). A lock is not
 * recursive. Portable C11: standard headers only. */
#ifndef DBF_PLATFORM_H
#define DBF_PLATFORM_H

#include <stdint.h>

#define DBF_LOCK_STORAGE 64 /* bytes; each implementation asserts that its native lock fits */

typedef struct DbfLock {
    _Alignas(16) unsigned char storage[DBF_LOCK_STORAGE];
} DbfLock;

void dbf_lock_init(DbfLock* lock);
void dbf_lock_enter(DbfLock* lock);
void dbf_lock_leave(DbfLock* lock);

#endif
