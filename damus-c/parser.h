
#ifndef CURSOR_PARSER
#define CURSOR_PARSER

#include "cursor.h"

static int consume_bytes(struct cursor *cursor, const unsigned char *match, int len)
{
	int i;

	if (cursor->p + len > cursor->end) {
		fprintf(stderr, "consume_bytes overflow\n");
		return 0;
	}

	for (i = 0; i < len; i++) {
		if (cursor->p[i] != match[i])
			return 0;
	}

	cursor->p += len;

	return 1;
}

static inline int consume_byte(struct cursor *cursor, unsigned char match)
{
	if (unlikely(cursor->p >= cursor->end))
		return 0;
	if (*cursor->p != match)
		return 0;
	cursor->p++;
	return 1;
}

static inline int consume_u32(struct cursor *cursor, unsigned int match)
{
	return consume_bytes(cursor, (unsigned char*)&match, sizeof(match));
}

#endif /* CURSOR_PARSER */

