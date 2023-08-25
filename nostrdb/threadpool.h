
#ifndef THREADPOOL_H
#define THREADPOOL_H

#include "protected_queue.h"

struct thread
{
	pthread_t thread_id;
	struct prot_queue inbox;
	void *qmem;
	void *ctx;
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

		if (pthread_create(&t->thread_id, NULL, thread_fn, t) != 0) {
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

static inline int threadpool_dispatch_all(struct threadpool *tp, void *msgs,
					  int num_msgs)
{
	struct thread *t = threadpool_next_thread(tp);
	return prot_queue_push_all(&t->inbox, msgs, num_msgs);
}

static inline void threadpool_destroy(struct threadpool *tp)
{
	struct thread *t;

	for (uint64_t i = 0; i < tp->num_threads; i++) {
		t = &tp->pool[i];
		if (!prot_queue_push(&t->inbox, tp->quit_msg)) {
			pthread_exit(&t->thread_id);
		} else {
			pthread_join(t->thread_id, NULL);
		}
		prot_queue_destroy(&t->inbox);
		free(t->qmem);
	}
	free(tp->pool);
}

#endif // THREADPOOL_H
