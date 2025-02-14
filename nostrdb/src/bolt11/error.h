
#ifndef PROTOVERSE_ERROR_H
#define PROTOVERSE_ERROR_H

#include "cursor.h"

struct error {
	int pos;
	const char *msg;
};

struct errors {
	struct cursor cur;
	int enabled;
};

#define note_error(errs, p, fmt, ...) note_error_(errs, p, "%s: " fmt, __FUNCTION__, ##__VA_ARGS__)

static inline int cursor_push_error(struct cursor *cur, struct error *err)
{
	return cursor_push_int(cur, err->pos) &&
	       cursor_push_c_str(cur, err->msg);
}

static inline int cursor_pull_error(struct cursor *cur, struct error *err)
{
	return cursor_pull_int(cur, &err->pos) &&
	       cursor_pull_c_str(cur, &err->msg);
}

int note_error_(struct errors *errs, struct cursor *p, const char *fmt, ...);

#endif /* PROTOVERSE_ERROR_H */
