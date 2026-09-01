/*
 * Minimal ChaCha20 (RFC 8439) implementation backing
 * sodium/crypto_stream_chacha20.h. See that header for why this exists.
 */

#include "crypto_stream_chacha20.h"

#include <string.h>

#define CHACHA20_BLOCKBYTES 64

static inline uint32_t chacha20_load32_le(const unsigned char *p)
{
	return (uint32_t)p[0]        | ((uint32_t)p[1] << 8) |
	       ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline void chacha20_store32_le(unsigned char *p, uint32_t v)
{
	p[0] = (unsigned char)(v      );
	p[1] = (unsigned char)(v >>  8);
	p[2] = (unsigned char)(v >> 16);
	p[3] = (unsigned char)(v >> 24);
}

static inline uint32_t chacha20_rotl32(uint32_t x, int n)
{
	return (x << n) | (x >> (32 - n));
}

#define CHACHA20_QUARTERROUND(a, b, c, d)		\
	do {						\
		a += b; d ^= a; d = chacha20_rotl32(d, 16); \
		c += d; b ^= c; b = chacha20_rotl32(b, 12); \
		a += b; d ^= a; d = chacha20_rotl32(d,  8); \
		c += d; b ^= c; b = chacha20_rotl32(b,  7); \
	} while (0)

/* Generate one 64-byte keystream block for the given state. */
static void chacha20_block(const uint32_t state[16], unsigned char out[CHACHA20_BLOCKBYTES])
{
	uint32_t x[16];
	int i;

	memcpy(x, state, sizeof(x));

	for (i = 0; i < 10; i++) {
		/* column rounds */
		CHACHA20_QUARTERROUND(x[0], x[4], x[ 8], x[12]);
		CHACHA20_QUARTERROUND(x[1], x[5], x[ 9], x[13]);
		CHACHA20_QUARTERROUND(x[2], x[6], x[10], x[14]);
		CHACHA20_QUARTERROUND(x[3], x[7], x[11], x[15]);
		/* diagonal rounds */
		CHACHA20_QUARTERROUND(x[0], x[5], x[10], x[15]);
		CHACHA20_QUARTERROUND(x[1], x[6], x[11], x[12]);
		CHACHA20_QUARTERROUND(x[2], x[7], x[ 8], x[13]);
		CHACHA20_QUARTERROUND(x[3], x[4], x[ 9], x[14]);
	}

	for (i = 0; i < 16; i++)
		chacha20_store32_le(out + 4 * i, x[i] + state[i]);
}

int crypto_stream_chacha20_ietf_xor_ic(unsigned char *c, const unsigned char *m,
				       unsigned long long mlen,
				       const unsigned char *n, uint32_t ic,
				       const unsigned char *k)
{
	unsigned char block[CHACHA20_BLOCKBYTES];
	uint32_t state[16];
	unsigned long long i;
	size_t j, todo;

	/* "expand 32-byte k" */
	state[ 0] = 0x61707865;
	state[ 1] = 0x3320646e;
	state[ 2] = 0x79622d32;
	state[ 3] = 0x6b206574;

	for (j = 0; j < 8; j++)
		state[4 + j] = chacha20_load32_le(k + 4 * j);

	state[12] = ic;
	state[13] = chacha20_load32_le(n + 0);
	state[14] = chacha20_load32_le(n + 4);
	state[15] = chacha20_load32_le(n + 8);

	for (i = 0; i < mlen; i += CHACHA20_BLOCKBYTES) {
		chacha20_block(state, block);

		todo = (size_t)(mlen - i);
		if (todo > CHACHA20_BLOCKBYTES)
			todo = CHACHA20_BLOCKBYTES;

		for (j = 0; j < todo; j++)
			c[i + j] = m[i + j] ^ block[j];

		/* the IETF variant uses a 32-bit counter, which wraps */
		state[12]++;
	}

	memset(block, 0, sizeof(block));
	memset(state, 0, sizeof(state));

	return 0;
}

int crypto_stream_chacha20_ietf_xor(unsigned char *c, const unsigned char *m,
				    unsigned long long mlen,
				    const unsigned char *n,
				    const unsigned char *k)
{
	return crypto_stream_chacha20_ietf_xor_ic(c, m, mlen, n, 0, k);
}
