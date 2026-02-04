#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "binmoji.h"

#define PRIMARY_CP_SHIFT 42
#define HASH_SHIFT 10
#define TONE1_SHIFT 7
#define TONE2_SHIFT 4
#define FLAGS_SHIFT 0

#define PRIMARY_CP_MASK 0x3FFFFF
#define HASH_MASK 0xFFFFFFFF
#define TONE_MASK 0x7
#define FLAGS_MASK 0xF

typedef struct {
	uint32_t hash;
	size_t count;
	uint32_t components[16];
} EmojiHashEntry;

#include "binmoji_table.h"

const size_t num_hash_entries =
    sizeof(binmoji_table) / sizeof(binmoji_table[0]);

static uint32_t crc32(const uint32_t *data, size_t length)
{
	uint32_t item, bit, crc = 0xFFFFFFFF;
	size_t i;
	int j;

	if (data == NULL || length == 0)
		return 0;
	for (i = 0; i < length; ++i) {
		item = data[i];
		for (j = 0; j < 32; ++j) {
			bit = (item >> (31 - j)) & 1;
			if ((crc >> 31) ^ bit) {
				crc = (crc << 1) ^ 0x04C11DB7;
			} else {
				crc = (crc << 1);
			}
		}
	}
	return crc;
}

static int is_base_emoji(uint32_t codepoint)
{
	if (codepoint >= 0x1F3FB && codepoint <= 0x1F3FF) /* Skin Tones */
		return 0;
	if (codepoint == 0x200D) /* Zero Width Joiner */
		return 0;
	return 1;
}

void binmoji_parse(const char *emoji_str, struct binmoji *binmoji)
{
	const unsigned char *s;
	memset(binmoji, 0, sizeof(struct binmoji));
	s = (const unsigned char *)emoji_str;

	while (*s) {
		uint32_t codepoint = 0;
		int len = 0;
		if (*s < 0x80) {
			len = 1;
			codepoint = s[0];
		} else if ((*s & 0xE0) == 0xC0) {
			len = 2;
			codepoint = ((s[0] & 0x1F) << 6) | (s[1] & 0x3F);
		} else if ((*s & 0xF0) == 0xE0) {
			len = 3;
			codepoint = ((s[0] & 0x0F) << 12) |
				    ((s[1] & 0x3F) << 6) | (s[2] & 0x3F);
		} else if ((*s & 0xF8) == 0xF0) {
			len = 4;
			codepoint = ((s[0] & 0x07) << 18) |
				    ((s[1] & 0x3F) << 12) |
				    ((s[2] & 0x3F) << 6) | (s[3] & 0x3F);
		} else {
			s++;
			continue;
		}
		s += len;

		if (codepoint >= 0x1F3FB && codepoint <= 0x1F3FF) {
			uint8_t tone_val = (codepoint - 0x1F3FB) + 1;
			if (binmoji->skin_tone1 == 0)
				binmoji->skin_tone1 = tone_val;
			else if (binmoji->skin_tone2 == 0)
				binmoji->skin_tone2 = tone_val;
		} else if (is_base_emoji(codepoint)) {
			if (binmoji->primary_codepoint == 0) {
				binmoji->primary_codepoint = codepoint;
			} else if (binmoji->component_count < 16) {
				binmoji->component_list
				    [binmoji->component_count++] = codepoint;
			}
		}
	}
	binmoji->component_hash =
	    crc32(binmoji->component_list, binmoji->component_count);
}

uint64_t binmoji_encode(const struct binmoji *binmoji)
{
	uint64_t id = 0;
	id |= ((uint64_t)(binmoji->primary_codepoint & PRIMARY_CP_MASK)
	       << PRIMARY_CP_SHIFT);
	id |= ((uint64_t)(binmoji->component_hash & HASH_MASK) << HASH_SHIFT);
	id |= ((uint64_t)(binmoji->skin_tone1 & TONE_MASK) << TONE1_SHIFT);
	id |= ((uint64_t)(binmoji->skin_tone2 & TONE_MASK) << TONE2_SHIFT);
	id |= ((uint64_t)(binmoji->flags & FLAGS_MASK) << FLAGS_SHIFT);
	return id;
}

/**
 * @brief Comparison function for bsearch.
 *
 * Compares a target hash key against an EmojiHashEntry's hash.
 * @param key Pointer to the target uint32_t hash.
 * @param element Pointer to the EmojiHashEntry from the array.
 * @return <0 if key is less than element's hash, 0 if equal, >0 if greater.
 */
static int compare_emoji_hash(const void *key, const void *element)
{
	const uint32_t hash_key = *(const uint32_t *)key;
	const EmojiHashEntry *entry = (const EmojiHashEntry *)element;

	if (hash_key < entry->hash) {
		return -1;
	} else if (hash_key > entry->hash) {
		return 1;
	} else {
		return 0;
	}
}

/**
 * @brief Optimized lookup using binary search.
 */
static int lookup_binmoji_by_hash(uint32_t hash, uint32_t *out_binmoji,
				  size_t *out_count)
{
	const EmojiHashEntry *result =
	    bsearch(&hash, binmoji_table, num_hash_entries,
		    sizeof(EmojiHashEntry), compare_emoji_hash);

	if (result != NULL) {
		*out_count = result->count;
		memcpy(out_binmoji, result->components,
		       (*out_count) * sizeof(uint32_t));
		return 1; /* Found */
	}

	*out_count = 0;
	return 0; /* Not found */
}

void binmoji_decode(uint64_t id, struct binmoji *binmoji)
{
	memset(binmoji, 0, sizeof(struct binmoji));
	binmoji->primary_codepoint = (id >> PRIMARY_CP_SHIFT) & PRIMARY_CP_MASK;
	binmoji->component_hash = (id >> HASH_SHIFT) & HASH_MASK;
	binmoji->skin_tone1 = (id >> TONE1_SHIFT) & TONE_MASK;
	binmoji->skin_tone2 = (id >> TONE2_SHIFT) & TONE_MASK;
	binmoji->flags = (id >> FLAGS_SHIFT) & FLAGS_MASK;
	if (binmoji->component_hash != 0) {
		lookup_binmoji_by_hash(binmoji->component_hash,
				       binmoji->component_list,
				       &binmoji->component_count);
	}
}

static int append_utf8(char *buf, size_t buf_size, size_t *offset,
		       uint32_t codepoint)
{
	char *p;
	int bytes_to_write = 0;

	if (!buf)
		return 0;
	if (codepoint < 0x80)
		bytes_to_write = 1;
	else if (codepoint < 0x800)
		bytes_to_write = 2;
	else if (codepoint < 0x10000)
		bytes_to_write = 3;
	else if (codepoint < 0x110000)
		bytes_to_write = 4;
	else
		return 0;
	if (*offset + bytes_to_write >= buf_size)
		return 0;

	p = buf + *offset;
	if (bytes_to_write == 1) {
		*p = (char)codepoint;
	} else if (bytes_to_write == 2) {
		p[0] = 0xC0 | (codepoint >> 6);
		p[1] = 0x80 | (codepoint & 0x3F);
	} else if (bytes_to_write == 3) {
		p[0] = 0xE0 | (codepoint >> 12);
		p[1] = 0x80 | ((codepoint >> 6) & 0x3F);
		p[2] = 0x80 | (codepoint & 0x3F);
	} else {
		p[0] = 0xF0 | (codepoint >> 18);
		p[1] = 0x80 | ((codepoint >> 12) & 0x3F);
		p[2] = 0x80 | ((codepoint >> 6) & 0x3F);
		p[3] = 0x80 | (codepoint & 0x3F);
	}
	*offset += bytes_to_write;
	return bytes_to_write;
}

void binmoji_to_string(const struct binmoji *binmoji, char *out_str,
		       size_t out_str_size)
{
	size_t i, offset;
	uint32_t comp;
	int needs_zwj, is_country_flag, is_subdivision_flag, no_zwj_sequence;

	if (!binmoji || !out_str || out_str_size == 0)
		return;

	offset = 0;
	out_str[0] = '\0';

	is_country_flag = (binmoji->primary_codepoint >= 0x1F1E6 &&
			   binmoji->primary_codepoint <= 0x1F1FF);

	is_subdivision_flag = (binmoji->primary_codepoint == 0x1F3F4 &&
			       binmoji->component_count > 0 &&
			       binmoji->component_list[0] >= 0xE0020 &&
			       binmoji->component_list[0] <= 0xE007F);

	no_zwj_sequence = is_country_flag || is_subdivision_flag;

	if (binmoji->primary_codepoint > 0) {
		append_utf8(out_str, out_str_size, &offset,
			    binmoji->primary_codepoint);
	}

	if (binmoji->skin_tone1 > 0) {
		append_utf8(out_str, out_str_size, &offset,
			    0x1F3FB + binmoji->skin_tone1 - 1);
	}

	for (i = 0; i < binmoji->component_count; i++) {
		comp = binmoji->component_list[i];
		needs_zwj =
		    (comp != 0xFE0F && comp != 0x20E3 && !no_zwj_sequence);

		if (needs_zwj) {
			append_utf8(out_str, out_str_size, &offset,
				    0x200D); /* ZWJ */
		}
		append_utf8(out_str, out_str_size, &offset, comp);

		if (i == binmoji->component_count - 1 &&
		    binmoji->skin_tone2 > 0) {
			append_utf8(out_str, out_str_size, &offset,
				    0x1F3FB + binmoji->skin_tone2 - 1);
		}
	}

	if (offset < out_str_size)
		out_str[offset] = '\0';
	else if (out_str_size > 0)
		out_str[out_str_size - 1] = '\0';
}
