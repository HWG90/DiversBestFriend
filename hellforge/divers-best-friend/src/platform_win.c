/* platform_win: DbfLock on a Windows CRITICAL_SECTION (KERNEL32). The Linux tests use tests/platform_posix.c instead. */
#include <windows.h>
#include "platform.h"

_Static_assert(sizeof(CRITICAL_SECTION) <= sizeof(((DbfLock*)0)->storage), "raise DBF_LOCK_STORAGE");
_Static_assert(_Alignof(CRITICAL_SECTION) <= _Alignof(DbfLock), "DbfLock is aligned too little for a CRITICAL_SECTION");

void dbf_lock_init(DbfLock* lock)
{
    InitializeCriticalSection((CRITICAL_SECTION*)(void*)lock->storage);
}

void dbf_lock_enter(DbfLock* lock)
{
    EnterCriticalSection((CRITICAL_SECTION*)(void*)lock->storage);
}

void dbf_lock_leave(DbfLock* lock)
{
    LeaveCriticalSection((CRITICAL_SECTION*)(void*)lock->storage);
}
