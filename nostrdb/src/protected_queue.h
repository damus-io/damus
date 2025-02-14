/*
 *    This header file provides a thread-safe queue implementation for generic
 *    data elements. It uses POSIX threads (pthreads) to ensure thread safety.
 *    The queue allows for pushing and popping elements, with the ability to
 *    block or non-block on pop operations. Users are responsible for providing
 *    memory for the queue buffer and ensuring its correct lifespan.
 *
 *         Author:  William Casarin
 *         Inspired-by: https://github.com/hoytech/hoytech-cpp/blob/master/hoytech/protected_queue.h
 */

#ifndef PROT_QUEUE_H
#define PROT_QUEUE_H

#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "cursor.h"
#include "util.h"
#include "thread.h"

#define max(a,b) ((a) > (b) ? (a) : (b))
#define min(a,b) ((a) < (b) ? (a) : (b))

/* 
 * The prot_queue structure represents a thread-safe queue that can hold
 * generic data elements.
 */
struct prot_queue {
	unsigned char *buf;
	size_t buflen;

	int head;
	int tail;
	int count;
	int elem_size;

	pthread_mutex_t mutex;
	pthread_cond_t cond;
};


/* 
 * Initialize the queue. 
 * Params:
 * q         - Pointer to the queue.
 * buf       - Buffer for holding data elements.
 * buflen    - Length of the buffer.
 * elem_size - Size of each data element.
 * Returns 1 if successful, 0 otherwise.
 */
static inline int prot_queue_init(struct prot_queue* q, void* buf,
				  size_t buflen, int elem_size)
{
	// buffer elements must fit nicely in the buffer
	if (buflen == 0 || buflen % elem_size != 0)
		assert(!"queue elements don't fit nicely");

	q->head = 0;
	q->tail = 0;
	q->count = 0;
	q->buf = buf;
	q->buflen = buflen;
	q->elem_size = elem_size;

	pthread_mutex_init(&q->mutex, NULL);
	pthread_cond_init(&q->cond, NULL);

	return 1;
}

/* 
 * Return the capacity of the queue.
 * q    - Pointer to the queue.
 */
static inline size_t prot_queue_capacity(struct prot_queue *q) {
	return q->buflen / q->elem_size;
}

/* 
 * Push an element onto the queue.
 * Params:
 * q    - Pointer to the queue.
 * data - Pointer to the data element to be pushed.
 *
 * Returns 1 if successful, 0 if the queue is full.
 */
static int prot_queue_push(struct prot_queue* q, void *data)
{
	int cap;

	pthread_mutex_lock(&q->mutex);

	cap = prot_queue_capacity(q);
	if (q->count == cap) {
		// only signal if the push was sucessful
		pthread_mutex_unlock(&q->mutex);
		return 0;
	}

	memcpy(&q->buf[q->tail * q->elem_size], data, q->elem_size);
	q->tail = (q->tail + 1) % cap;
	q->count++;

	pthread_cond_signal(&q->cond);
	pthread_mutex_unlock(&q->mutex);

	return 1;
}

/*
 * Push multiple elements onto the queue.
 * Params:
 * q      - Pointer to the queue.
 * data   - Pointer to the data elements to be pushed.
 * count  - Number of elements to push.
 *
 * Returns the number of elements successfully pushed, 0 if the queue is full or if there is not enough contiguous space.
 */
static int prot_queue_push_all(struct prot_queue* q, void *data, int count)
{
	int cap;
	int first_copy_count, second_copy_count;

	pthread_mutex_lock(&q->mutex);

	cap = prot_queue_capacity(q);
	if (q->count + count > cap) {
		pthread_mutex_unlock(&q->mutex);
		return 0; // Return failure if the queue is full
	}

	first_copy_count = min(count, cap - q->tail); // Elements until the end of the buffer
	second_copy_count = count - first_copy_count; // Remaining elements if wrap around

	memcpy(&q->buf[q->tail * q->elem_size], data, first_copy_count * q->elem_size);
	q->tail = (q->tail + first_copy_count) % cap;

	if (second_copy_count > 0) {
		// If there is a wrap around, copy the remaining elements
		memcpy(&q->buf[q->tail * q->elem_size], (char *)data + first_copy_count * q->elem_size, second_copy_count * q->elem_size);
		q->tail = (q->tail + second_copy_count) % cap;
	}

	q->count += count;

	pthread_cond_signal(&q->cond); // Signal a waiting thread
	pthread_mutex_unlock(&q->mutex);

	return count;
}

/* 
 * Try to pop an element from the queue without blocking.
 * Params:
 * q    - Pointer to the queue.
 * data - Pointer to where the popped data will be stored.
 * Returns 1 if successful, 0 if the queue is empty.
 */
static inline int prot_queue_try_pop_all(struct prot_queue *q, void *data, int max_items) {
	int items_to_pop, items_until_end;

	pthread_mutex_lock(&q->mutex);

	if (q->count == 0) {
		pthread_mutex_unlock(&q->mutex);
		return 0;
	}

	items_until_end = (q->buflen - q->head * q->elem_size) / q->elem_size;
	items_to_pop = min(q->count, max_items);
	items_to_pop = min(items_to_pop, items_until_end);

	memcpy(data, &q->buf[q->head * q->elem_size], items_to_pop * q->elem_size);
	q->head = (q->head + items_to_pop) % prot_queue_capacity(q);
	q->count -= items_to_pop;

	pthread_mutex_unlock(&q->mutex);
	return items_to_pop;
}

/* 
 * Wait until we have elements, and then pop multiple elements from the queue
 * up to the specified maximum.
 *
 * Params:
 * q		 - Pointer to the queue.
 * buffer	 - Pointer to the buffer where popped data will be stored.
 * max_items - Maximum number of items to pop from the queue.
 * Returns the actual number of items popped.
 */
static int prot_queue_pop_all(struct prot_queue *q, void *dest, int max_items) {
	pthread_mutex_lock(&q->mutex);

	// Wait until there's at least one item to pop
	while (q->count == 0) {
		pthread_cond_wait(&q->cond, &q->mutex);
	}

	int items_until_end = (q->buflen - q->head * q->elem_size) / q->elem_size;
	int items_to_pop = min(q->count, max_items);
	items_to_pop = min(items_to_pop, items_until_end);

	memcpy(dest, &q->buf[q->head * q->elem_size], items_to_pop * q->elem_size);
	q->head = (q->head + items_to_pop) % prot_queue_capacity(q);
	q->count -= items_to_pop;

	pthread_mutex_unlock(&q->mutex);

	return items_to_pop;
}

/* 
 * Pop an element from the queue. Blocks if the queue is empty.
 * Params:
 * q    - Pointer to the queue.
 * data - Pointer to where the popped data will be stored.
 */
static inline void prot_queue_pop(struct prot_queue *q, void *data) {
	pthread_mutex_lock(&q->mutex);

	while (q->count == 0)
		pthread_cond_wait(&q->cond, &q->mutex);

	memcpy(data, &q->buf[q->head * q->elem_size], q->elem_size);
	q->head = (q->head + 1) % prot_queue_capacity(q);
	q->count--;

	pthread_mutex_unlock(&q->mutex);
}

/* 
 * Destroy the queue. Releases resources associated with the queue.
 * Params:
 * q - Pointer to the queue.
 */
static inline void prot_queue_destroy(struct prot_queue* q) {
	pthread_mutex_destroy(&q->mutex);
	pthread_cond_destroy(&q->cond);
}

#endif // PROT_QUEUE_H
