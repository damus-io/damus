

#ifndef FAST_MEMCHR_H
#define FAST_MEMCHR_H

#include <string.h>

#ifdef __ARM_NEON
#define vector_strchr neon_strchr
#else
#define vector_strchr native_memchr
#endif

#ifdef __ARM_NEON
#include <arm_neon.h>
static const char *neon_strchr(const char *str, char c, size_t length) {
	const char* end = str + length;

	// Alignment handling
	while (str < end && ((size_t)str & 0xF)) {
		if (*str == c) 
			return str;
		++str;
	}

	uint8x16_t searchChar = vdupq_n_u8(c);

	while (str + 16 <= end) {
		uint8x16_t chunk = vld1q_u8((const uint8_t*)str);
		uint8x16_t comparison = vceqq_u8(chunk, searchChar);

		// Check first 64 bits
		uint64_t result0 =
			vgetq_lane_u64(vreinterpretq_u64_u8(comparison), 0);

		if (result0)
			return str + __builtin_ctzll(result0)/8;
	
		// Check second 64 bits
		uint64_t result1 = vgetq_lane_u64(vreinterpretq_u64_u8(comparison), 1);
		if (result1)
			return str + 8 + __builtin_ctzll(result1)/8;

		str += 16;
	}

	// Handle remaining unaligned characters
	for (; str < end; ++str) {
		if (*str == c)
			return str;
	}

	return NULL;
}
#endif

static inline const char *native_memchr(const char *str, char c, size_t length) {
    const void *result = memchr(str, c, length);
    return (const char *) result;
}

static inline const char *fast_strchr(const char *str, char c, size_t length)
{
	if (length >= 16) {
		return vector_strchr(str, c, length);
	}
	
	return native_memchr(str, c, length);
}


#endif // FAST_MEMCHR_H
