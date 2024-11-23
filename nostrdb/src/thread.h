#ifndef NDB_THREAD_H
#define NDB_THREAD_H

#ifdef _WIN32
  #include <windows.h>

  #define     ErrCode()       GetLastError()
// Define POSIX-like thread types
typedef HANDLE pthread_t;
typedef CRITICAL_SECTION pthread_mutex_t;
typedef CONDITION_VARIABLE pthread_cond_t;

#define ErrCode() GetLastError()

// Mutex functions
#define pthread_mutex_init(mutex, attr) \
    (InitializeCriticalSection(mutex), 0)

#define pthread_mutex_destroy(mutex) \
    (DeleteCriticalSection(mutex), 0)

#define pthread_mutex_lock(mutex) \
    (EnterCriticalSection(mutex), 0)

#define pthread_mutex_unlock(mutex) \
    (LeaveCriticalSection(mutex), 0)

// Condition variable functions
#define pthread_cond_init(cond, attr) \
    (InitializeConditionVariable(cond), 0)

#define pthread_cond_destroy(cond)

#define pthread_cond_signal(cond) \
    (WakeConditionVariable(cond), 0)

#define pthread_cond_wait(cond, mutex) \
    (SleepConditionVariableCS(cond, mutex, INFINITE) ? 0 : ErrCode())

// Thread functions
#define THREAD_CREATE(thr, start, arg) \
    (((thr = CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)start, arg, 0, NULL)) != NULL) ? 0 : ErrCode())

#define THREAD_FINISH(thr) \
    (WaitForSingleObject(thr, INFINITE), CloseHandle(thr), 0)

#define THREAD_TERMINATE(thr) \
    (TerminateThread(thr, 0) ? ErrCode() : 0)

#else // _WIN32
  #include <pthread.h>

  //#define     ErrCode()       errno
  #define THREAD_CREATE(thr,start,arg)	pthread_create(&thr,NULL,start,arg)
  #define THREAD_FINISH(thr)	pthread_join(thr,NULL)
  #define THREAD_TERMINATE(thr)	pthread_exit(&thr)
  
  #define LOCK_MUTEX(mutex)	pthread_mutex_lock(mutex)
  #define UNLOCK_MUTEX(mutex)	pthread_mutex_unlock(mutex)

#endif

#endif // NDB_THREAD_H
