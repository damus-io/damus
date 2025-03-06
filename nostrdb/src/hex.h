
#ifndef HEX_H
#define HEX_H

#include <stdlib.h>

static const char hex_table[256] = {
    ['0'] = 0, ['1'] = 1, ['2'] = 2, ['3'] = 3,
    ['4'] = 4, ['5'] = 5, ['6'] = 6, ['7'] = 7,
    ['8'] = 8, ['9'] = 9, ['a'] = 10, ['b'] = 11,
    ['c'] = 12, ['d'] = 13, ['e'] = 14, ['f'] = 15,
    ['A'] = 10, ['B'] = 11, ['C'] = 12, ['D'] = 13,
    ['E'] = 14, ['F'] = 15
};

static inline int char_to_hex(unsigned char *val, unsigned char c)
{
	if (hex_table[c] || c == '0') {
		*val = hex_table[c];
		return 1;
	}
	return 0;
}

static inline int hex_decode(const char *str, size_t slen, void *buf, size_t bufsize)
{
	unsigned char v1, v2;
	unsigned char *p = buf;

	while (slen > 1) {
		if (!char_to_hex(&v1, str[0]) || !char_to_hex(&v2, str[1]))
			return 0;
		if (!bufsize)
			return 0;
		*(p++) = (v1 << 4) | v2;
		str += 2;
		slen -= 2;
		bufsize--;
	}
	return slen == 0 && bufsize == 0;
}


static inline char hexchar(unsigned int val)
{
	if (val < 10)
		return '0' + val;
	if (val < 16)
		return 'a' + val - 10;
	abort();
}

static int hex_encode(const void *buf, size_t bufsize, char *dest)
{
	size_t i;

	for (i = 0; i < bufsize; i++) {
		unsigned int c = ((const unsigned char *)buf)[i];
		*(dest++) = hexchar(c >> 4);
		*(dest++) = hexchar(c & 0xF);
	}
	*dest = '\0';

	return 1;
}


#endif 
