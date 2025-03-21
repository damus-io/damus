
#ifndef JB55_CURSOR_H
#define JB55_CURSOR_H

#include "ccan/likely/likely.h"

#include <stdio.h>
#include <inttypes.h>
#include <ctype.h>
#include <assert.h>
#include <string.h>

struct cursor {
	unsigned char *start;
	unsigned char *p;
	unsigned char *end;
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

static inline void make_cursor(unsigned char *start, unsigned char *end, struct cursor *cursor)
{
	cursor->start = start;
	cursor->p = start;
	cursor->end = end;
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
	unsigned char *p;
	if (!(p = cursor_alloc(mem, size))) {
		return 0;
	}
	make_cursor(p, mem->p, slice);
	return 1;
}

static inline int cursor_malloc_slice(struct cursor *mem, struct cursor *slice, size_t size)
{
	unsigned char *p;
	if (!(p = cursor_malloc(mem, size))) {
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

static inline int cursor_skip(struct cursor *cursor, int n)
{
    if (cursor->p + n >= cursor->end)
        return 0;

    cursor->p += n;

    return 1;
}

static inline int cursor_pull_byte(struct cursor *cursor, unsigned char *c)
{
	if (unlikely(cursor->p >= cursor->end))
		return 0;

	*c = *cursor->p;
	cursor->p++;

	return 1;
}

static inline int parse_byte(struct cursor *cursor, unsigned char *c)
{
    if (unlikely(cursor->p >= cursor->end))
        return 0;

    *c = *cursor->p;
    //cursor->p++;

    return 1;
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


static inline int cursor_push_byte(struct cursor *cursor, unsigned char c)
{
	if (unlikely(cursor->p + 1 > cursor->end)) {
		return 0;
	}

	*cursor->p = c;
	cursor->p++;

	return 1;
}

static inline int cursor_pull(struct cursor *cursor, unsigned char *data, int len)
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
	unsigned char *p;
	if (unlikely(!(p = cursor_top(cur, sizeof(*i))))) {
		return 0;
	}
	*i = *((int*)p);
	return 1;
}

static inline int cursor_pop(struct cursor *cur, unsigned char *data, int len)
{
	if (unlikely(cur->p - len < cur->start)) {
		return 0;
	}

	cur->p -= len;
	memcpy(data, cur->p, len);

	return 1;
}

static inline int cursor_push(struct cursor *cursor, unsigned char *data, int len)
{
	if (unlikely(cursor->p + len > cursor->end)) {
		return 0;
	}

	if (cursor->p != data)
		memcpy(cursor->p, data, len);

	cursor->p += len;

	return 1;
}

static inline int cursor_push_int(struct cursor *cursor, int i)
{
	return cursor_push(cursor, (unsigned char*)&i, sizeof(i));
}

static inline size_t cursor_count(struct cursor *cursor, size_t elem_size)
{
	return (cursor->p - cursor->start)/elem_size;
}

/* Encodes a 64-bit integer into a variable-length format and pushes it into a cursor.
 * Returns the number of bytes used or -1 in case of an error. */
static inline int cursor_push_varint(struct cursor *cursor, uint64_t n)
{
	int len = 0;
	do {
		unsigned char b = (n & 0x7F) | (n > 0x7F ? 0x80 : 0);
		n >>= 7;
		if (!cursor_push_byte(cursor, b))
			return -1; // Error handling
		len++;
	} while (n != 0);

	return len;
}

static inline int cursor_pull_varint(struct cursor *cursor, uint64_t *n)
{
	int ok, i;
	unsigned char b;

	*n = 0;

	for (i = 0; i < 10; i++) { // Loop up to 10 bytes for 64-bit
		ok = cursor_pull_byte(cursor, &b);
		if (!ok) return 0;

		*n |= ((int64_t)b & 0x7F) << (i * 7);

		if ((b & 0x80) == 0) {
			return i + 1; // Successfully read i+1 bytes
		}
	}

	return 10; // Successfully read 10 bytes for a full 64-bit integer
}

static int cursor_pull_varint_u32(struct cursor *cursor, uint32_t *v)
{
	uint64_t bigval;

	if (!cursor_pull_varint(cursor, &bigval))
		return 0;

	if (bigval > UINT32_MAX)
		return 0;

	*v = (uint32_t) bigval;
	return 1;
}

static inline int cursor_pull_int(struct cursor *cursor, int *i)
{
	return cursor_pull(cursor, (unsigned char*)i, sizeof(*i));
}

static inline int cursor_push_u32(struct cursor *cursor, uint32_t i) {
    return cursor_push(cursor, (unsigned char*)&i, sizeof(i));
}

static inline int cursor_push_u16(struct cursor *cursor, unsigned short i)
{
	return cursor_push(cursor, (unsigned char*)&i, sizeof(i));
}

static inline int cursor_pull_u16(struct cursor *cursor, uint16_t *i)
{
	return cursor_pull(cursor, (unsigned char*)i, sizeof(*i));
}

static inline void *index_cursor(struct cursor *cursor, unsigned int index, int elem_size)
{
	unsigned char *p;
	p = &cursor->start[elem_size * index];

	if (unlikely(p >= cursor->end))
		return NULL;

	return (void*)p;
}


static inline int push_sized_str(struct cursor *cursor, const char *str, int len)
{
	return cursor_push(cursor, (unsigned char*)str, len);
}

static inline int cursor_push_lowercase(struct cursor *cur, const char *str, int len)
{
	int i;

	if (unlikely(cur->p + len >= cur->end))
		return 0;

	for (i = 0; i < len; i++)
		cur->p[i] = tolower(str[i]);

	cur->p += len;
	return 1;
}

static inline int cursor_push_str(struct cursor *cursor, const char *str)
{
	return cursor_push(cursor, (unsigned char*)str, (int)strlen(str));
}

static inline int cursor_push_c_str(struct cursor *cursor, const char *str)
{
	if (str == NULL)
		return cursor_push_byte(cursor, 0);
	return cursor_push_str(cursor, str) && cursor_push_byte(cursor, 0);
}

/* TODO: push varint size */
static inline int push_prefixed_str(struct cursor *cursor, const char *str)
{
	uint64_t len;
	len = strlen(str);
	if (!cursor_push_varint(cursor, len))
		return 0;
	return push_sized_str(cursor, str, len);
}

static inline int pull_prefixed_str(struct cursor *cursor, struct cursor *dest_buf, const char **str)
{
	uint64_t len;

	if (!cursor_pull_varint(cursor, &len))
		return 0;

	if (unlikely(dest_buf->p + len > dest_buf->end))
		return 0;

	if (!pull_data_into_cursor(cursor, dest_buf, (unsigned char**)str, len))
		return 0;

	return cursor_push_byte(dest_buf, 0);
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

static inline int pull_bytes(struct cursor *cur, int count, const unsigned char **bytes) {
    if (cur->p + count > cur->end)
        return 0;
    
    *bytes = cur->p;
    cur->p += count;
    return 1;
}

static inline int parse_str(struct cursor *cur, const char *str) {
    unsigned int i;
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

static inline int is_underscore(char c) {
    return c == '_';
}

static inline int is_utf8_byte(unsigned char c) {
    return c & 0x80;
}

static inline int parse_utf8_char(struct cursor *cursor, unsigned int *code_point, unsigned int *utf8_length)
{
    unsigned char first_byte;
    if (!parse_byte(cursor, &first_byte))
        return 0; // Not enough data

    // Determine the number of bytes in this UTF-8 character
    int remaining_bytes = 0;
    if (first_byte < 0x80) {
        *code_point = first_byte;
        return 1;
    } else if ((first_byte & 0xE0) == 0xC0) {
        remaining_bytes = 1;
        *utf8_length = remaining_bytes + 1;
        *code_point = first_byte & 0x1F;
    } else if ((first_byte & 0xF0) == 0xE0) {
        remaining_bytes = 2;
        *utf8_length = remaining_bytes + 1;
        *code_point = first_byte & 0x0F;
    } else if ((first_byte & 0xF8) == 0xF0) {
        remaining_bytes = 3;
        *utf8_length = remaining_bytes + 1;
        *code_point = first_byte & 0x07;
    } else {
        remaining_bytes = 0;
        *utf8_length = 1; // Assume 1 byte length for unrecognized UTF-8 characters
        // TODO: We need to gracefully handle unrecognized UTF-8 characters
        //printf("Invalid UTF-8 byte: %x\n", *code_point);
        *code_point = ((first_byte & 0xF0) << 6); // Prevent testing as punctuation
        return 0; // Invalid first byte
    }

    // Peek at remaining bytes
    for (int i = 0; i < remaining_bytes; ++i) {
        signed char next_byte;
        if ((next_byte = peek_char(cursor, i+1)) == -1) {
            *utf8_length = 1;
            return 0; // Not enough data
        }
        
        // Debugging lines
        //printf("Cursor: %s\n", cursor->p);
        //printf("Codepoint: %x\n", *code_point);
        //printf("Codepoint <<6: %x\n", ((*code_point << 6) | (next_byte & 0x3F)));
        //printf("Remaining bytes: %x\n", remaining_bytes);
        //printf("First byte: %x\n", first_byte);
        //printf("Next byte: %x\n", next_byte);
        //printf("Bitwise AND result: %x\n", (next_byte & 0xC0));
        
        if ((next_byte & 0xC0) != 0x80) {
            *utf8_length = 1;
            return 0; // Invalid byte in sequence
        }

        *code_point = (*code_point << 6) | (next_byte & 0x3F);
    }

    return 1;
}

/**
  * Checks if a given Unicode code point is a punctuation character
  *
  * @param codepoint The Unicode code point to check. @return true if the
  * code point is a punctuation character, false otherwise.
  */
static inline int is_punctuation(unsigned int codepoint) {

    // Check for underscore (underscore is not treated as punctuation)
    if (is_underscore(codepoint))
        return 0;
    
    // Check for ASCII punctuation
    if (codepoint <= 128 && ispunct(codepoint))
        return 1;

    // Check for Unicode punctuation exceptions (punctuation allowed in hashtags)
    if (codepoint == 0x301C || codepoint == 0xFF5E) // Japanese Wave Dash / Tilde
        return 0;
    
    // Check for Unicode punctuation
    // NOTE: We may need to adjust the codepoint ranges in the future,
    // to include/exclude certain types of Unicode characters in hashtags.
    // Unicode Blocks Reference: https://www.compart.com/en/unicode/block
    return (
        // Latin-1 Supplement No-Break Space (NBSP): U+00A0
        (codepoint == 0x00A0) ||
        
        // Latin-1 Supplement Punctuation: U+00A1 to U+00BF
        (codepoint >= 0x00A1 && codepoint <= 0x00BF) ||

        // General Punctuation: U+2000 to U+206F
        (codepoint >= 0x2000 && codepoint <= 0x206F) ||

        // Currency Symbols: U+20A0 to U+20CF
        (codepoint >= 0x20A0 && codepoint <= 0x20CF) ||

        // Supplemental Punctuation: U+2E00 to U+2E7F
        (codepoint >= 0x2E00 && codepoint <= 0x2E7F) ||

        // CJK Symbols and Punctuation: U+3000 to U+303F
        (codepoint >= 0x3000 && codepoint <= 0x303F) ||

        // Ideographic Description Characters: U+2FF0 to U+2FFF
        (codepoint >= 0x2FF0 && codepoint <= 0x2FFF)
    );
}

static inline int is_right_boundary(int c) {
    return is_whitespace(c) || is_punctuation(c);
}

static inline int is_left_boundary(char c) {
    return is_right_boundary(c) || is_utf8_byte(c);
}

static inline int is_alphanumeric(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
}

static inline int consume_until_boundary(struct cursor *cur) {
	unsigned int c;
	unsigned int char_length = 1;
	unsigned int *utf8_char_length = &char_length;
	
	while (cur->p < cur->end) {
		c = *cur->p;
		
		*utf8_char_length = 1;
		
		if (is_whitespace(c))
			return 1;
		
		// Need to check for UTF-8 characters, which can be multiple bytes long
		if (is_utf8_byte(c)) {
			if (!parse_utf8_char(cur, &c, utf8_char_length)) {
				if (!is_right_boundary(c)){
					return 0;
				}
			}
		}
		
		if (is_right_boundary(c))
			return 1;
		
		// Need to use a variable character byte length for UTF-8 (2-4 bytes)
		if (cur->p + *utf8_char_length <= cur->end)
			cur->p += *utf8_char_length;
		else
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


static inline int cursor_memset(struct cursor *cursor, unsigned char c, int n)
{
    if (cursor->p + n >= cursor->end)
        return 0;

    memset(cursor->p, c, n);
    cursor->p += n;

    return 1;
}

static void consume_whitespace_or_punctuation(struct cursor *cur)
{
	while (cur->p < cur->end) {
		if (!is_right_boundary(*cur->p))
			return;
		cur->p++;
	}
}

// pad cursor buffer to n-byte alignment
static inline int cursor_align(struct cursor *cur, int bytes) {
	size_t size = cur->p - cur->start;
	int pad;

	// pad to n-byte alignment
	pad = ((size + (bytes-1)) & ~(bytes-1)) - size;
	if (pad > 0 && !cursor_memset(cur, 0, pad))
		return 0;

	return 1;
}


#endif
