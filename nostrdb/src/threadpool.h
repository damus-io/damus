
#ifndef THREADPOOL_H
#define THREADPOOL_H

#include "protected_queue.h"

struct thread
{
	pthread_t thread_id;
	struct prot_queue inbox;
	void *qmem;
	void *ctx;
	int quit_pushed; // did the quit message make it into the inbox?
};

struct threadpool
{
	int num_threads;
	struct thread *pool;
	int next_thread;
	void *quit_msg;
};

static int threadpool_init(struct threadpool *tp, int num_threads,
			   int q_elem_size, int q_num_elems,
			   void *quit_msg, void *ctx, void* (*thread_fn)(void*))
{
	int i;
	struct thread *t;

	if (num_threads <= 0)
		return 0;

	tp->num_threads = num_threads;
	tp->pool = malloc(sizeof(*tp->pool) * num_threads);
	tp->quit_msg = quit_msg;
	tp->next_thread = -1;

	if (tp->pool == NULL) {
		fprintf(stderr, "threadpool_init: couldn't allocate memory for pool");
		return 0;
	}

	for (i = 0; i < num_threads; i++) {
		t = &tp->pool[i];
		t->qmem = malloc(q_elem_size * q_num_elems);
		t->ctx = ctx;

		if (t->qmem == NULL) {
			fprintf(stderr, "threadpool_init: couldn't allocate memory for queue");
			return 0;
		}

		if (!prot_queue_init(&t->inbox, t->qmem, q_elem_size * q_num_elems, q_elem_size)) {
			fprintf(stderr, "threadpool_init: couldn't init queue. buffer alignment is wrong.");
			return 0;
		}

		if (THREAD_CREATE(t->thread_id, thread_fn, t) != 0) {
			fprintf(stderr, "threadpool_init: failed to create thread\n");
			return 0;
		}
	}

	return 1;
}

static inline struct thread *threadpool_next_thread(struct threadpool *tp)
{
	tp->next_thread = (tp->next_thread + 1) % tp->num_threads;
	return &tp->pool[tp->next_thread];
}

static inline int threadpool_dispatch(struct threadpool *tp, void *msg)
{
	struct thread *t = threadpool_next_thread(tp);
	return prot_queue_push(&t->inbox, msg);
}

static inline int threadpool_dispatch_all_threads(struct threadpool *tp, void *msg)
{
	int i, ok;
	ok = 1;

	for (i = 0; i < tp->num_threads; i++) {
		ok = ok && prot_queue_push(&tp->pool[i].inbox, msg);
	}

	return ok;
}


static inline int threadpool_dispatch_all(struct threadpool *tp, void *msgs,
					  int num_msgs)
{
	struct thread *t = threadpool_next_thread(tp);
	return prot_queue_push_all(&t->inbox, msgs, num_msgs);
}

static inline void threadpool_destroy(struct threadpool *tp)
{
	struct thread *t;

	// quit every thread before joining any of them, and free no queue
	// until they have all stopped: a thread can dispatch onto another
	// thread's inbox while it drains, so tearing them down one at a time
	// would let a live thread push into freed queue memory
	for (int i = 0; i < tp->num_threads; i++) {
		t = &tp->pool[i];
		t->quit_pushed = prot_queue_push(&t->inbox, tp->quit_msg);
	}

	for (int i = 0; i < tp->num_threads; i++) {
		t = &tp->pool[i];
		if (t->quit_pushed)
			THREAD_FINISH(t->thread_id);
		else
			THREAD_TERMINATE(t->thread_id);
	}

	for (int i = 0; i < tp->num_threads; i++) {
		t = &tp->pool[i];
		prot_queue_destroy(&t->inbox);
		free(t->qmem);
	}

	free(tp->pool);
}

#endif // THREADPOOL_H
