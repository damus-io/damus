
#ifndef JB55_CURSOR_H
#define JB55_CURSOR_H

#include "typedefs.h"
#include "varint.h"

#include <stdio.h>
#include <ctype.h>
#include <assert.h>
#include <string.h>

#define unlikely(x) __builtin_expect((x),0)
#define likely(x)   __builtin_expect((x),1)

struct cursor {
	unsigned char *start;
	unsigned char *p;
	unsigned char *end;
};

struct array {
	struct cursor cur;
	unsigned int elem_size;
};

static inline void reset_cursor(struct cursor *cursor)
{
	cursor->p = cursor->start;
}

static inline void wipe_cursor(struct cursor *cursor)
{
	reset_cursor(cursor);
	memset(cursor->start, 0, cursor->end - cursor->start);
}

static inline void make_cursor(u8 *start, u8 *end, struct cursor *cursor)
{
	cursor->start = start;
	cursor->p = start;
	cursor->end = end;
}

static inline void make_array(struct array *a, u8* start, u8 *end, unsigned int elem_size)
{
	make_cursor(start, end, &a->cur);
	a->elem_size = elem_size;
}

static inline int cursor_eof(struct cursor *c)
{
	return c->p == c->end;
}

static inline void *cursor_malloc(struct cursor *mem, unsigned long size)
{
	void *ret;

	if (mem->p + size > mem->end) {
		return NULL;
	}

	ret = mem->p;
	mem->p += size;

	return ret;
}

static inline void *cursor_alloc(struct cursor *mem, unsigned long size)
{
	void *ret;
	if (!(ret = cursor_malloc(mem, size))) {
		return 0;
	}

	memset(ret, 0, size);
	return ret;
}

static inline int cursor_slice(struct cursor *mem, struct cursor *slice, size_t size)
{
	u8 *p;
	if (!(p = cursor_alloc(mem, size))) {
		return 0;
	}
	make_cursor(p, mem->p, slice);
	return 1;
}


static inline void copy_cursor(struct cursor *src, struct cursor *dest)
{
	dest->start = src->start;
	dest->p = src->p;
	dest->end = src->end;
}

static inline int pull_byte(struct cursor *cursor, u8 *c)
{
	if (unlikely(cursor->p >= cursor->end))
		return 0;

	*c = *cursor->p;
	cursor->p++;

	return 1;
}

static inline int cursor_pull_c_str(struct cursor *cursor, const char **str)
{
	*str = (const char*)cursor->p;

	for (; cursor->p < cursor->end; cursor->p++) {
		if (*cursor->p == 0) {
			cursor->p++;
			return 1;
		}
	}

	return 0;
}


static inline int cursor_push_byte(struct cursor *cursor, u8 c)
{
	if (unlikely(cursor->p + 1 > cursor->end)) {
		return 0;
	}

	*cursor->p = c;
	cursor->p++;

	return 1;
}

static inline int cursor_pull(struct cursor *cursor, u8 *data, int len)
{
	if (unlikely(cursor->p + len > cursor->end)) {
		return 0;
	}

	memcpy(data, cursor->p, len);
	cursor->p += len;

	return 1;
}

static inline int pull_data_into_cursor(struct cursor *cursor,
			  struct cursor *dest,
			  unsigned char **data,
			  int len)
{
	int ok;

	if (unlikely(dest->p + len > dest->end)) {
		printf("not enough room in dest buffer\n");
		return 0;
	}

	ok = cursor_pull(cursor, dest->p, len);
	if (!ok) return 0;

	*data = dest->p;
	dest->p += len;

	return 1;
}

static inline int cursor_dropn(struct cursor *cur, int size, int n)
{
	if (n == 0)
		return 1;

	if (unlikely(cur->p - size*n < cur->start)) {
		return 0;
	}

	cur->p -= size*n;
	return 1;
}

static inline int cursor_drop(struct cursor *cur, int size)
{
	return cursor_dropn(cur, size, 1);
}

static inline unsigned char *cursor_topn(struct cursor *cur, int len, int n)
{
	n += 1;
	if (unlikely(cur->p - len*n < cur->start)) {
		return NULL;
	}
	return cur->p - len*n;
}

static inline unsigned char *cursor_top(struct cursor *cur, int len)
{
	if (unlikely(cur->p - len < cur->start)) {
		return NULL;
	}
	return cur->p - len;
}

static inline int cursor_top_int(struct cursor *cur, int *i)
{
	u8 *p;
	if (unlikely(!(p = cursor_top(cur, sizeof(*i))))) {
		return 0;
	}
	*i = *((int*)p);
	return 1;
}

static inline int cursor_pop(struct cursor *cur, u8 *data, int len)
{
	if (unlikely(cur->p - len < cur->start)) {
		return 0;
	}

	cur->p -= len;
	memcpy(data, cur->p, len);

	return 1;
}

static inline int cursor_push(struct cursor *cursor, u8 *data, int len)
{
	if (unlikely(cursor->p + len >= cursor->end)) {
		return 0;
	}

	if (cursor->p != data)
		memcpy(cursor->p, data, len);

	cursor->p += len;

	return 1;
}

static inline int cursor_push_int(struct cursor *cursor, int i)
{
	return cursor_push(cursor, (u8*)&i, sizeof(i));
}

static inline size_t cursor_count(struct cursor *cursor, size_t elem_size)
{
	return (cursor->p - cursor->start)/elem_size;
}

/* TODO: push_varint */
static inline int push_varint(struct cursor *cursor, int n)
{
	int ok, len;
	unsigned char b;
	len = 0;

	while (1) {
		b = (n & 0xFF) | 0x80;
		n >>= 7;
		if (n == 0) {
			b &= 0x7F;
			ok = cursor_push_byte(cursor, b);
			len++;
			if (!ok) return 0;
			break;
		}

		ok = cursor_push_byte(cursor, b);
		len++;
		if (!ok) return 0;
	}

	return len;
}

/* TODO: pull_varint */
static inline int pull_varint(struct cursor *cursor, int *n)
{
	int ok, i;
	unsigned char b;
	*n = 0;

	for (i = 0;; i++) {
		ok = pull_byte(cursor, &b);
		if (!ok) return 0;

		*n |= ((int)b & 0x7F) << (i * 7);

		/* is_last */
		if ((b & 0x80) == 0) {
			return i+1;
		}

		if (i == 4) return 0;
	}

	return 0;
}

static inline int cursor_pull_int(struct cursor *cursor, int *i)
{
	return cursor_pull(cursor, (u8*)i, sizeof(*i));
}

static inline int cursor_push_u32(struct cursor *cursor, uint32_t i) {
    return cursor_push(cursor, (unsigned char*)&i, sizeof(i));
}

static inline int cursor_push_u16(struct cursor *cursor, u16 i)
{
	return cursor_push(cursor, (u8*)&i, sizeof(i));
}

static inline void *index_cursor(struct cursor *cursor, unsigned int index, int elem_size)
{
	u8 *p;
	p = &cursor->start[elem_size * index];

	if (unlikely(p >= cursor->end))
		return NULL;

	return (void*)p;
}


static inline int push_sized_str(struct cursor *cursor, const char *str, int len)
{
	return cursor_push(cursor, (u8*)str, len);
}

static inline int cursor_push_str(struct cursor *cursor, const char *str)
{
	return cursor_push(cursor, (u8*)str, (int)strlen(str));
}

static inline int cursor_push_c_str(struct cursor *cursor, const char *str)
{
	return cursor_push_str(cursor, str) && cursor_push_byte(cursor, 0);
}

/* TODO: push varint size */
static inline int push_prefixed_str(struct cursor *cursor, const char *str)
{
	int ok, len;
	len = (int)strlen(str);
	ok = push_varint(cursor, len);
	if (!ok) return 0;
	return push_sized_str(cursor, str, len);
}

static inline int pull_prefixed_str(struct cursor *cursor, struct cursor *dest_buf, const char **str)
{
	int len, ok;

	ok = pull_varint(cursor, &len);
	if (!ok) return 0;

	if (unlikely(dest_buf->p + len > dest_buf->end)) {
		return 0;
	}

	ok = pull_data_into_cursor(cursor, dest_buf, (unsigned char**)str, len);
	if (!ok) return 0;

	ok = cursor_push_byte(dest_buf, 0);

	return 1;
}

static inline int cursor_remaining_capacity(struct cursor *cursor)
{
	return (int)(cursor->end - cursor->p);
}


#define max(a,b) ((a) > (b) ? (a) : (b))
static inline void cursor_print_around(struct cursor *cur, int range)
{
	unsigned char *c;

	printf("[%ld/%ld]\n", cur->p - cur->start, cur->end - cur->start);

	c = max(cur->p - range, cur->start);
	for (; c < cur->end && c < (cur->p + range); c++) {
		printf("%02x", *c);
	}
	printf("\n");

	c = max(cur->p - range, cur->start);
	for (; c < cur->end && c < (cur->p + range); c++) {
		if (c == cur->p) {
			printf("^");
			continue;
		}
		printf("  ");
	}
	printf("\n");
}
#undef max

static inline int pull_bytes(struct cursor *cur, int count, const u8 **bytes) {
    if (cur->p + count > cur->end)
        return 0;
    
    *bytes = cur->p;
    cur->p += count;
    return 1;
}

static inline int parse_str(struct cursor *cur, const char *str) {
    int i;
    char c, cs;
    unsigned long len;
    
    len = strlen(str);
    
    if (cur->p + len >= cur->end)
        return 0;
    
    for (i = 0; i < len; i++) {
        c = tolower(cur->p[i]);
        cs = tolower(str[i]);
        
        if (c != cs)
            return 0;
    }
    
    cur->p += len;
    
    return 1;
}

static inline int is_whitespace(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
}

static inline int is_utf8_byte(u8 c) {
    return c & 0x80;
}

static inline int is_right_boundary(char c) {
    return is_whitespace(c) || ispunct(c);
}

static inline int is_left_boundary(char c) {
    return is_right_boundary(c) || is_utf8_byte(c);
}

static inline int is_invalid_url_ending(char c) {
    return c == '!' || c == '?' || c == ')' || c == '.' || c == ',' || c == ';';
}

static inline int is_alphanumeric(char c) {
    return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
}

static inline int consume_until_boundary(struct cursor *cur) {
    char c;
    
    while (cur->p < cur->end) {
        c = *cur->p;
        
        if (is_right_boundary(c))
            return 1;
        
        cur->p++;
    }
    
    return 1;
}

static inline int consume_until_whitespace(struct cursor *cur, int or_end) {
    char c;
    int consumedAtLeastOne = 0;
    
    while (cur->p < cur->end) {
        c = *cur->p;
        
        if (is_whitespace(c))
            return consumedAtLeastOne;
        
        cur->p++;
        consumedAtLeastOne = 1;
    }
    
    return or_end;
}

static inline int consume_until_non_alphanumeric(struct cursor *cur, int or_end) {
    char c;
    int consumedAtLeastOne = 0;

    while (cur->p < cur->end) {
        c = *cur->p;

        if (!is_alphanumeric(c))
            return consumedAtLeastOne;

        cur->p++;
        consumedAtLeastOne = 1;
    }

    return or_end;
}

static inline int parse_char(struct cursor *cur, char c) {
    if (cur->p >= cur->end)
        return 0;
        
    if (*cur->p == c) {
        cur->p++;
        return 1;
    }
    
    return 0;
}

static inline int peek_char(struct cursor *cur, int ind) {
    if ((cur->p + ind < cur->start) || (cur->p + ind >= cur->end))
        return -1;
    
    return *(cur->p + ind);
}

#endif
