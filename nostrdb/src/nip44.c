
#include "base64.h"
#include "secp256k1.h"
#include "secp256k1_ecdh.h"
#include "secp256k1_schnorrsig.h"
#include "hmac_sha256.h"
#include "hkdf_sha256.h"
#include "nip44.h"
#include "random.h"
#include "cursor.h"
#include "sodium/crypto_stream_chacha20.h"
#include <string.h>

#include "print_util.h"

/* NIP44 payload encryption/decryption */

static int copyx(unsigned char *output, const unsigned char *x32,
		 const unsigned char *y32, void *data)
{
	memcpy(output, x32, 32);
	return 1;
}


static int init_secp_context(secp256k1_context **ctx)
{
	unsigned char randomize[32];

	*ctx = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY);
	if (!fill_random(randomize, sizeof(randomize))) {
		return 0;
	}

	/* Randomizing the context is recommended to protect against side-channel
	 * leakage See `secp256k1_context_randomize` in secp256k1.h for more
	 * information about it. This should never fail. */
	return secp256k1_context_randomize(*ctx, randomize);
}

static enum ndb_decrypt_result
calculate_shared_secret(secp256k1_context *ctx,
			const unsigned char *seckey,
			const unsigned char *pubkey,
			unsigned char *shared_secret)
{
	secp256k1_pubkey parsed_pubkey;
	unsigned char compressed_pubkey[33];
	compressed_pubkey[0] = 2;
	memcpy(&compressed_pubkey[1], pubkey, 32);

        if (!secp256k1_ec_seckey_verify(ctx, seckey)) {
		return NIP44_ERR_SECKEY_VERIFY_FAILED;
	}

	if (!secp256k1_ec_pubkey_parse(ctx, &parsed_pubkey, compressed_pubkey, sizeof(compressed_pubkey))) {
		return NIP44_ERR_PUBKEY_PARSE_FAILED;
	}

	if (!secp256k1_ecdh(ctx, shared_secret, &parsed_pubkey, seckey, copyx, NULL)) {
		return NIP44_ERR_ECDH_FAILED;
	}

	return NIP44_OK;
}

struct message_keys {
	unsigned char key[32];
	unsigned char nonce[12];
	unsigned char auth[32];
};

static void hmac_aad(struct hmac_sha256 *out,
		     unsigned char hmac[32], unsigned char *aad,
		     const unsigned char *msg, size_t msgsize)
{
	struct hmac_sha256_ctx ctx;
	hmac_sha256_init(&ctx, hmac, 32);
	hmac_sha256_update(&ctx, aad, 32);
	hmac_sha256_update(&ctx, msg, msgsize);
	hmac_sha256_done(&ctx, out);
}

enum ndb_decrypt_result
nip44_decode_payload(struct nip44_payload *decoded,
		     unsigned char *buf, size_t bufsize,
		     const char *payload, size_t payload_len)
{
	size_t decoded_len;

	/* NOTE(jb55): we use the variant that doesn't have an
	 *             upper size limit
	 */
	if (payload_len < 132 /*|| plen > 87472*/) {
		return NIP44_ERR_INVALID_PAYLOAD;
	}

	/*
	1. Check if first payload's character is `#`

	   - `#` is an optional future-proof flag that means non-base64
	     encoding is used

	   - The `#` is not present in base64 alphabet, but, instead of
	     throwing `base64 is invalid`, implementations MUST indicate that
	     the encryption version is not yet supported
	*/ 
	if (payload[0] == '#') {
		return NIP44_ERR_UNSUPPORTED_ENCODING;
	}

	/*
	2. Decode base64
	   - Base64 is decoded into `version, nonce, ciphertext, mac`

	   - If the version is unknown, implementations must indicate that the
	     encryption version is not supported

	   - Validate length of base64 message to prevent DoS on base64
	     decoder: it can be in range from 132 to 87472 chars

	   - Validate length of decoded message to verify output of the
	     decoder: it can be in range from 99 to 65603 bytes
	*/
	decoded_len = base64_decode((char*)buf, bufsize, payload, payload_len);
	if (decoded_len == -1) {
		return NIP44_ERR_BASE64_DECODE;
	} else if (decoded_len < 99 /*|| decoded_len > 65603*/) {
		return NIP44_ERR_INVALID_PAYLOAD;
	}

	decoded->version = buf[0];
	decoded->nonce = &buf[1];
	decoded->ciphertext = &buf[33];
	decoded->ciphertext_len = decoded_len - 65;
	decoded->mac = &buf[decoded_len-32];

	return NIP44_OK;
}

#define BSWAP_16(val)				\
	((((uint16_t)(val) & 0x00ff) << 8)	\
	 | (((uint16_t)(val) & 0xff00) >> 8))

static inline uint16_t bswap_16(uint16_t val)
{
	return BSWAP_16(val);
}

static int cursor_pull_b16(struct cursor *c, uint16_t *s)
{
	if (!cursor_pull_u16(c, s))
		return 0;

	// we assume little endian
	*s = bswap_16(*s);
	return 1;
}

static int cursor_push_b16(struct cursor *c, uint16_t s)
{
	if (!cursor_push_u16(c, bswap_16(s)))
		return 0;
	return 1;
}

static inline uint16_t next_pow2_16(uint16_t v)
{
	if (v <= 1)
		return 1;

	v--; /* round down from v to (v-1) */
	v |= v >> 1;
	v |= v >> 2;
	v |= v >> 4;
	v |= v >> 8;
	v++; /* now v is next power of two */

	return v;
}

static int calc_padded_len(uint16_t unpadded_len)
{
	uint16_t chunk;

	/* enforce minimum of 32 */
	if (unpadded_len <= 32)
		return 32;

	/* For <= 256, always use 32-byte chunks. */
	if (unpadded_len <= 256) {
		chunk = 32;
	} else {
		/* next_power / 8 */
		chunk = next_pow2_16(unpadded_len) >> 3;
	}

	chunk--;

	// Round up to the next multiple of chunk (chunk is power of two)
	return (unpadded_len + chunk) & ~chunk;
}

static int unpad(unsigned char *padded_buf, size_t len, uint16_t *unpadded_len)
{
	struct cursor c;
	unsigned char *decoded_end;
	uint16_t decoded_len, decoded_end_len;

	make_cursor(padded_buf, padded_buf+len, &c);

	if (!cursor_pull_b16(&c, &decoded_len)) {
		fprintf(stderr, "unpad: couldn't pull decoded len\n");
		return 0;
	}

	decoded_end_len = decoded_len + 2;
	decoded_end = padded_buf + decoded_end_len;

	if (decoded_end > c.end) {
		fprintf(stderr, "decode debug: '%.*s'\n", (int)len-2, (const char *)(padded_buf + 2));
		fprintf(stderr, "unpad: decoded end (%d) is larger then original buf (%ld)\n",
				decoded_end_len, len);
		return 0;
	}

	c.end = decoded_end;

	*unpadded_len = (uint16_t)cursor_remaining_capacity(&c);

	if (*unpadded_len != decoded_len) {
		fprintf(stderr, "unpadded_len(%d) != decoded_len(%d)\n",
			*unpadded_len, decoded_len);
		return 0;
	}

	if (decoded_len == 0 || len != (2 + calc_padded_len(decoded_len))) {
		fprintf(stderr, "padding size is wrong\n");
		return 0;
	}

	return 1;
}

const char *nip44_err_msg(enum ndb_decrypt_result res)
{
	switch (res) {
	case NIP44_OK:
		return "ok";
	case NIP44_ERR_FILL_RANDOM_FAILED:
	       return "fill random failed";
	case NIP44_ERR_INVALID_MAC:
	       return "invalid mac";
	case NIP44_ERR_SECKEY_VERIFY_FAILED:
	       return "seckey verify failed";
	case NIP44_ERR_PUBKEY_PARSE_FAILED:
	       return "pubkey parse failed";
	case NIP44_ERR_ECDH_FAILED:
	       return "ecdh failed";
	case NIP44_ERR_INVALID_PAYLOAD:
	       return "invalid payload";
	case NIP44_ERR_UNSUPPORTED_ENCODING:
	       return "unsupported encoding";
	case NIP44_ERR_BASE64_DECODE:
	       return "error during base64 decoding";
	case NIP44_ERR_INVALID_PADDING:
	       return "invalid padding";
	case NIP44_ERR_BUFFER_TOO_SMALL:
	       return "buffer too small";
	}

	return "unknown";
}

/* ### Decryption
 * Before decryption, the event's pubkey and signature MUST be validated as
 * defined in NIP 01. The public key MUST be a valid non-zero secp256k1 curve
 * point, and the signature must be valid secp256k1 schnorr signature. For exact
 * validation rules, refer to BIP-340.
 */
enum ndb_decrypt_result
nip44_decrypt_raw(void *secp,
	      const unsigned char *sender_pubkey,
	      const unsigned char *receiver_seckey,
	      struct nip44_payload *decoded,
	      unsigned char **decrypted, uint16_t *decrypted_len)
{
	struct hmac_sha256 conversation_key;
	struct hmac_sha256 calculated_mac;
	enum ndb_decrypt_result rc;
	unsigned char shared_secret[32];
	struct message_keys keys;
	secp256k1_context *context = (secp256k1_context *)secp;

	/*
	3. Calculate a conversation key
	   - Execute ECDH (scalar multiplication) of public key B by private
	     key A Output `shared_x` must be unhashed, 32-byte encoded x
	     coordinate of the shared point
	   - Use HKDF-extract with sha256, `IKM=shared_x` and
	     `salt=utf8_encode('nip44-v2')`
	   - HKDF output will be a `conversation_key` between two users.
	*/
	if ((rc = calculate_shared_secret(context, receiver_seckey,
					  sender_pubkey, shared_secret))) {
		return rc;
	}

	hmac_sha256(&conversation_key, "nip44-v2", 8, shared_secret, 32);

	/*
	5. Calculate message keys
	   - The keys are generated from `conversation_key` and `nonce`.
	     Validate that both are 32 bytes long
	   - Use HKDF-expand, with sha256, `PRK=conversation_key`,
	                                   `info=nonce` and `L=76`
	   - Slice 76-byte HKDF output into: `chacha_key` (bytes 0..32),
	     `chacha_nonce` (bytes 32..44), `hmac_key` (bytes 44..76)
	*/
	assert(sizeof(keys) == 76);
	assert(sizeof(conversation_key) == 32);

	hkdf_expand(&keys, sizeof(keys),
		    &conversation_key, sizeof(conversation_key),
		    decoded->nonce, 32);

	/*
	6. Calculate MAC (message authentication code) with AAD and compare
	   - Stop and throw an error if MAC doesn't match the decoded one from
	     step 2
	   - Use constant-time comparison algorithm
	*/
	hmac_aad(&calculated_mac, keys.auth, decoded->nonce,
		 decoded->ciphertext, decoded->ciphertext_len);

	/* TODO(jb55): spec says this needs to be constant time memcmp,
	 *             not sure why?
	 */
	if (memcmp(calculated_mac.sha.u.u8, decoded->mac, 32)) {
		return NIP44_ERR_INVALID_MAC;
	}


	/*
	6. Decrypt ciphertext
	   - Use ChaCha20 with key and nonce from step 3
	*/
	crypto_stream_chacha20_ietf_xor_ic(decoded->ciphertext,
					   decoded->ciphertext,
					   decoded->ciphertext_len,
					   keys.nonce, 0, keys.key);

	/*
	7. Remove padding
	*/
	if (!unpad(decoded->ciphertext, decoded->ciphertext_len, decrypted_len)) {
		return NIP44_ERR_INVALID_PADDING;
	}

	*decrypted = decoded->ciphertext + 2;

	return NIP44_OK;
}

enum ndb_decrypt_result
nip44_decrypt(void *secp,
	      const unsigned char *sender_pubkey,
	      const unsigned char *receiver_seckey,
	      const char *payload, int payload_len,
	      unsigned char *buf, size_t bufsize,
	      unsigned char **decrypted, uint16_t *decrypted_len)
{
	struct nip44_payload decoded;
	enum ndb_decrypt_result rc;

	/* decode payload! */
	if ((rc = nip44_decode_payload(&decoded, buf, bufsize,
				       payload, payload_len))) {
		return rc;
	}

	return nip44_decrypt_raw(secp, sender_pubkey, receiver_seckey,
				 &decoded, decrypted, decrypted_len);
}

/* Encryption */
enum ndb_decrypt_result
nip44_encrypt(void *secp, const unsigned char *sender_seckey,
	      const unsigned char *receiver_pubkey,
	      const unsigned char *plaintext, uint16_t plaintext_size,
	      unsigned char *buf, size_t bufsize,
	      char **out, ssize_t *out_len)
{
	int rc;
	struct cursor cursor;
	struct hmac_sha256 auth, conversation_key;
	unsigned char shared_secret[32];
	unsigned char nonce[32];
	unsigned char *ciphertext;
	struct message_keys keys;
	uint16_t ciphertext_len;
	
	make_cursor(buf, buf+bufsize, &cursor);

	/* 
	1. Calculate a conversation key
	   - Execute ECDH (scalar multiplication) of public key B by private
	     key A Output `shared_x` must be unhashed, 32-byte encoded x
	     coordinate of the shared point

	   - Use HKDF-extract with sha256, `IKM=shared_x` and
	     `salt=utf8_encode('nip44-v2')`

	   - HKDF output will be a `conversation_key` between two users.

	   - It is always the same, when key roles are swapped:
	     `conv(a, B) == conv(b, A)`
	*/
	if ((rc = calculate_shared_secret(secp, sender_seckey,
					  receiver_pubkey, shared_secret))) {
		return rc;
	}

	hmac_sha256(&conversation_key, "nip44-v2", 8, shared_secret, 32);
	/*
	2. Generate a random 32-byte nonce
	   - Always use CSPRNG
	   - Don't generate a nonce from message content
	   - Don't re-use the same nonce between messages: doing so would make
	     them decryptable, but won't leak the long-term key
	*/
	if (!fill_random(nonce, sizeof(nonce))) {
		return NIP44_ERR_FILL_RANDOM_FAILED;
	}

	/*
	3. Calculate message keys
	   - The keys are generated from `conversation_key` and `nonce`.
	     Validate that both are 32 bytes long
	   - Use HKDF-expand, with sha256, `PRK=conversation_key`, `info=nonce`
	     and `L=76`
	   - Slice 76-byte HKDF output into: `chacha_key` (bytes 0..32),
	     `chacha_nonce` (bytes 32..44), `hmac_key` (bytes 44..76)
	*/
	hkdf_expand(&keys, sizeof(keys),
		    &conversation_key, sizeof(conversation_key),
		    nonce, 32);

	/*
	4. Add padding
	   - Content must be encoded from UTF-8 into byte array
	   - Validate plaintext length. Minimum is 1 byte, maximum is 65535 bytes
	   - Padding format is: `[plaintext_length:u16][plaintext][zero_bytes]`
	   - Padding algorithm is related to powers-of-two, with min padded msg
	     size of 32 bytes
	   - Plaintext length is encoded in big-endian as first 2 bytes of the
	     padded blob
	*/
	if (!cursor_push_byte(&cursor, 0x02))
		return NIP44_ERR_BUFFER_TOO_SMALL;
	if (!cursor_push(&cursor, nonce, 32))
		return NIP44_ERR_BUFFER_TOO_SMALL;

	ciphertext = cursor.p;

	if (!cursor_push_b16(&cursor, plaintext_size))
		return NIP44_ERR_BUFFER_TOO_SMALL;
	if (!cursor_push(&cursor, (unsigned char*)plaintext, plaintext_size))
		return NIP44_ERR_BUFFER_TOO_SMALL;
	if (!cursor_memset(&cursor, 0, calc_padded_len(plaintext_size) - plaintext_size))
		return NIP44_ERR_BUFFER_TOO_SMALL;

	ciphertext_len = cursor.p - ciphertext;

	/*
	5. Encrypt padded content
	   - Use ChaCha20, with key and nonce from step 3
	*/
	crypto_stream_chacha20_ietf_xor_ic(ciphertext, ciphertext,
					   ciphertext_len, keys.nonce, 0,
					   keys.key);

	/*
	6. Calculate MAC (message authentication code)
	   - AAD (additional authenticated data) is used - instead of
	     calculating MAC on ciphertext, it's calculated over a concatenation
	     of `nonce` and `ciphertext`

	   - Validate that AAD (nonce) is 32 bytes
	*/
	hmac_aad(&auth, keys.auth, nonce, ciphertext, ciphertext_len);

	if (!cursor_push(&cursor, auth.sha.u.u8, 32))
		return NIP44_ERR_BUFFER_TOO_SMALL;

	/*
	7. Base64-encode (with padding) params using `concat(version, nonce,
	ciphertext, mac)`
	*/
	*out = (char*)cursor.p;
	*out_len = base64_encode((char*)cursor.p,
				 cursor_remaining_capacity(&cursor),
				 (const char*)cursor.start,
				 cursor.p - cursor.start);

	if (*out_len == -1)
		return NIP44_ERR_BUFFER_TOO_SMALL;
	return NIP44_OK;
}

