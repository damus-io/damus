/*
 * Minimal ChaCha20 (RFC 8439 "IETF" variant) providing the subset of
 * libsodium's crypto_stream_chacha20 API that nostrdb's NIP-44 code uses.
 *
 * DAMUS-LOCAL DIVERGENCE FROM UPSTREAM NOSTRDB
 * --------------------------------------------
 * Upstream nostrdb links libsodium (deps/libsodium) purely for
 * crypto_stream_chacha20_ietf_xor_ic(). Vendoring the whole of libsodium into
 * the damus Xcode project would drag in its build system, runtime CPU
 * dispatch, randombytes and utils layers for one stream cipher, so instead we
 * vendor this self-contained implementation behind the same header name and
 * function signatures. src/nip44.c is unmodified from upstream and keeps
 * including <sodium/crypto_stream_chacha20.h>; on platforms that build against
 * real libsodium the include resolves there instead and this file is unused.
 *
 * Correctness is exercised by nostrdb's own test.c NIP-44 vector tests
 * (test_nip44_test_vector, test_nip44_decrypt) and by NdbTests.
 */

#ifndef NDB_SODIUM_CRYPTO_STREAM_CHACHA20_H
#define NDB_SODIUM_CRYPTO_STREAM_CHACHA20_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define crypto_stream_chacha20_ietf_KEYBYTES 32U
#define crypto_stream_chacha20_ietf_NONCEBYTES 12U

/*
 * XOR the message m (mlen bytes) with the ChaCha20-IETF keystream generated
 * from the 32-byte key k and 12-byte nonce n, starting at block counter ic,
 * writing mlen bytes to c. c and m may alias. Always returns 0.
 */
int crypto_stream_chacha20_ietf_xor_ic(unsigned char *c, const unsigned char *m,
				       unsigned long long mlen,
				       const unsigned char *n, uint32_t ic,
				       const unsigned char *k);

/* Same, with an initial block counter of 0. */
int crypto_stream_chacha20_ietf_xor(unsigned char *c, const unsigned char *m,
				    unsigned long long mlen,
				    const unsigned char *n,
				    const unsigned char *k);

#ifdef __cplusplus
}
#endif

#endif /* NDB_SODIUM_CRYPTO_STREAM_CHACHA20_H */
