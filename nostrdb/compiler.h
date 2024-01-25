
#ifndef COMPILER_H
#define COMPILER_H

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"

#if HAVE_UNALIGNED_ACCESS
#define alignment_ok(p, n) 1
#else
#define alignment_ok(p, n) ((size_t)(p) % (n) == 0)
#endif

#define UNUSED __attribute__((__unused__))

/**
 * BUILD_ASSERT - assert a build-time dependency.
 * @cond: the compile-time condition which must be true.
 *
 * Your compile will fail if the condition isn't true, or can't be evaluated
 * by the compiler.  This can only be used within a function.
 *
 * Example:
 *	#include <stddef.h>
 *	...
 *	static char *foo_to_char(struct foo *foo)
 *	{
 *		// This code needs string to be at start of foo.
 *		BUILD_ASSERT(offsetof(struct foo, string) == 0);
 *		return (char *)foo;
 *	}
 */
#define BUILD_ASSERT(cond) \
	do { (void) sizeof(char [1 - 2*!(cond)]); } while(0)

/**
 * BUILD_ASSERT_OR_ZERO - assert a build-time dependency, as an expression.
 * @cond: the compile-time condition which must be true.
 *
 * Your compile will fail if the condition isn't true, or can't be evaluated
 * by the compiler.  This can be used in an expression: its value is "0".
 *
 * Example:
 *	#define foo_to_char(foo)					\
 *		 ((char *)(foo)						\
 *		  + BUILD_ASSERT_OR_ZERO(offsetof(struct foo, string) == 0))
 */
#define BUILD_ASSERT_OR_ZERO(cond) \
	(sizeof(char [1 - 2*!(cond)]) - 1)

#define memclear(mem, size) memset(mem, 0, size)
#define memclear_2(m1, s1, m2, s2) { memclear(m1, s1); memclear(m2, s2); }
#define memclear_3(m1, s1, m2, s2, m3, s3) { memclear(m1, s1); memclear(m2, s2); memclear(m3, s3); }

static inline void *memcheck_(const void *data, size_t len)
{
	(void)len;
	return (void *)data;
}

#if HAVE_TYPEOF
/**
 * memcheck - check that a memory region is initialized
 * @data: start of region
 * @len: length in bytes
 *
 * When running under valgrind, this causes an error to be printed
 * if the entire region is not defined.  Otherwise valgrind only
 * reports an error when an undefined value is used for a branch, or
 * written out.
 *
 * Example:
 *	// Search for space, but make sure it's all initialized.
 *	if (memchr(memcheck(somebytes, bytes_len), ' ', bytes_len)) {
 *		printf("space was found!\n");
 *	}
 */
#define memcheck(data, len) ((__typeof__((data)+0))memcheck_((data), (len)))
#else
#define memcheck(data, len) memcheck_((data), (len))
#endif

#endif /* COMPILER_H */
