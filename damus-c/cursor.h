//
//  cursor.h
//  damus
//
//  Created by William Casarin on 2023-04-09.
//

#ifndef cursor_h
#define cursor_h

#include <ctype.h>
#include <string.h>
#include "bech32.h"

typedef unsigned char u8;

struct cursor {
    const u8 *p;
    const u8 *start;
    const u8 *end;
};

static inline int is_whitespace(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
}

static inline int is_boundary(char c) {
    return !isalnum(c);
}

static inline int is_invalid_url_ending(char c) {
    return c == '!' || c == '?' || c == ')' || c == '.' || c == ',' || c == ';';
}

static inline int is_bech32_character(char c) {
    return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || bech32_charset_rev[c] != -1;
}

static inline void make_cursor(struct cursor *c, const u8 *content, size_t len)
{
    c->start = content;
    c->end = content + len;
    c->p = content;
}

static inline int consume_until_boundary(struct cursor *cur) {
    char c;
    
    while (cur->p < cur->end) {
        c = *cur->p;
        
        if (is_boundary(c))
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

static inline int consume_until_non_bech32_character(struct cursor *cur, int or_end) {
    char c;
    int consumedAtLeastOne = 0;

    while (cur->p < cur->end) {
        c = *cur->p;

        if (!is_bech32_character(c))
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

static int parse_digit(struct cursor *cur, int *digit) {
    int c;
    if ((c = peek_char(cur, 0)) == -1)
        return 0;
    
    c -= '0';
    
    if (c >= 0 && c <= 9) {
        *digit = c;
        cur->p++;
        return 1;
    }
    return 0;
}


static inline int pull_byte(struct cursor *cur, u8 *byte) {
    if (cur->p >= cur->end)
        return 0;
        
    *byte = *cur->p;
    cur->p++;
    return 1;
}

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


#endif /* cursor_h */
