/*
 * ndb_negentropy.c - Native Negentropy for NostrDB
 *
 * Implementation of the negentropy set reconciliation protocol.
 * See ndb_negentropy.h for API documentation.
 */

#include "ndb_negentropy.h"
#include <string.h>
#include <stdlib.h>

/* ============================================================
 * VARINT ENCODING/DECODING
 * ============================================================
 *
 * Negentropy varints are MSB-first (most significant byte first).
 * This is the opposite of the common LEB128 encoding.
 *
 * Encoding strategy:
 * 1. Determine how many 7-bit groups we need
 * 2. Write them MSB-first, setting the high bit on all but the last
 *
 * Example: Encoding 300 (0x12C)
 *   - Binary: 0000 0001 0010 1100
 *   - 7-bit groups (MSB first): 0000010, 0101100
 *   - Add continuation bits: 10000010, 00101100
 *   - Result: 0x82 0x2C
 */


/*
 * Calculate how many bytes a value needs when encoded as a varint.
 *
 * Each byte encodes 7 bits of data, so we count how many 7-bit
 * groups are needed to represent the value.
 */
int ndb_negentropy_varint_size(uint64_t n)
{
	int size;

	/* Zero needs exactly one byte */
	if (n == 0)
		return 1;

	/* Count 7-bit groups needed */
	size = 0;
	while (n > 0) {
		size++;
		n >>= 7;
	}

	return size;
}


/*
 * Encode a 64-bit value as an MSB-first varint.
 *
 * We first calculate the size, then write bytes from most significant
 * to least significant. All bytes except the last have the high bit set.
 */
int ndb_negentropy_varint_encode(unsigned char *buf, size_t buflen, uint64_t n)
{
	int size;
	int i;

	/* Calculate required size */
	size = ndb_negentropy_varint_size(n);

	/* Guard: ensure buffer is large enough */
	if (buflen < (size_t)size)
		return 0;

	/*
	 * Write bytes from right to left (LSB to MSB position in buffer).
	 * The rightmost byte (last written) has no continuation bit.
	 * All others have the high bit set.
	 */
	for (i = size - 1; i >= 0; i--) {
		/* Extract lowest 7 bits */
		unsigned char byte = n & 0x7F;

		/* Set continuation bit on all but the last byte */
		if (i != size - 1)
			byte |= 0x80;

		buf[i] = byte;
		n >>= 7;
	}

	return size;
}


/*
 * Decode an MSB-first varint from a buffer.
 *
 * Read bytes until we find one without the continuation bit (high bit).
 * Maximum length is 10 bytes (ceil(64/7) = 10).
 */
int ndb_negentropy_varint_decode(const unsigned char *buf, size_t buflen,
                                  uint64_t *out)
{
	uint64_t result;
	size_t i;

	/* Guard: need at least one byte */
	if (buflen == 0)
		return 0;

	/* Guard: output pointer must be valid */
	if (out == NULL)
		return 0;

	result = 0;

	for (i = 0; i < buflen && i < 10; i++) {
		unsigned char byte = buf[i];

		/*
		 * Shift existing value left by 7 bits and add new 7 bits.
		 * This builds the value MSB-first.
		 */
		result = (result << 7) | (byte & 0x7F);

		/* If high bit is not set, this is the last byte */
		if ((byte & 0x80) == 0) {
			*out = result;
			return (int)(i + 1);
		}
	}

	/*
	 * If we get here, either:
	 * - We consumed 10 bytes without finding a terminator (malformed)
	 * - We ran out of buffer (incomplete)
	 */
	return 0;
}


/* ============================================================
 * HEX ENCODING UTILITIES
 * ============================================================
 */

/* Lookup table for hex encoding (lowercase as per nostr convention) */
static const char hex_chars[] = "0123456789abcdef";


/*
 * Convert binary data to lowercase hex string.
 *
 * Each input byte becomes two hex characters.
 * Output is NUL-terminated.
 */
size_t ndb_negentropy_to_hex(const unsigned char *bin, size_t len, char *hex)
{
	size_t i;

	for (i = 0; i < len; i++) {
		hex[i * 2]     = hex_chars[(bin[i] >> 4) & 0x0F];
		hex[i * 2 + 1] = hex_chars[bin[i] & 0x0F];
	}

	hex[len * 2] = '\0';
	return len * 2;
}


/*
 * Convert a single hex character to its numeric value.
 * Returns -1 for invalid characters.
 */
static int hex_char_value(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';

	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;

	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;

	return -1;
}


/*
 * Convert hex string to binary data.
 *
 * Input length must be even (two hex chars per byte).
 * Invalid hex characters cause an error return.
 */
size_t ndb_negentropy_from_hex(const char *hex, size_t hexlen,
                                unsigned char *bin, size_t binlen)
{
	size_t i;
	size_t out_len;
	int high, low;

	/* Guard: hex string must have even length */
	if (hexlen % 2 != 0)
		return 0;

	out_len = hexlen / 2;

	/* Guard: output buffer must be large enough */
	if (binlen < out_len)
		return 0;

	for (i = 0; i < out_len; i++) {
		high = hex_char_value(hex[i * 2]);
		low  = hex_char_value(hex[i * 2 + 1]);

		/* Guard: both characters must be valid hex */
		if (high < 0 || low < 0)
			return 0;

		bin[i] = (unsigned char)((high << 4) | low);
	}

	return out_len;
}


/* ============================================================
 * FINGERPRINT COMPUTATION
 * ============================================================
 */

/*
 * Initialize accumulator to zero.
 */
void ndb_negentropy_accumulator_init(struct ndb_negentropy_accumulator *acc)
{
	memset(acc->sum, 0, sizeof(acc->sum));
}


/*
 * Add a 32-byte ID to the accumulator (mod 2^256).
 *
 * Both the accumulator and ID are treated as little-endian 256-bit
 * unsigned integers. We perform byte-by-byte addition with carry
 * propagation. Any final carry is discarded (mod 2^256).
 */
void ndb_negentropy_accumulator_add(struct ndb_negentropy_accumulator *acc,
                                     const unsigned char *id)
{
	int i;
	uint16_t carry = 0;

	/*
	 * Add byte-by-byte, propagating carry.
	 * Little-endian: byte 0 is least significant.
	 */
	for (i = 0; i < 32; i++) {
		uint16_t sum = (uint16_t)acc->sum[i] + (uint16_t)id[i] + carry;
		acc->sum[i] = (unsigned char)(sum & 0xFF);
		carry = sum >> 8;
	}

	/* Carry overflow is discarded (mod 2^256) */
}


/*
 * Compute fingerprint from accumulator and count.
 *
 * The fingerprint is: SHA256(sum || varint(count))[:16]
 *
 * We need access to SHA256. NostrDB uses the ccan/crypto/sha256 library.
 */
#include "ccan/crypto/sha256/sha256.h"

void ndb_negentropy_fingerprint(const struct ndb_negentropy_accumulator *acc,
                                 size_t count,
                                 unsigned char *out)
{
	struct sha256 hash;
	unsigned char buf[32 + 10];  /* 32-byte sum + up to 10-byte varint */
	int varint_len;
	size_t total_len;

	/* Copy the 32-byte sum */
	memcpy(buf, acc->sum, 32);

	/* Append count as varint */
	varint_len = ndb_negentropy_varint_encode(buf + 32, 10, (uint64_t)count);
	total_len = 32 + (size_t)varint_len;

	/* Hash and take first 16 bytes */
	sha256(&hash, buf, total_len);
	memcpy(out, hash.u.u8, 16);
}


/* ============================================================
 * BOUND ENCODING/DECODING
 * ============================================================
 */

/*
 * Encode a bound into a buffer.
 *
 * Format: <encodedTimestamp (Varint)> <prefixLen (Varint)> <idPrefix (bytes)>
 *
 * Timestamp encoding:
 * - UINT64_MAX ("infinity") encodes as 0
 * - All other values encode as (1 + delta_from_previous)
 */
int ndb_negentropy_bound_encode(unsigned char *buf, size_t buflen,
                                 const struct ndb_negentropy_bound *bound,
                                 uint64_t *prev_timestamp)
{
	size_t offset = 0;
	int written;
	uint64_t encoded_ts;

	/* Guard: validate inputs */
	if (buf == NULL || bound == NULL || prev_timestamp == NULL)
		return 0;

	/*
	 * Encode timestamp:
	 * - Infinity (UINT64_MAX) -> 0
	 * - Otherwise -> 1 + (timestamp - prev_timestamp)
	 */
	if (bound->timestamp == UINT64_MAX) {
		encoded_ts = 0;
	} else {
		uint64_t delta = bound->timestamp - *prev_timestamp;
		encoded_ts = 1 + delta;
		*prev_timestamp = bound->timestamp;
	}

	/* Write encoded timestamp */
	written = ndb_negentropy_varint_encode(buf + offset, buflen - offset, encoded_ts);
	if (written == 0)
		return 0;
	offset += (size_t)written;

	/* Write prefix length */
	written = ndb_negentropy_varint_encode(buf + offset, buflen - offset,
	                                        (uint64_t)bound->prefix_len);
	if (written == 0)
		return 0;
	offset += (size_t)written;

	/* Guard: ensure room for prefix bytes */
	if (offset + bound->prefix_len > buflen)
		return 0;

	/* Write ID prefix bytes */
	if (bound->prefix_len > 0)
		memcpy(buf + offset, bound->id_prefix, bound->prefix_len);
	offset += bound->prefix_len;

	return (int)offset;
}


/*
 * Decode a bound from a buffer.
 */
int ndb_negentropy_bound_decode(const unsigned char *buf, size_t buflen,
                                 struct ndb_negentropy_bound *bound,
                                 uint64_t *prev_timestamp)
{
	size_t offset = 0;
	int consumed;
	uint64_t encoded_ts;
	uint64_t prefix_len;

	/* Guard: validate inputs */
	if (buf == NULL || bound == NULL || prev_timestamp == NULL)
		return 0;

	/* Read encoded timestamp */
	consumed = ndb_negentropy_varint_decode(buf + offset, buflen - offset, &encoded_ts);
	if (consumed == 0)
		return 0;
	offset += (size_t)consumed;

	/*
	 * Decode timestamp:
	 * - 0 -> Infinity (UINT64_MAX)
	 * - Otherwise -> prev_timestamp + (encoded_ts - 1)
	 */
	if (encoded_ts == 0) {
		bound->timestamp = UINT64_MAX;
	} else {
		uint64_t delta = encoded_ts - 1;

		/* Guard: check for timestamp overflow */
		if (delta > UINT64_MAX - *prev_timestamp)
			return 0;

		bound->timestamp = *prev_timestamp + delta;
		*prev_timestamp = bound->timestamp;
	}

	/* Read prefix length */
	consumed = ndb_negentropy_varint_decode(buf + offset, buflen - offset, &prefix_len);
	if (consumed == 0)
		return 0;
	offset += (size_t)consumed;

	/* Guard: prefix length must be <= 32 */
	if (prefix_len > 32)
		return 0;

	bound->prefix_len = (uint8_t)prefix_len;

	/* Guard: ensure buffer has enough bytes for prefix */
	if (offset + bound->prefix_len > buflen)
		return 0;

	/* Read ID prefix bytes, zero the rest */
	memset(bound->id_prefix, 0, 32);
	if (bound->prefix_len > 0)
		memcpy(bound->id_prefix, buf + offset, bound->prefix_len);
	offset += bound->prefix_len;

	return (int)offset;
}


/* ============================================================
 * RANGE ENCODING/DECODING
 * ============================================================
 *
 * Ranges are the core unit of negentropy messages. Each range
 * specifies a section of the item space and what to do with it.
 */


/*
 * Encode a range into a buffer.
 *
 * Format: <bound> <mode> <payload>
 *
 * We use early returns for each error condition to avoid deep nesting.
 */
int ndb_negentropy_range_encode(unsigned char *buf, size_t buflen,
                                 const struct ndb_negentropy_range *range,
                                 uint64_t *prev_timestamp)
{
	size_t offset = 0;
	int written;

	/* Guard: validate inputs */
	if (buf == NULL || range == NULL || prev_timestamp == NULL)
		return 0;

	/* Encode the upper bound */
	written = ndb_negentropy_bound_encode(buf + offset, buflen - offset,
	                                       &range->upper_bound, prev_timestamp);
	if (written == 0)
		return 0;
	offset += (size_t)written;

	/* Encode the mode */
	written = ndb_negentropy_varint_encode(buf + offset, buflen - offset,
	                                        (uint64_t)range->mode);
	if (written == 0)
		return 0;
	offset += (size_t)written;

	/* Encode the payload based on mode */
	switch (range->mode) {

	case NDB_NEG_SKIP:
		/* No payload for SKIP mode */
		break;

	case NDB_NEG_FINGERPRINT:
		/* 16-byte fingerprint */
		if (offset + 16 > buflen)
			return 0;
		memcpy(buf + offset, range->payload.fingerprint, 16);
		offset += 16;
		break;

	case NDB_NEG_IDLIST: {
		/*
		 * IdList: <count (Varint)> <ids (32 bytes each)>
		 */
		size_t id_count = range->payload.id_list.id_count;
		size_t ids_size = id_count * 32;

		/* Write count */
		written = ndb_negentropy_varint_encode(buf + offset, buflen - offset,
		                                        (uint64_t)id_count);
		if (written == 0)
			return 0;
		offset += (size_t)written;

		/* Guard: ensure room for all IDs */
		if (offset + ids_size > buflen)
			return 0;

		/* Write IDs */
		if (id_count > 0 && range->payload.id_list.ids != NULL)
			memcpy(buf + offset, range->payload.id_list.ids, ids_size);
		offset += ids_size;
		break;
	}

	case NDB_NEG_IDLIST_RESPONSE: {
		/*
		 * IdListResponse:
		 *   <haveIds (IdList)> <bitfieldLen (Varint)> <bitfield>
		 *
		 * haveIds is an IdList (count + ids) of IDs the server has.
		 * bitfield indicates which client IDs the server needs.
		 */
		size_t have_count = range->payload.id_list_response.have_count;
		size_t have_size = have_count * 32;
		size_t bf_len = range->payload.id_list_response.bitfield_len;

		/* Write have_count */
		written = ndb_negentropy_varint_encode(buf + offset, buflen - offset,
		                                        (uint64_t)have_count);
		if (written == 0)
			return 0;
		offset += (size_t)written;

		/* Guard: ensure room for have_ids */
		if (offset + have_size > buflen)
			return 0;

		/* Write have_ids */
		if (have_count > 0 && range->payload.id_list_response.have_ids != NULL)
			memcpy(buf + offset, range->payload.id_list_response.have_ids, have_size);
		offset += have_size;

		/* Write bitfield length */
		written = ndb_negentropy_varint_encode(buf + offset, buflen - offset,
		                                        (uint64_t)bf_len);
		if (written == 0)
			return 0;
		offset += (size_t)written;

		/* Guard: ensure room for bitfield */
		if (offset + bf_len > buflen)
			return 0;

		/* Write bitfield */
		if (bf_len > 0 && range->payload.id_list_response.bitfield != NULL)
			memcpy(buf + offset, range->payload.id_list_response.bitfield, bf_len);
		offset += bf_len;
		break;
	}

	default:
		/* Unknown mode */
		return 0;
	}

	return (int)offset;
}


/*
 * Decode a range from a buffer.
 *
 * For IDLIST and IDLIST_RESPONSE modes, the payload pointers point
 * directly into the input buffer for zero-copy access.
 */
int ndb_negentropy_range_decode(const unsigned char *buf, size_t buflen,
                                 struct ndb_negentropy_range *range,
                                 uint64_t *prev_timestamp)
{
	size_t offset = 0;
	int consumed;
	uint64_t mode_val;

	/* Guard: validate inputs */
	if (buf == NULL || range == NULL || prev_timestamp == NULL)
		return 0;

	/* Decode the upper bound */
	consumed = ndb_negentropy_bound_decode(buf + offset, buflen - offset,
	                                        &range->upper_bound, prev_timestamp);
	if (consumed == 0)
		return 0;
	offset += (size_t)consumed;

	/* Decode the mode */
	consumed = ndb_negentropy_varint_decode(buf + offset, buflen - offset, &mode_val);
	if (consumed == 0)
		return 0;
	offset += (size_t)consumed;

	/* Guard: mode must be valid */
	if (mode_val > NDB_NEG_IDLIST_RESPONSE)
		return 0;
	range->mode = (enum ndb_negentropy_mode)mode_val;

	/* Decode payload based on mode */
	switch (range->mode) {

	case NDB_NEG_SKIP:
		/* No payload */
		break;

	case NDB_NEG_FINGERPRINT:
		/* 16-byte fingerprint */
		if (offset + 16 > buflen)
			return 0;
		memcpy(range->payload.fingerprint, buf + offset, 16);
		offset += 16;
		break;

	case NDB_NEG_IDLIST: {
		/*
		 * IdList: <count (Varint)> <ids (32 bytes each)>
		 */
		uint64_t id_count;
		size_t ids_size;

		/* Read count */
		consumed = ndb_negentropy_varint_decode(buf + offset, buflen - offset, &id_count);
		if (consumed == 0)
			return 0;
		offset += (size_t)consumed;

		/* Guard: prevent DOS and overflow in multiplication */
		if (id_count > NDB_NEGENTROPY_MAX_IDS_PER_RANGE)
			return 0;

		ids_size = (size_t)id_count * 32;

		/* Guard: ensure buffer has all IDs */
		if (offset + ids_size > buflen)
			return 0;

		/* Point directly into buffer (zero-copy) */
		range->payload.id_list.id_count = (size_t)id_count;
		range->payload.id_list.ids = (id_count > 0) ? (buf + offset) : NULL;
		offset += ids_size;
		break;
	}

	case NDB_NEG_IDLIST_RESPONSE: {
		/*
		 * IdListResponse:
		 *   <haveIds (IdList)> <bitfieldLen (Varint)> <bitfield>
		 */
		uint64_t have_count;
		size_t have_size;
		uint64_t bf_len;

		/* Read have_count */
		consumed = ndb_negentropy_varint_decode(buf + offset, buflen - offset, &have_count);
		if (consumed == 0)
			return 0;
		offset += (size_t)consumed;

		/* Guard: prevent DOS and overflow in multiplication */
		if (have_count > NDB_NEGENTROPY_MAX_IDS_PER_RANGE)
			return 0;

		have_size = (size_t)have_count * 32;

		/* Guard: ensure buffer has all have_ids */
		if (offset + have_size > buflen)
			return 0;

		/* Point directly into buffer (zero-copy) */
		range->payload.id_list_response.have_count = (size_t)have_count;
		range->payload.id_list_response.have_ids = (have_count > 0) ? (buf + offset) : NULL;
		offset += have_size;

		/* Read bitfield length */
		consumed = ndb_negentropy_varint_decode(buf + offset, buflen - offset, &bf_len);
		if (consumed == 0)
			return 0;
		offset += (size_t)consumed;

		/*
		 * Guard: bitfield length sanity check.
		 * Bitfield is ceil(client_id_count / 8), so max is ~12KB
		 * for 100K IDs. Use generous 1MB limit.
		 */
		if (bf_len > (1024 * 1024))
			return 0;

		/* Guard: ensure buffer has bitfield */
		if (offset + bf_len > buflen)
			return 0;

		/* Point directly into buffer (zero-copy) */
		range->payload.id_list_response.bitfield_len = (size_t)bf_len;
		range->payload.id_list_response.bitfield = (bf_len > 0) ? (buf + offset) : NULL;
		offset += bf_len;
		break;
	}

	default:
		/* Unknown mode */
		return 0;
	}

	return (int)offset;
}


/* ============================================================
 * MESSAGE ENCODING/DECODING
 * ============================================================
 *
 * Messages are the complete wire-format units. Each message
 * starts with a version byte followed by concatenated ranges.
 */


/*
 * Encode a complete negentropy message.
 *
 * Format: <version (1 byte)> <range>*
 */
int ndb_negentropy_message_encode(unsigned char *buf, size_t buflen,
                                   const struct ndb_negentropy_range *ranges,
                                   size_t num_ranges)
{
	size_t offset = 0;
	size_t i;
	uint64_t prev_timestamp = 0;
	int written;

	/* Guard: need at least 1 byte for version */
	if (buf == NULL || buflen < 1)
		return 0;

	/* Guard: enforce range limit for DOS protection */
	if (num_ranges > NDB_NEGENTROPY_MAX_RANGES)
		return 0;

	/* Write protocol version byte */
	buf[offset++] = NDB_NEGENTROPY_PROTOCOL_V1;

	/* Encode each range */
	for (i = 0; i < num_ranges; i++) {
		written = ndb_negentropy_range_encode(buf + offset, buflen - offset,
		                                       &ranges[i], &prev_timestamp);
		if (written == 0)
			return 0;

		offset += (size_t)written;
	}

	return (int)offset;
}


/*
 * Get the protocol version from a message.
 *
 * Simply returns the first byte, which is the version.
 */
int ndb_negentropy_message_version(const unsigned char *buf, size_t buflen)
{
	if (buf == NULL || buflen < 1)
		return 0;

	return (int)buf[0];
}


/*
 * Count ranges in a message.
 *
 * We parse through the message skipping the version byte,
 * then iterate through ranges counting each one.
 */
int ndb_negentropy_message_count_ranges(const unsigned char *buf, size_t buflen)
{
	const unsigned char *p;
	size_t remaining;
	uint64_t prev_timestamp = 0;
	struct ndb_negentropy_range range;
	int count = 0;
	int consumed;

	/* Guard: need at least version byte */
	if (buf == NULL || buflen < 1)
		return -1;

	/* Check version is V1 */
	if (buf[0] != NDB_NEGENTROPY_PROTOCOL_V1)
		return -1;

	/* Skip version byte */
	p = buf + 1;
	remaining = buflen - 1;

	/*
	 * Parse ranges until buffer exhausted.
	 * We use the actual decode function to ensure we count
	 * correctly even with complex payloads.
	 */
	while (remaining > 0) {
		consumed = ndb_negentropy_range_decode(p, remaining, &range, &prev_timestamp);

		/* Decode error */
		if (consumed == 0)
			return -1;

		/* Guard: ensure we don't exceed limit */
		count++;
		if (count > NDB_NEGENTROPY_MAX_RANGES)
			return -1;

		p += consumed;
		remaining -= (size_t)consumed;
	}

	return count;
}


/* ============================================================
 * NEGENTROPY STORAGE
 * ============================================================
 *
 * Storage manages a sorted array of (timestamp, id) items for
 * use in negentropy reconciliation.
 */

/* Initial capacity for item array */
#define STORAGE_INITIAL_CAPACITY 64


/*
 * Compare two items for sorting.
 *
 * Primary sort: timestamp (ascending)
 * Secondary sort: id (lexicographic ascending)
 */
static int item_compare(const void *a, const void *b)
{
	const struct ndb_negentropy_item *ia = a;
	const struct ndb_negentropy_item *ib = b;

	/* Compare timestamp first */
	if (ia->timestamp < ib->timestamp)
		return -1;
	if (ia->timestamp > ib->timestamp)
		return 1;

	/* Timestamps equal - compare IDs lexicographically */
	return memcmp(ia->id, ib->id, 32);
}


/*
 * Compare an item to a bound for binary search.
 *
 * Returns:
 *   < 0 if item < bound
 *   = 0 if item == bound
 *   > 0 if item > bound
 */
static int item_bound_compare(const struct ndb_negentropy_item *item,
                               const struct ndb_negentropy_bound *bound)
{
	int cmp;
	int i;

	/* Handle infinity bound */
	if (bound->timestamp == UINT64_MAX)
		return -1;  /* Item is always < infinity */

	/* Compare timestamp */
	if (item->timestamp < bound->timestamp)
		return -1;
	if (item->timestamp > bound->timestamp)
		return 1;

	/* Timestamps equal - compare ID prefix */
	if (bound->prefix_len > 0) {
		cmp = memcmp(item->id, bound->id_prefix, bound->prefix_len);
		if (cmp != 0)
			return cmp;
	}

	/*
	 * Prefix matches. Per negentropy spec, omitted bytes in bound
	 * are implicitly zero. Check if item has any non-zero bytes
	 * after the prefix - if so, item > bound.
	 */
	for (i = bound->prefix_len; i < 32; i++) {
		if (item->id[i] != 0)
			return 1;  /* item > bound */
	}

	/* Complete match */
	return 0;
}


/*
 * Ensure storage has room for at least one more item.
 * Grows the array if necessary.
 */
static int storage_ensure_capacity(struct ndb_negentropy_storage *storage)
{
	size_t new_capacity;
	struct ndb_negentropy_item *new_items;

	if (storage->count < storage->capacity)
		return 1;

	/* Grow by doubling */
	new_capacity = storage->capacity * 2;
	if (new_capacity < STORAGE_INITIAL_CAPACITY)
		new_capacity = STORAGE_INITIAL_CAPACITY;

	new_items = realloc(storage->items,
	                    new_capacity * sizeof(struct ndb_negentropy_item));
	if (new_items == NULL)
		return 0;

	storage->items = new_items;
	storage->capacity = new_capacity;
	return 1;
}


int ndb_negentropy_storage_init(struct ndb_negentropy_storage *storage)
{
	if (storage == NULL)
		return 0;

	storage->items = NULL;
	storage->count = 0;
	storage->capacity = 0;
	storage->sealed = 0;

	return 1;
}


void ndb_negentropy_storage_destroy(struct ndb_negentropy_storage *storage)
{
	if (storage == NULL)
		return;

	free(storage->items);
	storage->items = NULL;
	storage->count = 0;
	storage->capacity = 0;
	storage->sealed = 0;
}


int ndb_negentropy_storage_add(struct ndb_negentropy_storage *storage,
                                uint64_t timestamp,
                                const unsigned char *id)
{
	struct ndb_negentropy_item *item;

	/* Guard: validate inputs */
	if (storage == NULL || id == NULL)
		return 0;

	/* Guard: cannot add after sealing */
	if (storage->sealed)
		return 0;

	/* Ensure capacity */
	if (!storage_ensure_capacity(storage))
		return 0;

	/* Add the item */
	item = &storage->items[storage->count];
	item->timestamp = timestamp;
	memcpy(item->id, id, 32);
	storage->count++;

	return 1;
}


int ndb_negentropy_storage_add_many(struct ndb_negentropy_storage *storage,
                                     const struct ndb_negentropy_item *items,
                                     size_t count)
{
	size_t needed;
	size_t new_capacity;
	struct ndb_negentropy_item *new_items;
	size_t i;

	/* Guard: validate inputs */
	if (storage == NULL)
		return 0;

	if (count == 0)
		return 1;

	if (items == NULL)
		return 0;

	/* Guard: cannot add after sealing */
	if (storage->sealed)
		return 0;

	/* Ensure capacity for all items */
	needed = storage->count + count;
	if (needed > storage->capacity) {
		new_capacity = storage->capacity;
		if (new_capacity < STORAGE_INITIAL_CAPACITY)
			new_capacity = STORAGE_INITIAL_CAPACITY;

		while (new_capacity < needed)
			new_capacity *= 2;

		new_items = realloc(storage->items,
		                    new_capacity * sizeof(struct ndb_negentropy_item));
		if (new_items == NULL)
			return 0;

		storage->items = new_items;
		storage->capacity = new_capacity;
	}

	/* Copy items */
	for (i = 0; i < count; i++) {
		storage->items[storage->count + i] = items[i];
	}
	storage->count += count;

	return 1;
}


int ndb_negentropy_storage_seal(struct ndb_negentropy_storage *storage)
{
	/* Guard: validate input */
	if (storage == NULL)
		return 0;

	/* Guard: cannot seal twice */
	if (storage->sealed)
		return 0;

	/* Sort items by (timestamp, id) */
	if (storage->count > 0) {
		qsort(storage->items, storage->count,
		      sizeof(struct ndb_negentropy_item), item_compare);
	}

	storage->sealed = 1;
	return 1;
}


size_t ndb_negentropy_storage_size(const struct ndb_negentropy_storage *storage)
{
	if (storage == NULL)
		return 0;

	return storage->count;
}


const struct ndb_negentropy_item *
ndb_negentropy_storage_get(const struct ndb_negentropy_storage *storage, size_t index)
{
	/* Guard: validate input */
	if (storage == NULL)
		return NULL;

	/* Guard: must be sealed */
	if (!storage->sealed)
		return NULL;

	/* Guard: bounds check */
	if (index >= storage->count)
		return NULL;

	return &storage->items[index];
}


size_t ndb_negentropy_storage_lower_bound(const struct ndb_negentropy_storage *storage,
                                           const struct ndb_negentropy_bound *bound)
{
	size_t lo, hi, mid;
	int cmp;

	/* Guard: validate inputs */
	if (storage == NULL || bound == NULL)
		return 0;

	/* Guard: must be sealed */
	if (!storage->sealed)
		return 0;

	/* Empty storage */
	if (storage->count == 0)
		return 0;

	/* Binary search for lower bound */
	lo = 0;
	hi = storage->count;

	while (lo < hi) {
		mid = lo + (hi - lo) / 2;

		cmp = item_bound_compare(&storage->items[mid], bound);

		if (cmp < 0) {
			/* Item is less than bound, search right half */
			lo = mid + 1;
		} else {
			/* Item is >= bound, search left half */
			hi = mid;
		}
	}

	return lo;
}


int ndb_negentropy_storage_fingerprint(const struct ndb_negentropy_storage *storage,
                                        size_t begin, size_t end,
                                        unsigned char *fingerprint_out)
{
	struct ndb_negentropy_accumulator acc;
	size_t i;
	size_t count;

	/* Guard: validate inputs */
	if (storage == NULL || fingerprint_out == NULL)
		return 0;

	/* Guard: must be sealed */
	if (!storage->sealed)
		return 0;

	/* Guard: valid range */
	if (begin > end || end > storage->count)
		return 0;

	/* Initialize accumulator */
	ndb_negentropy_accumulator_init(&acc);

	/* Add all IDs in range to accumulator */
	for (i = begin; i < end; i++) {
		ndb_negentropy_accumulator_add(&acc, storage->items[i].id);
	}

	/* Compute fingerprint */
	count = end - begin;
	ndb_negentropy_fingerprint(&acc, count, fingerprint_out);

	return 1;
}


/* ============================================================
 * FILTER-BASED INITIALIZATION (NostrDB Integration)
 * ============================================================
 *
 * This section requires the full nostrdb library. It's compiled
 * only when NDB_NEGENTROPY_NOSTRDB is defined (which happens
 * automatically when building as part of nostrdb).
 *
 * For standalone testing of core negentropy functions, compile
 * without this define.
 */

#ifndef NDB_NEGENTROPY_STANDALONE

#include "nostrdb.h"

/* Default limit for filter queries if not specified */
#define DEFAULT_QUERY_LIMIT 10000


/**
 * Populate storage from a NostrDB filter query.
 *
 * Queries the database using the provided filter and adds all matching
 * events to the storage. The storage is automatically sealed after
 * population.
 *
 * @param storage  Initialized (but not sealed) storage
 * @param txn      Active read transaction
 * @param filter   NIP-01 filter to query events
 * @param limit    Max events to add (0 = DEFAULT_QUERY_LIMIT)
 * @return Number of items added, or -1 on error
 */
int ndb_negentropy_storage_from_filter(struct ndb_negentropy_storage *storage,
                                        struct ndb_txn *txn,
                                        struct ndb_filter *filter,
                                        int limit)
{
	struct ndb_query_result *results;
	int result_count;
	int query_limit;
	int i;
	int added;

	/* Guard: validate inputs */
	if (storage == NULL || txn == NULL || filter == NULL)
		return -1;

	/* Guard: storage must not already be sealed */
	if (storage->sealed)
		return -1;

	/* Determine query limit */
	query_limit = (limit > 0) ? limit : DEFAULT_QUERY_LIMIT;

	/* Allocate results buffer */
	results = malloc((size_t)query_limit * sizeof(struct ndb_query_result));
	if (results == NULL)
		return -1;

	result_count = 0;
	added = 0;

	/* Execute query */
	if (!ndb_query(txn, filter, 1, results, query_limit, &result_count)) {
		free(results);
		return -1;
	}

	/* Add each result to storage */
	for (i = 0; i < result_count; i++) {
		struct ndb_note *note = results[i].note;
		uint64_t timestamp;
		unsigned char *id;

		/* Get timestamp and ID from note */
		timestamp = (uint64_t)ndb_note_created_at(note);
		id = ndb_note_id(note);

		/* Add to storage (copies the ID) */
		if (!ndb_negentropy_storage_add(storage, timestamp, id)) {
			free(results);
			return -1;
		}

		added++;
	}

	free(results);

	/* Seal storage after populating from filter */
	if (!ndb_negentropy_storage_seal(storage))
		return -1;

	return added;
}

#endif /* NDB_NEGENTROPY_STANDALONE */


/* ============================================================
 * RECONCILIATION STATE MACHINE
 * ============================================================
 *
 * The reconciliation engine implements the negentropy protocol
 * for determining set differences between two parties.
 */

/* Initial capacity for ID arrays */
#define IDS_INITIAL_CAPACITY 64


/*
 * Initialize an ID array.
 */
static void ids_init(struct ndb_negentropy_ids *ids)
{
	ids->ids = NULL;
	ids->count = 0;
	ids->capacity = 0;
}


/*
 * Free an ID array.
 */
static void ids_destroy(struct ndb_negentropy_ids *ids)
{
	free(ids->ids);
	ids->ids = NULL;
	ids->count = 0;
	ids->capacity = 0;
}


/*
 * Add an ID to an ID array.
 */
static int ids_add(struct ndb_negentropy_ids *ids, const unsigned char *id)
{
	size_t new_capacity;
	unsigned char *new_ids;

	/* Grow if needed */
	if (ids->count >= ids->capacity) {
		new_capacity = ids->capacity * 2;
		if (new_capacity < IDS_INITIAL_CAPACITY)
			new_capacity = IDS_INITIAL_CAPACITY;

		new_ids = realloc(ids->ids, new_capacity * 32);
		if (new_ids == NULL)
			return 0;

		ids->ids = new_ids;
		ids->capacity = new_capacity;
	}

	/* Copy ID */
	memcpy(ids->ids + ids->count * 32, id, 32);
	ids->count++;

	return 1;
}


/*
 * Check if storage contains an ID using binary search.
 * Returns 1 if found, 0 if not.
 */
static int storage_has_id(const struct ndb_negentropy_storage *storage,
                           uint64_t timestamp, const unsigned char *id)
{
	struct ndb_negentropy_bound bound;
	size_t idx;
	const struct ndb_negentropy_item *item;

	/* Create bound for the ID */
	bound.timestamp = timestamp;
	memcpy(bound.id_prefix, id, 32);
	bound.prefix_len = 32;

	/* Find lower bound */
	idx = ndb_negentropy_storage_lower_bound(storage, &bound);

	/* Check if we found an exact match */
	if (idx >= storage->count)
		return 0;

	item = &storage->items[idx];
	if (item->timestamp != timestamp)
		return 0;

	return memcmp(item->id, id, 32) == 0;
}


int ndb_negentropy_init(struct ndb_negentropy *neg,
                         const struct ndb_negentropy_storage *storage,
                         const struct ndb_negentropy_config *config)
{
	/* Guard: validate inputs */
	if (neg == NULL || storage == NULL)
		return 0;

	/* Guard: storage must be sealed */
	if (!storage->sealed)
		return 0;

	neg->storage = storage;
	neg->is_initiator = 0;
	neg->is_complete = 0;

	/* Apply config or use defaults */
	if (config != NULL) {
		neg->frame_size_limit = config->frame_size_limit;
		neg->idlist_threshold = config->idlist_threshold > 0
		                        ? config->idlist_threshold
		                        : NDB_NEGENTROPY_IDLIST_THRESHOLD;
		neg->split_count = config->split_count > 1
		                   ? config->split_count
		                   : NDB_NEGENTROPY_SPLIT_COUNT;
	} else {
		neg->frame_size_limit = 0;  /* unlimited */
		neg->idlist_threshold = NDB_NEGENTROPY_IDLIST_THRESHOLD;
		neg->split_count = NDB_NEGENTROPY_SPLIT_COUNT;
	}

	ids_init(&neg->have_ids);
	ids_init(&neg->need_ids);

	return 1;
}


void ndb_negentropy_destroy(struct ndb_negentropy *neg)
{
	if (neg == NULL)
		return;

	ids_destroy(&neg->have_ids);
	ids_destroy(&neg->need_ids);
	neg->storage = NULL;
	neg->is_initiator = 0;
	neg->is_complete = 0;
}


int ndb_negentropy_is_complete(const struct ndb_negentropy *neg)
{
	if (neg == NULL)
		return 0;

	return neg->is_complete;
}


int ndb_negentropy_initiate(struct ndb_negentropy *neg,
                             unsigned char *buf, size_t buflen,
                             size_t *outlen)
{
	struct ndb_negentropy_range range;
	int len;

	/* Guard: validate inputs */
	if (neg == NULL || buf == NULL || outlen == NULL)
		return 0;

	/* Guard: need room for version + range */
	if (buflen < 2)
		return 0;

	/* Mark as initiator */
	neg->is_initiator = 1;

	/*
	 * Create initial message with single FINGERPRINT range
	 * covering the entire item space (0 to infinity).
	 */
	range.upper_bound.timestamp = UINT64_MAX;
	range.upper_bound.prefix_len = 0;
	range.mode = NDB_NEG_FINGERPRINT;

	/* Compute fingerprint of all items */
	if (!ndb_negentropy_storage_fingerprint(neg->storage, 0,
	                                         neg->storage->count,
	                                         range.payload.fingerprint))
		return 0;

	/* Encode message */
	len = ndb_negentropy_message_encode(buf, buflen, &range, 1);
	if (len == 0)
		return 0;

	*outlen = (size_t)len;
	return 1;
}


/*
 * Create a bound from a storage item at the given index.
 * If index == count, creates an infinity bound.
 */
static void bound_from_index(const struct ndb_negentropy_storage *storage,
                              size_t index,
                              struct ndb_negentropy_bound *bound)
{
	if (index >= storage->count) {
		/* Infinity bound */
		bound->timestamp = UINT64_MAX;
		bound->prefix_len = 0;
	} else {
		/* Bound from item */
		const struct ndb_negentropy_item *item = &storage->items[index];
		bound->timestamp = item->timestamp;
		memcpy(bound->id_prefix, item->id, 32);
		bound->prefix_len = 32;
	}
}


/*
 * Process incoming ranges and build response.
 * This is the core reconciliation logic.
 */
int ndb_negentropy_reconcile(struct ndb_negentropy *neg,
                              const unsigned char *msg, size_t msglen,
                              unsigned char *out, size_t *outlen)
{
	const unsigned char *p;
	size_t remaining;
	uint64_t prev_ts_in = 0;
	uint64_t prev_ts_out = 0;
	size_t out_offset;
	size_t lower_idx = 0;  /* Current position in our storage */
	struct ndb_negentropy_range in_range;
	int consumed;
	int received_non_skip = 0;  /* Track if we received any non-SKIP input */

	/* Guard: validate inputs */
	if (neg == NULL || msg == NULL || out == NULL || outlen == NULL)
		return 0;

	/* Guard: need at least version byte */
	if (msglen < 1 || *outlen < 1)
		return 0;

	/* Guard: check version */
	if (msg[0] != NDB_NEGENTROPY_PROTOCOL_V1)
		return 0;

	/* Write version byte to output */
	out[0] = NDB_NEGENTROPY_PROTOCOL_V1;
	out_offset = 1;

	/* Process each incoming range */
	p = msg + 1;
	remaining = msglen - 1;

	while (remaining > 0) {
		/* Decode next range */
		consumed = ndb_negentropy_range_decode(p, remaining, &in_range, &prev_ts_in);
		if (consumed == 0)
			return 0;

		p += consumed;
		remaining -= (size_t)consumed;

		/* Find the upper index for this range */
		size_t upper_idx = ndb_negentropy_storage_lower_bound(
			neg->storage, &in_range.upper_bound);

		/* Number of items in our [lower, upper) range */
		size_t our_count = (upper_idx > lower_idx) ? (upper_idx - lower_idx) : 0;

		/* Process based on mode */
		switch (in_range.mode) {

		case NDB_NEG_SKIP: {
			/*
			 * Peer is skipping this range (they agree it matches).
			 * We echo SKIP to maintain coverage (unless all input is SKIP,
			 * in which case we'll send empty message at the end).
			 */
			struct ndb_negentropy_range out_range;
			int written;

			out_range.upper_bound = in_range.upper_bound;
			out_range.mode = NDB_NEG_SKIP;

			written = ndb_negentropy_range_encode(
				out + out_offset, *outlen - out_offset,
				&out_range, &prev_ts_out);
			if (written == 0)
				return 0;

			out_offset += (size_t)written;
			break;
		}

		case NDB_NEG_FINGERPRINT: {
			/*
			 * Compare fingerprints. If they match, respond with SKIP.
			 * If different, split the range.
			 */
			unsigned char our_fp[16];
			received_non_skip = 1;

			ndb_negentropy_storage_fingerprint(neg->storage,
			                                    lower_idx, upper_idx, our_fp);

			if (memcmp(our_fp, in_range.payload.fingerprint, 16) == 0) {
				/* Fingerprints match - respond with SKIP */
				struct ndb_negentropy_range out_range;
				int written;

				out_range.upper_bound = in_range.upper_bound;
				out_range.mode = NDB_NEG_SKIP;

				written = ndb_negentropy_range_encode(
					out + out_offset, *outlen - out_offset,
					&out_range, &prev_ts_out);
				if (written == 0)
					return 0;

				out_offset += (size_t)written;
			} else {
				/*
				 * Fingerprints differ - need to split.
				 * For small ranges, send IdList.
				 * For large ranges, send multiple Fingerprint sub-ranges.
				 */
				if (our_count <= (size_t)neg->idlist_threshold) {
					/* Small range: send IdList */
					struct ndb_negentropy_range out_range;
					int written;
					unsigned char *id_buf = NULL;

					out_range.upper_bound = in_range.upper_bound;
					out_range.mode = NDB_NEG_IDLIST;
					out_range.payload.id_list.id_count = our_count;

					/*
					 * Must copy IDs to contiguous buffer because
					 * storage items have timestamps interleaved.
					 */
					if (our_count > 0) {
						size_t i;
						id_buf = malloc(our_count * 32);
						if (id_buf == NULL)
							return 0;

						for (i = 0; i < our_count; i++) {
							memcpy(id_buf + i * 32,
							       neg->storage->items[lower_idx + i].id,
							       32);
						}
						out_range.payload.id_list.ids = id_buf;
					} else {
						out_range.payload.id_list.ids = NULL;
					}

					written = ndb_negentropy_range_encode(
						out + out_offset, *outlen - out_offset,
						&out_range, &prev_ts_out);

					free(id_buf);

					if (written == 0)
						return 0;

					out_offset += (size_t)written;
				} else {
					/*
					 * Large range: split into sub-ranges with fingerprints.
					 * Use configured split_count splits.
					 */
					size_t items_per_split = our_count / (size_t)neg->split_count;
					if (items_per_split == 0)
						items_per_split = 1;

					size_t split_lower = lower_idx;
					int split_count = neg->split_count;

					for (int s = 0; s < split_count && split_lower < upper_idx; s++) {
						size_t split_upper;
						struct ndb_negentropy_range out_range;
						int written;

						if (s == split_count - 1) {
							/* Last split takes the rest */
							split_upper = upper_idx;
						} else {
							split_upper = split_lower + items_per_split;
							if (split_upper > upper_idx)
								split_upper = upper_idx;
						}

						/* Create fingerprint for this split */
						bound_from_index(neg->storage, split_upper,
						                 &out_range.upper_bound);

						/* Use the incoming upper bound for the last split */
						if (split_upper == upper_idx)
							out_range.upper_bound = in_range.upper_bound;

						out_range.mode = NDB_NEG_FINGERPRINT;
						ndb_negentropy_storage_fingerprint(
							neg->storage, split_lower, split_upper,
							out_range.payload.fingerprint);

						written = ndb_negentropy_range_encode(
							out + out_offset, *outlen - out_offset,
							&out_range, &prev_ts_out);
						if (written == 0)
							return 0;

						out_offset += (size_t)written;
						split_lower = split_upper;
					}
				}
			}
			break;
		}

		case NDB_NEG_IDLIST: {
			/*
			 * Remote sent us their full ID list for this range.
			 * Per NIP-77, we respond with SKIP (range is resolved).
			 *
			 * We track:
			 * - have_ids: IDs we have that they don't (we should send)
			 * - need_ids: IDs they have that we don't (we should request)
			 */
			struct ndb_negentropy_range out_range;
			int written;
			size_t their_count = in_range.payload.id_list.id_count;
			const unsigned char *their_ids = in_range.payload.id_list.ids;
			size_t i, j;

			received_non_skip = 1;

			/* Find IDs we have that they don't -> have_ids */
			for (i = lower_idx; i < upper_idx; i++) {
				const struct ndb_negentropy_item *item = &neg->storage->items[i];
				int found = 0;

				/* Check if they have this ID */
				for (j = 0; j < their_count; j++) {
					if (memcmp(item->id, their_ids + j * 32, 32) == 0) {
						found = 1;
						break;
					}
				}

				if (!found) {
					/* We have it, they don't */
					ids_add(&neg->have_ids, item->id);
				}
			}

			/* Find IDs they have that we don't -> need_ids */
			for (j = 0; j < their_count; j++) {
				const unsigned char *their_id = their_ids + j * 32;
				int we_have = 0;

				/* Check if we have this ID */
				for (i = lower_idx; i < upper_idx; i++) {
					if (memcmp(neg->storage->items[i].id, their_id, 32) == 0) {
						we_have = 1;
						break;
					}
				}

				if (!we_have) {
					/* We need this ID */
					ids_add(&neg->need_ids, their_id);
				}
			}

			/* Respond with SKIP per NIP-77 (range resolved) */
			out_range.upper_bound = in_range.upper_bound;
			out_range.mode = NDB_NEG_SKIP;

			written = ndb_negentropy_range_encode(
				out + out_offset, *outlen - out_offset,
				&out_range, &prev_ts_out);
			if (written == 0)
				return 0;

			out_offset += (size_t)written;
			break;
		}

		case NDB_NEG_IDLIST_RESPONSE: {
			/*
			 * NOTE: Mode 3 (IDLIST_RESPONSE) is NOT in NIP-77.
			 * It's from hoytech's negentropy reference implementation.
			 * We accept it for compatibility but don't send it.
			 *
			 * Remote responded to our IdList with:
			 * - IDs they have that we don't (have_ids)
			 * - Bitfield of our IDs they need
			 *
			 * Extract the have/need IDs.
			 */
			size_t have_count = in_range.payload.id_list_response.have_count;
			received_non_skip = 1;
			const unsigned char *have_ids = in_range.payload.id_list_response.have_ids;
			size_t bf_len = in_range.payload.id_list_response.bitfield_len;
			const unsigned char *bitfield = in_range.payload.id_list_response.bitfield;

			/* IDs they have that we need */
			for (size_t i = 0; i < have_count; i++) {
				ids_add(&neg->need_ids, have_ids + i * 32);
			}

			/* IDs we have that they need (from bitfield) */
			/* We need to match against our original IdList... */
			/* For now, we iterate our items and check the bitfield */
			size_t bit_idx = 0;
			for (size_t i = lower_idx; i < upper_idx && bit_idx / 8 < bf_len; i++) {
				if (bitfield[bit_idx / 8] & (1 << (bit_idx % 8))) {
					ids_add(&neg->have_ids, neg->storage->items[i].id);
				}
				bit_idx++;
			}

			/* No response needed for IdListResponse - send SKIP */
			struct ndb_negentropy_range out_range;
			int written;

			out_range.upper_bound = in_range.upper_bound;
			out_range.mode = NDB_NEG_SKIP;

			written = ndb_negentropy_range_encode(
				out + out_offset, *outlen - out_offset,
				&out_range, &prev_ts_out);
			if (written == 0)
				return 0;

			out_offset += (size_t)written;
			break;
		}

		default:
			return 0;
		}

		/* Move to next range */
		lower_idx = upper_idx;
	}

	/*
	 * If all incoming ranges were SKIP, we can signal completion
	 * by returning just the version byte (empty message).
	 * This prevents infinite SKIP echo loops.
	 */
	if (!received_non_skip)
		out_offset = 1;

	*outlen = out_offset;

	/*
	 * Mark reconciliation as complete if output is just the version byte.
	 * This happens when all ranges in the response are SKIP mode,
	 * meaning there are no differences to resolve.
	 */
	if (out_offset == 1)
		neg->is_complete = 1;

	return 1;
}


size_t ndb_negentropy_get_have_ids(const struct ndb_negentropy *neg,
                                    const unsigned char **ids_out)
{
	if (neg == NULL || ids_out == NULL)
		return 0;

	*ids_out = neg->have_ids.ids;
	return neg->have_ids.count;
}


size_t ndb_negentropy_get_need_ids(const struct ndb_negentropy *neg,
                                    const unsigned char **ids_out)
{
	if (neg == NULL || ids_out == NULL)
		return 0;

	*ids_out = neg->need_ids.ids;
	return neg->need_ids.count;
}
