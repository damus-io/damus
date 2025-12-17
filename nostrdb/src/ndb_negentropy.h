/*
 * ndb_negentropy.h - Native Negentropy for NostrDB
 *
 * This implements the negentropy set reconciliation protocol (NIP-77)
 * for efficient event syncing between clients and relays.
 *
 * Negentropy allows two parties to efficiently determine which items
 * each has that the other lacks, using O(log n) round trips and
 * minimal bandwidth via fingerprint comparison.
 *
 * The protocol works by:
 * 1. Both sides sort their items by (timestamp, id)
 * 2. Exchange fingerprints of ranges to find differences
 * 3. Recursively split differing ranges until items are identified
 * 4. Exchange the actual differing item IDs
 *
 * Reference: https://github.com/hoytech/negentropy
 * NIP-77: https://github.com/nostr-protocol/nips/blob/master/77.md
 */

#ifndef NDB_NEGENTROPY_H
#define NDB_NEGENTROPY_H

#include <inttypes.h>
#include <stddef.h>

/* Forward declarations for NostrDB integration */
struct ndb_txn;
struct ndb_filter;

/*
 * Protocol version byte.
 * V1 = 0x61, future versions increment (0x62, 0x63, etc.)
 * If a peer receives an incompatible version, it replies with
 * a single byte containing its highest supported version.
 */
#define NDB_NEGENTROPY_PROTOCOL_V1 0x61

/*
 * Range modes determine how each range in a message should be processed.
 *
 * SKIP:            No further processing needed for this range.
 *                  Payload is empty.
 *
 * FINGERPRINT:     Payload contains a 16-byte fingerprint of all IDs
 *                  in this range. If fingerprints match, ranges are
 *                  identical. If not, further splitting is needed.
 *
 * IDLIST:          Payload contains a complete list of all IDs in
 *                  this range. Used for small ranges as a base case.
 *
 * IDLIST_RESPONSE: Server's response to an IDLIST. Contains IDs the
 *                  server has (client needs) plus a bitfield indicating
 *                  which client IDs the server needs.
 */
enum ndb_negentropy_mode {
	NDB_NEG_SKIP            = 0,
	NDB_NEG_FINGERPRINT     = 1,
	NDB_NEG_IDLIST          = 2,
	NDB_NEG_IDLIST_RESPONSE = 3
};

/*
 * Bound: Represents a range boundary in the timestamp/ID space.
 *
 * Ranges in negentropy are specified by inclusive lower bounds and
 * exclusive upper bounds. Each bound consists of a timestamp and
 * an ID prefix of variable length.
 *
 * The prefix_len allows using the shortest possible prefix that
 * distinguishes this bound from adjacent records. If timestamps
 * differ, prefix_len can be 0. Otherwise, it's the length of the
 * common prefix plus 1.
 *
 * Trailing bytes after prefix_len are implicitly zero.
 */
struct ndb_negentropy_bound {
	uint64_t timestamp;
	unsigned char id_prefix[32];
	uint8_t prefix_len;  /* 0-32 bytes */
};

/*
 * Item: A (timestamp, id) pair for negentropy reconciliation.
 *
 * Items must be sorted by timestamp first, then lexicographically
 * by ID for items with identical timestamps.
 */
struct ndb_negentropy_item {
	uint64_t timestamp;
	unsigned char id[32];
};

/*
 * Accumulator: 256-bit accumulator for fingerprint computation.
 *
 * The fingerprint algorithm sums all 32-byte IDs (treated as
 * little-endian 256-bit unsigned integers) modulo 2^256, then
 * hashes the result with the count.
 *
 * Formula: fingerprint = SHA256(sum || varint(count))[:16]
 */
struct ndb_negentropy_accumulator {
	unsigned char sum[32];  /* little-endian 256-bit value */
};


/* ============================================================
 * VARINT ENCODING/DECODING
 * ============================================================
 *
 * Negentropy uses a specific varint format:
 * - Base-128 encoding
 * - Most significant byte FIRST (big-endian style)
 * - High bit (0x80) set on all bytes EXCEPT the last
 *
 * This differs from the common LEB128 format which is LSB-first.
 *
 * Examples:
 *   0      -> 0x00
 *   127    -> 0x7F
 *   128    -> 0x81 0x00
 *   255    -> 0x81 0x7F
 *   16383  -> 0xFF 0x7F
 *   16384  -> 0x81 0x80 0x00
 */

/*
 * Encode a 64-bit unsigned integer as a negentropy varint.
 *
 * Returns: Number of bytes written, or 0 if buffer too small.
 *
 * The maximum encoded size is 10 bytes (for UINT64_MAX).
 */
int ndb_negentropy_varint_encode(unsigned char *buf, size_t buflen, uint64_t n);

/*
 * Decode a negentropy varint into a 64-bit unsigned integer.
 *
 * Returns: Number of bytes consumed, or 0 on error.
 *
 * Errors include: buffer too small, malformed varint (> 10 bytes),
 * or value overflow.
 */
int ndb_negentropy_varint_decode(const unsigned char *buf, size_t buflen,
                                  uint64_t *out);

/*
 * Calculate the encoded size of a varint without actually encoding.
 *
 * Useful for pre-calculating buffer sizes.
 */
int ndb_negentropy_varint_size(uint64_t n);


/* ============================================================
 * FINGERPRINT COMPUTATION
 * ============================================================
 *
 * Fingerprints are computed by:
 * 1. Summing all 32-byte IDs as little-endian 256-bit integers
 * 2. Taking the sum modulo 2^256 (natural overflow)
 * 3. Appending the count as a varint
 * 4. Hashing with SHA-256
 * 5. Taking the first 16 bytes
 */

/*
 * Initialize an accumulator to zero.
 */
void ndb_negentropy_accumulator_init(struct ndb_negentropy_accumulator *acc);

/*
 * Add a 32-byte ID to the accumulator.
 *
 * Performs 256-bit addition with natural overflow (mod 2^256).
 * The ID is interpreted as a little-endian unsigned integer.
 */
void ndb_negentropy_accumulator_add(struct ndb_negentropy_accumulator *acc,
                                     const unsigned char *id);

/*
 * Compute the final 16-byte fingerprint.
 *
 * Formula: SHA256(acc->sum || varint(count))[:16]
 *
 * The output buffer must be at least 16 bytes.
 */
void ndb_negentropy_fingerprint(const struct ndb_negentropy_accumulator *acc,
                                 size_t count,
                                 unsigned char *out);


/* ============================================================
 * BOUND ENCODING/DECODING
 * ============================================================
 *
 * Bounds are encoded as:
 *   <encodedTimestamp (Varint)> <prefixLen (Varint)> <idPrefix (bytes)>
 *
 * Timestamp encoding is special:
 * - The "infinity" timestamp (UINT64_MAX) is encoded as 0
 * - All other values are encoded as (1 + delta) where delta is
 *   the difference from the previous timestamp
 * - Deltas are always non-negative (ranges are ascending)
 *
 * The prev_timestamp parameter tracks state across multiple
 * bound encodings within a single message.
 */

/*
 * Encode a bound into a buffer.
 *
 * prev_timestamp: In/out parameter for delta encoding.
 *                 Initialize to 0 at the start of a message.
 *
 * Returns: Number of bytes written, or 0 on error.
 */
int ndb_negentropy_bound_encode(unsigned char *buf, size_t buflen,
                                 const struct ndb_negentropy_bound *bound,
                                 uint64_t *prev_timestamp);

/*
 * Decode a bound from a buffer.
 *
 * prev_timestamp: In/out parameter for delta decoding.
 *                 Initialize to 0 at the start of a message.
 *
 * Returns: Number of bytes consumed, or 0 on error.
 */
int ndb_negentropy_bound_decode(const unsigned char *buf, size_t buflen,
                                 struct ndb_negentropy_bound *bound,
                                 uint64_t *prev_timestamp);


/* ============================================================
 * HEX ENCODING UTILITIES
 * ============================================================
 *
 * NIP-77 transmits negentropy messages as hex-encoded strings
 * within JSON arrays:
 *
 *   ["NEG-OPEN", "sub1", {"kinds":[1]}, "6181..."]
 *   ["NEG-MSG", "sub1", "6181..."]
 */

/*
 * Convert binary data to a hex string.
 *
 * The output is NUL-terminated. The hex buffer must be at least
 * (len * 2 + 1) bytes.
 *
 * Returns: Number of hex characters written (excluding NUL).
 */
size_t ndb_negentropy_to_hex(const unsigned char *bin, size_t len, char *hex);

/*
 * Convert a hex string to binary data.
 *
 * Returns: Number of bytes written, or 0 on error (invalid hex,
 *          buffer too small, odd-length input).
 */
size_t ndb_negentropy_from_hex(const char *hex, size_t hexlen,
                                unsigned char *bin, size_t binlen);


/* ============================================================
 * RANGE ENCODING/DECODING
 * ============================================================
 *
 * A Range represents a contiguous section of the timestamp/ID space
 * with associated data for reconciliation.
 *
 * Wire format:
 *   <upperBound (Bound)> <mode (Varint)> <payload>
 *
 * The lower bound is implicit - it's the upper bound of the previous
 * range (or 0/0 for the first range).
 *
 * Payload format depends on mode:
 *   SKIP:            (empty)
 *   FINGERPRINT:     16 bytes
 *   IDLIST:          <count (Varint)> <id (32 bytes)>*
 *   IDLIST_RESPONSE: <haveIds (IdList)> <bitfieldLen (Varint)> <bitfield>
 */

/*
 * Range structure with payload data.
 *
 * For IDLIST and IDLIST_RESPONSE modes, the caller is responsible
 * for allocating and freeing the id arrays. The encode/decode
 * functions work with raw buffers; higher-level wrappers should
 * manage memory.
 */
struct ndb_negentropy_range {
	struct ndb_negentropy_bound upper_bound;
	enum ndb_negentropy_mode mode;

	/*
	 * Payload data (interpretation depends on mode):
	 * - SKIP: unused
	 * - FINGERPRINT: fingerprint[16] contains the fingerprint
	 * - IDLIST: ids points to (id_count * 32) bytes of IDs
	 * - IDLIST_RESPONSE: have_ids + bitfield for client IDs
	 */
	union {
		unsigned char fingerprint[16];

		struct {
			size_t id_count;
			const unsigned char *ids;  /* id_count * 32 bytes */
		} id_list;

		struct {
			size_t have_count;
			const unsigned char *have_ids;  /* have_count * 32 bytes */
			size_t bitfield_len;
			const unsigned char *bitfield;
		} id_list_response;
	} payload;
};

/*
 * Encode a range into a buffer.
 *
 * prev_timestamp: In/out parameter for bound delta encoding.
 *
 * For IDLIST mode, payload.id_list.ids must point to valid ID data.
 * For IDLIST_RESPONSE mode, both have_ids and bitfield must be valid.
 *
 * Returns: Number of bytes written, or 0 on error.
 */
int ndb_negentropy_range_encode(unsigned char *buf, size_t buflen,
                                 const struct ndb_negentropy_range *range,
                                 uint64_t *prev_timestamp);

/*
 * Decode a range from a buffer.
 *
 * prev_timestamp: In/out parameter for bound delta decoding.
 *
 * For IDLIST and IDLIST_RESPONSE modes, the payload pointers will
 * point directly into the input buffer (zero-copy). The caller must
 * ensure the buffer remains valid while using the range data.
 *
 * Returns: Number of bytes consumed, or 0 on error.
 */
int ndb_negentropy_range_decode(const unsigned char *buf, size_t buflen,
                                 struct ndb_negentropy_range *range,
                                 uint64_t *prev_timestamp);


/* ============================================================
 * MESSAGE ENCODING/DECODING
 * ============================================================
 *
 * A negentropy message is the complete unit transmitted over the wire.
 * It contains a version byte followed by zero or more ranges.
 *
 * Wire format:
 *   <version (1 byte)> <range>*
 *
 * The version byte is 0x61 for protocol V1.
 *
 * Messages are hex-encoded for transmission in NIP-77 JSON arrays:
 *   ["NEG-OPEN", "subId", {filter}, "<hex-encoded message>"]
 *   ["NEG-MSG", "subId", "<hex-encoded message>"]
 *
 * Note on range limits: The protocol doesn't impose a maximum number
 * of ranges, but implementations typically limit them for DOS protection.
 * A reasonable limit is 128-256 ranges per message.
 */

/*
 * Maximum ranges per message for DOS protection.
 * This can be adjusted based on deployment requirements.
 * Note: relay.damus.io can send 500KB+ messages with many ranges,
 * so we use a higher limit than typical implementations.
 */
#define NDB_NEGENTROPY_MAX_RANGES 8192

/*
 * Maximum IDs per IDLIST range for DOS protection.
 * Prevents overflow when computing id_count * 32.
 * 100,000 IDs = 3.2MB per range, which is generous.
 */
#define NDB_NEGENTROPY_MAX_IDS_PER_RANGE 100000

/*
 * Encode a complete negentropy message.
 *
 * The message starts with the protocol version byte (NDB_NEGENTROPY_PROTOCOL_V1)
 * followed by the encoded ranges.
 *
 * Parameters:
 *   buf:        Output buffer for the encoded message
 *   buflen:     Size of the output buffer
 *   ranges:     Array of ranges to encode
 *   num_ranges: Number of ranges in the array
 *
 * Returns: Total bytes written, or 0 on error.
 *
 * Note: The timestamp delta encoding is reset for each message. The
 * first range uses absolute timestamp encoding (delta from 0).
 */
int ndb_negentropy_message_encode(unsigned char *buf, size_t buflen,
                                   const struct ndb_negentropy_range *ranges,
                                   size_t num_ranges);

/*
 * Get the protocol version from a message.
 *
 * This reads just the first byte without parsing the full message.
 * Returns the version byte, or 0 if the buffer is empty.
 *
 * Use this to check version compatibility before full decode.
 */
int ndb_negentropy_message_version(const unsigned char *buf, size_t buflen);

/*
 * Decode the next range from a message buffer.
 *
 * This is an incremental decoder for processing ranges one at a time.
 * It avoids allocating memory for an array of ranges.
 *
 * Parameters:
 *   buf:            Input buffer (should point past version byte for first call)
 *   buflen:         Remaining bytes in buffer
 *   range:          Output range structure
 *   prev_timestamp: In/out state for delta decoding (init to 0)
 *
 * Returns: Bytes consumed for this range, or 0 if no more ranges/error.
 *
 * Usage pattern:
 *   const unsigned char *p = buf + 1;  // skip version
 *   size_t remaining = len - 1;
 *   uint64_t prev_ts = 0;
 *   struct ndb_negentropy_range range;
 *
 *   while (remaining > 0) {
 *       int consumed = ndb_negentropy_range_decode(p, remaining, &range, &prev_ts);
 *       if (consumed == 0) break;
 *       // process range...
 *       p += consumed;
 *       remaining -= consumed;
 *   }
 */

/*
 * Count the number of ranges in a message.
 *
 * This parses through the message to count ranges without
 * extracting the full data. Useful for pre-allocating arrays
 * or validating message structure.
 *
 * Returns: Number of ranges, or -1 on parse error.
 */
int ndb_negentropy_message_count_ranges(const unsigned char *buf, size_t buflen);


/* ============================================================
 * NEGENTROPY STORAGE
 * ============================================================
 *
 * Storage holds a sorted list of items for negentropy reconciliation.
 * Items are (timestamp, id) pairs sorted first by timestamp, then by id.
 *
 * The storage can be populated from a NostrDB query or built manually.
 * Once sealed, the storage is ready for reconciliation.
 *
 * Memory management: The storage owns its item array and will free it
 * when destroyed. Items are copied in, so the caller can free their
 * original data after adding.
 */

/*
 * Storage structure for negentropy items.
 *
 * Items must be sorted by (timestamp, id) before sealing.
 * The seal operation handles sorting automatically.
 */
struct ndb_negentropy_storage {
	struct ndb_negentropy_item *items;  /* Sorted item array */
	size_t count;                        /* Number of items */
	size_t capacity;                     /* Allocated capacity */
	int sealed;                          /* 1 if sealed (ready for use) */
};

/*
 * Initialize a new storage instance.
 *
 * Must be destroyed with ndb_negentropy_storage_destroy() when done.
 * Returns 1 on success, 0 on failure (allocation error).
 */
int ndb_negentropy_storage_init(struct ndb_negentropy_storage *storage);

/*
 * Destroy a storage instance and free its memory.
 */
void ndb_negentropy_storage_destroy(struct ndb_negentropy_storage *storage);

/*
 * Add an item to the storage.
 *
 * Items can be added in any order - they will be sorted when sealed.
 * Must not call after sealing.
 *
 * Returns 1 on success, 0 on failure (allocation error or already sealed).
 */
int ndb_negentropy_storage_add(struct ndb_negentropy_storage *storage,
                                uint64_t timestamp,
                                const unsigned char *id);

/*
 * Add multiple items at once.
 *
 * More efficient than adding one at a time due to reduced reallocation.
 * The items array should contain count items.
 *
 * Returns 1 on success, 0 on failure.
 */
int ndb_negentropy_storage_add_many(struct ndb_negentropy_storage *storage,
                                     const struct ndb_negentropy_item *items,
                                     size_t count);

/*
 * Seal the storage for use.
 *
 * This sorts the items by (timestamp, id) and marks the storage as ready.
 * After sealing:
 * - No more items can be added
 * - The storage can be used for fingerprint computation
 *
 * Returns 1 on success, 0 if already sealed.
 */
int ndb_negentropy_storage_seal(struct ndb_negentropy_storage *storage);

/*
 * Get the number of items in the storage.
 */
size_t ndb_negentropy_storage_size(const struct ndb_negentropy_storage *storage);

/*
 * Get an item by index.
 *
 * Index must be < size(). Returns NULL if out of bounds or not sealed.
 */
const struct ndb_negentropy_item *
ndb_negentropy_storage_get(const struct ndb_negentropy_storage *storage, size_t index);

/*
 * Find the index of the first item >= the given bound.
 *
 * Uses binary search for O(log n) performance.
 * Returns the insertion point if no exact match (i.e., the index where
 * an item with this bound would be inserted).
 *
 * Storage must be sealed.
 */
size_t ndb_negentropy_storage_lower_bound(const struct ndb_negentropy_storage *storage,
                                           const struct ndb_negentropy_bound *bound);

/*
 * Compute the fingerprint for a range of items.
 *
 * Computes the fingerprint for items in [begin, end).
 * The begin and end are indices into the storage.
 *
 * Storage must be sealed.
 * Returns 1 on success, 0 on error (invalid indices or not sealed).
 */
int ndb_negentropy_storage_fingerprint(const struct ndb_negentropy_storage *storage,
                                        size_t begin, size_t end,
                                        unsigned char *fingerprint_out);


/* ============================================================
 * FILTER-BASED INITIALIZATION (NostrDB Integration)
 * ============================================================
 *
 * These functions integrate negentropy with NostrDB's query system,
 * allowing storage to be populated directly from a NIP-01 filter
 * rather than manually adding items.
 */

/*
 * Populate storage from a NostrDB filter query.
 *
 * This queries the database using the provided filter and adds all
 * matching events to the storage. The storage should be initialized
 * but not sealed before calling this function.
 *
 * After this function returns successfully, the storage is automatically
 * sealed and ready for use.
 *
 * Parameters:
 *   storage:  Initialized (but not sealed) storage
 *   txn:      Active read transaction
 *   filter:   NIP-01 filter to query events
 *   limit:    Maximum number of events to add (0 = use filter's limit or 10000)
 *
 * Returns: Number of items added, or -1 on error.
 *
 * Note: The transaction must remain valid for the lifetime of the storage
 * since we only store references to the event data.
 */
int ndb_negentropy_storage_from_filter(struct ndb_negentropy_storage *storage,
                                        struct ndb_txn *txn,
                                        struct ndb_filter *filter,
                                        int limit);


/* ============================================================
 * RECONCILIATION STATE MACHINE
 * ============================================================
 *
 * The reconciliation engine processes negentropy messages and
 * determines which items each side has that the other lacks.
 *
 * Protocol flow:
 * 1. Client calls initiate() to create initial message
 * 2. Server processes with reconcile(), sends reply
 * 3. Client calls reconcile() on reply, extracts have/need IDs
 * 4. Repeat until reconcile() returns empty message (sync complete)
 *
 * The engine is agnostic to client/server roles - both sides use
 * the same API. The difference is who calls initiate() first.
 */

/*
 * Threshold for switching from IdList to Fingerprint mode.
 * Ranges smaller than this send full IdLists (base case).
 * Larger ranges send Fingerprints for sub-ranges.
 */
#define NDB_NEGENTROPY_IDLIST_THRESHOLD 16

/*
 * Number of sub-ranges to split into when fingerprints differ.
 * Must be > 1 to ensure progress.
 */
#define NDB_NEGENTROPY_SPLIT_COUNT 16

/*
 * ID output array for have/need tracking.
 *
 * During reconciliation, IDs are accumulated into these arrays.
 * The arrays are dynamically grown as needed.
 */
struct ndb_negentropy_ids {
	unsigned char *ids;   /* Array of 32-byte IDs */
	size_t count;         /* Number of IDs */
	size_t capacity;      /* Allocated capacity (in IDs, not bytes) */
};

/*
 * Configuration for negentropy reconciliation.
 *
 * Pass NULL to use defaults. All fields are optional - zero values
 * use sensible defaults.
 */
struct ndb_negentropy_config {
	/*
	 * Maximum frame/message size in bytes. 0 = unlimited.
	 * Useful for constraining message sizes on memory-limited devices.
	 */
	int frame_size_limit;

	/*
	 * Threshold for switching between fingerprint and idlist modes.
	 * Ranges with fewer items than this send full ID lists.
	 * Default: NDB_NEGENTROPY_IDLIST_THRESHOLD (16)
	 */
	int idlist_threshold;

	/*
	 * Number of sub-ranges to split into when fingerprints differ.
	 * Must be > 1 to ensure progress.
	 * Default: NDB_NEGENTROPY_SPLIT_COUNT (16)
	 */
	int split_count;
};

/*
 * Reconciliation context.
 *
 * Holds the storage reference and tracks state across multiple
 * reconcile() calls. Also accumulates have/need IDs.
 */
struct ndb_negentropy {
	const struct ndb_negentropy_storage *storage;  /* Item storage (not owned) */
	int is_initiator;                               /* 1 if we initiated */
	int is_complete;                                /* 1 when reconciliation done */

	/* Configuration (copied from init) */
	int frame_size_limit;
	int idlist_threshold;
	int split_count;

	/* IDs we have that remote needs (to send) */
	struct ndb_negentropy_ids have_ids;

	/* IDs remote has that we need (to request) */
	struct ndb_negentropy_ids need_ids;
};

/*
 * Initialize a negentropy reconciliation context.
 *
 * The storage must be sealed and remain valid for the lifetime
 * of the context. The context does not own the storage.
 *
 * The config parameter is optional - pass NULL to use defaults.
 * If provided, the config is copied so it doesn't need to remain valid.
 *
 * Returns 1 on success, 0 on failure.
 */
int ndb_negentropy_init(struct ndb_negentropy *neg,
                         const struct ndb_negentropy_storage *storage,
                         const struct ndb_negentropy_config *config);

/*
 * Destroy a negentropy context and free resources.
 */
void ndb_negentropy_destroy(struct ndb_negentropy *neg);

/*
 * Create the initial message to start reconciliation.
 *
 * This creates a single FINGERPRINT range covering the entire
 * item space (from timestamp 0 to infinity).
 *
 * Parameters:
 *   neg:     Initialized context
 *   buf:     Output buffer for the encoded message
 *   buflen:  Size of output buffer
 *   outlen:  Receives the actual message length
 *
 * Returns 1 on success, 0 on failure.
 */
int ndb_negentropy_initiate(struct ndb_negentropy *neg,
                             unsigned char *buf, size_t buflen,
                             size_t *outlen);

/*
 * Process an incoming message and generate a response.
 *
 * This is the core reconciliation function. It:
 * 1. Parses the incoming message
 * 2. Compares fingerprints and splits differing ranges
 * 3. Processes IdLists and IdListResponses
 * 4. Accumulates have/need IDs
 * 5. Generates a response message
 *
 * Parameters:
 *   neg:          Initialized context
 *   msg:          Incoming message (binary, not hex)
 *   msglen:       Length of incoming message
 *   out:          Output buffer for response message
 *   outlen:       In: buffer size, Out: response length
 *
 * Returns:
 *   1  - Success, response generated (check outlen > 1 for more rounds)
 *   0  - Error (parse error, invalid message, etc.)
 *
 * When outlen == 1 on return (just version byte), reconciliation
 * is complete - no more messages needed.
 */
int ndb_negentropy_reconcile(struct ndb_negentropy *neg,
                              const unsigned char *msg, size_t msglen,
                              unsigned char *out, size_t *outlen);

/*
 * Check if reconciliation is complete.
 *
 * Returns 1 if reconciliation is done (no more rounds needed),
 * 0 if more rounds are required.
 *
 * Reconciliation is complete when reconcile() returns an empty
 * response (just version byte, length == 1).
 */
int ndb_negentropy_is_complete(const struct ndb_negentropy *neg);

/*
 * Get the IDs we have that the remote needs.
 *
 * These are IDs we should send to the remote.
 * The returned array remains valid until the context is destroyed
 * or the next reconcile() call.
 *
 * Returns the number of IDs. ids_out receives pointer to the array.
 */
size_t ndb_negentropy_get_have_ids(const struct ndb_negentropy *neg,
                                    const unsigned char **ids_out);

/*
 * Get the IDs the remote has that we need.
 *
 * These are IDs we should request from the remote.
 * The returned array remains valid until the context is destroyed
 * or the next reconcile() call.
 *
 * Returns the number of IDs. ids_out receives pointer to the array.
 */
size_t ndb_negentropy_get_need_ids(const struct ndb_negentropy *neg,
                                    const unsigned char **ids_out);


#endif /* NDB_NEGENTROPY_H */
