/* platform_posix: DbfLock on a pthread mutex, for the Linux tests (the DLL uses src/platform_win.c). */
#include <pthread.h>
#include "platform.h"

_Static_assert(sizeof(pthread_mutex_t) <= sizeof(((DbfLock*)0)->storage), "raise DBF_LOCK_STORAGE");
_Static_assert(_Alignof(pthread_mutex_t) <= _Alignof(DbfLock), "DbfLock is aligned too little for a pthread_mutex_t");

void dbf_lock_init(DbfLock* lock)
{
    pthread_mutex_init((pthread_mutex_t*)(void*)lock->storage, NULL);
}

void dbf_lock_enter(DbfLock* lock)
{
    pthread_mutex_lock((pthread_mutex_t*)(void*)lock->storage);
}

void dbf_lock_leave(DbfLock* lock)
{
    pthread_mutex_unlock((pthread_mutex_t*)(void*)lock->storage);
}
