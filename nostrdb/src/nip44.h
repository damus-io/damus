
#ifndef NDB_NIP44_H
#define NDB_NIP44_H

enum ndb_decrypt_result
{
	NIP44_OK = 0,
	NIP44_ERR_UNSUPPORTED_ENCODING = 1,
	NIP44_ERR_INVALID_PAYLOAD = 2,
	NIP44_ERR_BASE64_DECODE = 3,
	NIP44_ERR_SECKEY_VERIFY_FAILED = 4,
	NIP44_ERR_PUBKEY_PARSE_FAILED = 5,
	NIP44_ERR_ECDH_FAILED = 6,
	NIP44_ERR_FILL_RANDOM_FAILED = 7,
	NIP44_ERR_INVALID_MAC = 8,
	NIP44_ERR_INVALID_PADDING = 9,
	NIP44_ERR_BUFFER_TOO_SMALL = 10,
};

struct nip44_payload {
	unsigned char version;
	unsigned char *nonce;
	unsigned char *ciphertext;
	size_t ciphertext_len;
	unsigned char *mac;
};

enum ndb_decrypt_result
nip44_decrypt(void *secp_context,
	      const unsigned char *sender_pubkey,
	      const unsigned char *receiver_seckey,
	      const char *payload, int payload_len,
	      unsigned char *buf, size_t bufsize,
	      unsigned char **decrypted, uint16_t *decrypted_len);

enum ndb_decrypt_result
nip44_encrypt(void *secp, const unsigned char *sender_seckey,
	      const unsigned char *receiver_pubkey,
	      const unsigned char *plaintext, uint16_t plaintext_size,
	      unsigned char *buf, size_t bufsize,
	      char **out, ssize_t *out_len);

enum ndb_decrypt_result
nip44_decrypt_raw(void *secp,
	      const unsigned char *sender_pubkey,
	      const unsigned char *receiver_seckey,
	      struct nip44_payload *decoded,
	      unsigned char **decrypted, uint16_t *decrypted_len);

enum ndb_decrypt_result
nip44_decode_payload(struct nip44_payload *decoded,
		     unsigned char *buf, size_t bufsize,
		     const char *payload, size_t payload_len);

const char *nip44_err_msg(enum ndb_decrypt_result res);

#endif /* NDB_METADATA_H */
