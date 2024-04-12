#ifndef NDB_THREAD_H
#define NDB_THREAD_H

#ifdef _WIN32
  #include <windows.h>

  #define     ErrCode()       GetLastError()
  #define pthread_t	HANDLE
  #define pthread_mutex_t	HANDLE
  #define pthread_cond_t	HANDLE
  #define pthread_cond_destroy(x)	
  #define pthread_mutex_unlock(x)	ReleaseMutex(*x)
  #define pthread_mutex_destroy(x) \
  	(CloseHandle(*x) ? 0 : ErrCode())
  #define pthread_mutex_lock(x)	WaitForSingleObject(*x, INFINITE)
  #define pthread_mutex_init(mutex, attr) \
    ((*mutex = CreateMutex(NULL, FALSE, NULL)) ? 0 : ErrCode())
  #define pthread_cond_init(x, attr) (InitializeConditionVariable(x), 0)
  #define pthread_cond_signal(x)	SetEvent(*x)
  #define pthread_cond_wait(cond,mutex)	do{SignalObjectAndWait(*mutex, *cond, INFINITE, FALSE); WaitForSingleObject(*mutex, INFINITE);}while(0)
  #define THREAD_CREATE(thr,start,arg) \
  	(((thr) = CreateThread(NULL, 0, start, arg, 0, NULL)) ? 0 : ErrCode())
  #define THREAD_FINISH(thr) \
  	(WaitForSingleObject(thr, INFINITE) ? ErrCode() : 0)
  #define THREAD_TERMINATE(thr) \
	(TerminateThread(thr, 0) ? ErrCode() : 0)
  #define LOCK_MUTEX(mutex)		WaitForSingleObject(mutex, INFINITE)
  #define UNLOCK_MUTEX(mutex)		ReleaseMutex(mutex)

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
