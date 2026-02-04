
#ifndef BINMOJI_H
#define BINMOJI_H

#include <stdint.h>
#include <stdlib.h>

struct binmoji {
	uint32_t primary_codepoint;
	uint32_t component_list[16];
	size_t component_count;
	uint32_t component_hash;
	uint8_t skin_tone1;
	uint8_t skin_tone2;
	uint8_t flags;
};

static const uint64_t USER_FLAG_MASK = 1 << 3;

void     binmoji_to_string(const struct binmoji *binmoji, char *out_str, size_t out_str_size);
void     binmoji_decode(uint64_t id, struct binmoji *binmoji);
void     binmoji_parse(const char *emoji, struct binmoji *binmoji);
uint64_t binmoji_encode(const struct binmoji *binmoji);

/* some user flag helpers */
static __inline uint64_t binmoji_set_user_flag(uint64_t binmoji, uint8_t enable) {
	return enable ? (binmoji | USER_FLAG_MASK) : (binmoji & ~USER_FLAG_MASK);
}

static __inline uint8_t binmoji_get_user_flag(uint64_t binmoji) {
	return (binmoji & USER_FLAG_MASK) == USER_FLAG_MASK;
}

#endif /* BINMOJI_H */
