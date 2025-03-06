#ifndef NOSTRDB_H
#define NOSTRDB_H

#include <inttypes.h>
#include "win.h"
#include "cursor.h"

// maximum number of filters allowed in a filter group
#define NDB_PACKED_STR     0x1
#define NDB_PACKED_ID      0x2

#define NDB_FLAG_NOMIGRATE        (1 << 0)
#define NDB_FLAG_SKIP_NOTE_VERIFY (1 << 1)
#define NDB_FLAG_NO_FULLTEXT      (1 << 2)
#define NDB_FLAG_NO_NOTE_BLOCKS   (1 << 3)
#define NDB_FLAG_NO_STATS         (1 << 4)

//#define DEBUG 1

#ifdef NDB_LOG
#define ndb_debug(...) printf(__VA_ARGS__)
#else
#define ndb_debug(...) (void)0
#endif

#include "str_block.h"

struct ndb_json_parser;
struct ndb;
struct ndb_blocks;
struct ndb_block;
struct ndb_note;
struct ndb_tag;
struct ndb_tags;
struct ndb_lmdb;
union ndb_packed_str;
struct bolt11;

// some bindings like swift needs help with forward declared pointers
struct ndb_tag_ptr { struct ndb_tag *ptr; };
struct ndb_tags_ptr { struct ndb_tags *ptr; };
struct ndb_block_ptr { struct ndb_block *ptr; };
struct ndb_blocks_ptr { struct ndb_blocks *ptr; };
struct ndb_note_ptr { struct ndb_note *ptr; };

struct ndb_t {
	struct ndb *ndb;
};

struct ndb_str {
	unsigned char flag;
	union {
		const char *str;
		unsigned char *id;
	};
};

struct ndb_keypair {
	unsigned char pubkey[32];
	unsigned char secret[32];
	
	// this corresponds to secp256k1's keypair type. it's guaranteed to
	// be 96 bytes according to their docs. I don't want to depend on
	// the secp256k1 header here so we just use raw bytes.
	unsigned char pair[96];
};

// function pointer for controlling what to do after we parse an id
typedef enum ndb_idres (*ndb_id_fn)(void *, const char *);

// callback function for when we receive new subscription results
typedef void (*ndb_sub_fn)(void *, uint64_t subid);

// id callback + closure data
struct ndb_id_cb {
	ndb_id_fn fn;
	void *data;
};

// required to keep a read 
struct ndb_txn {
	struct ndb_lmdb *lmdb;
	void *mdb_txn;
};

struct ndb_event {
	struct ndb_note *note;
};

struct ndb_command_result {
	int ok;
	const char *msg;
	int msglen;
};

// From-client event types
enum fce_type {
	NDB_FCE_EVENT = 0x1
};

// To-client event types
enum tce_type {
	NDB_TCE_EVENT  = 0x1,
	NDB_TCE_OK     = 0x2,
	NDB_TCE_NOTICE = 0x3,
	NDB_TCE_EOSE   = 0x4,
	NDB_TCE_AUTH   = 0x5,
};

enum ndb_ingest_filter_action {
	NDB_INGEST_REJECT,
	NDB_INGEST_ACCEPT,
	NDB_INGEST_SKIP_VALIDATION
};

struct ndb_search_key
{
	char search[24];
	unsigned char id[32];
	uint64_t timestamp;
};

struct ndb_search {
	struct ndb_search_key *key;
	uint64_t profile_key;
	void *cursor; // MDB_cursor *
};

// From-client event
struct ndb_fce {
	enum fce_type evtype;
	union {
		struct ndb_event event;
	};
};

// To-client event
struct ndb_tce {
	enum tce_type evtype;
	const char *subid;
	int subid_len;

	union {
		struct ndb_event event;
		struct ndb_command_result command_result;
	};
};

typedef enum ndb_ingest_filter_action (*ndb_ingest_filter_fn)(void *, struct ndb_note *);

enum ndb_filter_fieldtype {
	NDB_FILTER_IDS     = 1,
	NDB_FILTER_AUTHORS = 2,
	NDB_FILTER_KINDS   = 3,
	NDB_FILTER_TAGS    = 4,
	NDB_FILTER_SINCE   = 5,
	NDB_FILTER_UNTIL   = 6,
	NDB_FILTER_LIMIT   = 7,
	NDB_FILTER_SEARCH  = 8,
};
#define NDB_NUM_FILTERS 7

// when matching generic tags, we need to know if we're dealing with
// a pointer to a 32-byte ID or a null terminated string
enum ndb_generic_element_type {
	NDB_ELEMENT_UNKNOWN = 0,
	NDB_ELEMENT_STRING  = 1,
	NDB_ELEMENT_ID      = 2,
	NDB_ELEMENT_INT     = 3,
};

enum ndb_search_order {
	NDB_ORDER_DESCENDING,
	NDB_ORDER_ASCENDING,
};

enum ndb_dbs {
	NDB_DB_NOTE,
	NDB_DB_META,
	NDB_DB_PROFILE,
	NDB_DB_NOTE_ID,
	NDB_DB_PROFILE_PK, // profile pk index
	NDB_DB_NDB_META,
	NDB_DB_PROFILE_SEARCH,
	NDB_DB_PROFILE_LAST_FETCH,
	NDB_DB_NOTE_KIND, // note kind index
	NDB_DB_NOTE_TEXT, // note fulltext index
	NDB_DB_NOTE_BLOCKS, // parsed note blocks for rendering
	NDB_DB_NOTE_TAGS,  // note tags index
	NDB_DB_NOTE_PUBKEY, // note pubkey index
	NDB_DB_NOTE_PUBKEY_KIND, // note pubkey kind index
	NDB_DBS,
};

// common kinds. we collect stats on these in ndb_stat. mainly because I don't
// want to deal with including a hashtable to the project.
enum ndb_common_kind {
	NDB_CKIND_PROFILE,
	NDB_CKIND_TEXT,
	NDB_CKIND_CONTACTS,
	NDB_CKIND_DM,
	NDB_CKIND_DELETE,
	NDB_CKIND_REPOST,
	NDB_CKIND_REACTION,
	NDB_CKIND_ZAP,
	NDB_CKIND_ZAP_REQUEST,
	NDB_CKIND_NWC_REQUEST,
	NDB_CKIND_NWC_RESPONSE,
	NDB_CKIND_HTTP_AUTH,
	NDB_CKIND_LIST,
	NDB_CKIND_LONGFORM,
	NDB_CKIND_STATUS,
	NDB_CKIND_COUNT, // should always be last
};

struct ndb_builder {
	struct cursor mem;
	struct cursor note_cur;
	struct cursor strings;
	struct cursor str_indices;
	struct ndb_note *note;
	struct ndb_tag *current_tag;
};

struct ndb_iterator {
	struct ndb_note *note;
	struct ndb_tag *tag;

	// current outer index
	int index;
};

struct ndb_filter_string {
	const char *string;
	int len;
};

union ndb_filter_element {
	struct ndb_filter_string string;
	const unsigned char *id;
	uint64_t integer;
};

struct ndb_filter_field {
	enum ndb_filter_fieldtype type;
	enum ndb_generic_element_type elem_type;
	char tag; // for generic queries like #t
};

struct ndb_filter_elements {
	struct ndb_filter_field field;
	int count;

	// this needs to be pointer size for reasons
	// FIXME: what about on 32bit systems??
	uint64_t elements[0];
};

struct ndb_filter {
	struct cursor elem_buf;
	struct cursor data_buf;
	int num_elements;
	int finalized;
	int current;

	// struct ndb_filter_elements offsets into elem_buf
	//
	// TODO(jb55): this should probably be called fields. elements are
	// the things within fields
	int elements[NDB_NUM_FILTERS]; 
};

struct ndb_config {
	int flags;
	int ingester_threads;
	size_t mapsize;
	void *filter_context;
	ndb_ingest_filter_fn ingest_filter;
	void *sub_cb_ctx;
	ndb_sub_fn sub_cb;
};

struct ndb_text_search_config {
	enum ndb_search_order order;
	int limit;
};

struct ndb_stat_counts {
	size_t key_size;
	size_t value_size;
	size_t count;
};

struct ndb_stat {
	struct ndb_stat_counts dbs[NDB_DBS];
	struct ndb_stat_counts common_kinds[NDB_CKIND_COUNT];
	struct ndb_stat_counts other_kinds;
};

#define MAX_TEXT_SEARCH_RESULTS 128
#define MAX_TEXT_SEARCH_WORDS 8

// unpacked form of the actual lmdb fulltext search key
// see `ndb_make_text_search_key` for how the packed version is constructed
struct ndb_text_search_key
{
	int str_len;
	const char *str;
	uint64_t timestamp;
	uint64_t note_id;
	uint64_t word_index;
};

struct ndb_text_search_result {
	struct ndb_text_search_key key;
	int prefix_chars;

	// This is only set if we passed a filter for nip50 searches
	struct ndb_note *note;
	uint64_t note_size;
};

struct ndb_text_search_results {
	struct ndb_text_search_result results[MAX_TEXT_SEARCH_RESULTS];
	int num_results;
};

enum ndb_block_type {
    BLOCK_HASHTAG        = 1,
    BLOCK_TEXT           = 2,
    BLOCK_MENTION_INDEX  = 3,
    BLOCK_MENTION_BECH32 = 4,
    BLOCK_URL            = 5,
    BLOCK_INVOICE        = 6,
};
#define NDB_NUM_BLOCK_TYPES 6
#define NDB_MAX_RELAYS 24

struct ndb_relays {
	struct ndb_str_block relays[NDB_MAX_RELAYS];
	int num_relays;
};

enum nostr_bech32_type {
	NOSTR_BECH32_NOTE = 1,
	NOSTR_BECH32_NPUB = 2,
	NOSTR_BECH32_NPROFILE = 3,
	NOSTR_BECH32_NEVENT = 4,
	NOSTR_BECH32_NRELAY = 5,
	NOSTR_BECH32_NADDR = 6,
	NOSTR_BECH32_NSEC = 7,
};
#define NOSTR_BECH32_KNOWN_TYPES 7

struct bech32_note {
	const unsigned char *event_id;
};

struct bech32_npub {
	const unsigned char *pubkey;
};

struct bech32_nsec {
	const unsigned char *nsec;
};

struct bech32_nevent {
	struct ndb_relays relays;
	const unsigned char *event_id;
	const unsigned char *pubkey; // optional
	uint32_t kind;
	bool has_kind;
};

struct bech32_nprofile {
	struct ndb_relays relays;
	const unsigned char *pubkey;
	uint32_t kind;
	bool has_kind;
};

struct bech32_naddr {
	struct ndb_relays relays;
	struct ndb_str_block identifier;
	const unsigned char *pubkey;
	uint32_t kind;
};

struct bech32_nrelay {
	struct ndb_str_block relay;
};

typedef struct nostr_bech32 {
	enum nostr_bech32_type type;

	union {
		struct bech32_note note;
		struct bech32_npub npub;
		struct bech32_nsec nsec;
		struct bech32_nevent nevent;
		struct bech32_nprofile nprofile;
		struct bech32_naddr naddr;
		struct bech32_nrelay nrelay;
	};
} nostr_bech32_t;


struct ndb_mention_bech32_block {
	struct ndb_str_block str;
	struct nostr_bech32 bech32;
};

struct ndb_invoice {
	unsigned char version;
	uint64_t amount;
	uint64_t timestamp;
	uint64_t expiry;
	char *description;
	unsigned char *description_hash;
};

struct ndb_invoice_block {
	struct ndb_str_block invstr;
	struct ndb_invoice invoice;
};

struct ndb_block {
	enum ndb_block_type type;
	union {
		struct ndb_str_block str;
		struct ndb_invoice_block invoice;
		struct ndb_mention_bech32_block mention_bech32;
		uint32_t mention_index;
	} block;
};

struct ndb_block_iterator {
	const char *content;
	struct ndb_blocks *blocks;
	struct ndb_block block;
	unsigned char *p;
};

struct ndb_query_result {
	struct ndb_note *note;
	uint64_t note_size;
	uint64_t note_id;
};

struct ndb_query_results {
	struct cursor cur;
};

// CONFIG
void ndb_default_config(struct ndb_config *);
void ndb_config_set_ingest_threads(struct ndb_config *config, int threads);
void ndb_config_set_flags(struct ndb_config *config, int flags);
void ndb_config_set_mapsize(struct ndb_config *config, size_t mapsize);
void ndb_config_set_ingest_filter(struct ndb_config *config, ndb_ingest_filter_fn fn, void *);
void ndb_config_set_subscription_callback(struct ndb_config *config, ndb_sub_fn fn, void *ctx);

// HELPERS
int ndb_calculate_id(struct ndb_note *note, unsigned char *buf, int buflen);
int ndb_sign_id(struct ndb_keypair *keypair, unsigned char id[32], unsigned char sig[64]);
int ndb_create_keypair(struct ndb_keypair *key);
int ndb_decode_key(const char *secstr, struct ndb_keypair *keypair);
int ndb_note_verify(void *secp_ctx, unsigned char pubkey[32], unsigned char id[32], unsigned char signature[64]);

// NDB
int ndb_init(struct ndb **ndb, const char *dbdir, const struct ndb_config *);
int ndb_db_version(struct ndb_txn *txn);
int ndb_process_event(struct ndb *, const char *json, int len);
int ndb_process_events(struct ndb *, const char *ldjson, size_t len);
#ifndef _WIN32
// TODO: fix on windows
int ndb_process_events_stream(struct ndb *, FILE* fp);
#endif
int ndb_process_client_event(struct ndb *, const char *json, int len);
int ndb_process_client_events(struct ndb *, const char *json, size_t len);
int ndb_begin_query(struct ndb *, struct ndb_txn *);
int ndb_search_profile(struct ndb_txn *txn, struct ndb_search *search, const char *query);
int ndb_search_profile_next(struct ndb_search *search);
void ndb_search_profile_end(struct ndb_search *search);
int ndb_end_query(struct ndb_txn *);
int ndb_write_last_profile_fetch(struct ndb *ndb, const unsigned char *pubkey, uint64_t fetched_at);
uint64_t ndb_read_last_profile_fetch(struct ndb_txn *txn, const unsigned char *pubkey);
void *ndb_get_profile_by_pubkey(struct ndb_txn *txn, const unsigned char *pubkey, size_t *len, uint64_t *primkey);
void *ndb_get_profile_by_key(struct ndb_txn *txn, uint64_t key, size_t *len);
uint64_t ndb_get_notekey_by_id(struct ndb_txn *txn, const unsigned char *id);
uint64_t ndb_get_profilekey_by_pubkey(struct ndb_txn *txn, const unsigned char *id);
struct ndb_note *ndb_get_note_by_id(struct ndb_txn *txn, const unsigned char *id, size_t *len, uint64_t *primkey);
struct ndb_note *ndb_get_note_by_key(struct ndb_txn *txn, uint64_t key, size_t *len);
void *ndb_get_note_meta(struct ndb_txn *txn, const unsigned char *id, size_t *len);
void ndb_destroy(struct ndb *);

// BUILDER
int ndb_parse_json_note(struct ndb_json_parser *, struct ndb_note **);
int ndb_client_event_from_json(const char *json, int len, struct ndb_fce *fce, unsigned char *buf, int bufsize, struct ndb_id_cb *cb);
int ndb_ws_event_from_json(const char *json, int len, struct ndb_tce *tce, unsigned char *buf, int bufsize, struct ndb_id_cb *);
int ndb_note_from_json(const char *json, int len, struct ndb_note **, unsigned char *buf, int buflen);
int ndb_builder_init(struct ndb_builder *builder, unsigned char *buf, size_t bufsize);
int ndb_builder_finalize(struct ndb_builder *builder, struct ndb_note **note, struct ndb_keypair *privkey);
int ndb_builder_set_content(struct ndb_builder *builder, const char *content, int len);
void ndb_builder_set_created_at(struct ndb_builder *builder, uint64_t created_at);
void ndb_builder_set_sig(struct ndb_builder *builder, unsigned char *sig);
void ndb_builder_set_pubkey(struct ndb_builder *builder, unsigned char *pubkey);
void ndb_builder_set_id(struct ndb_builder *builder, unsigned char *id);
void ndb_builder_set_kind(struct ndb_builder *builder, uint32_t kind);
int ndb_builder_new_tag(struct ndb_builder *builder);
int ndb_builder_push_tag_str(struct ndb_builder *builder, const char *str, int len);

// FILTERS
int ndb_filter_init(struct ndb_filter *);

/// Allocate a filter with a fixed sized buffer (where pages is number of 4096-byte sized blocks)
/// You can set pages to 1 if you know you are constructing small filters
// TODO: replace this with passed-in buffers
int ndb_filter_init_with(struct ndb_filter *filter, int pages);

int ndb_filter_add_id_element(struct ndb_filter *, const unsigned char *id);
int ndb_filter_add_int_element(struct ndb_filter *, uint64_t integer);
int ndb_filter_add_str_element(struct ndb_filter *, const char *str);
int ndb_filter_eq(const struct ndb_filter *, const struct ndb_filter *);

/// is `a` a subset of `b`
int ndb_filter_is_subset_of(const struct ndb_filter *a, const struct ndb_filter *b);

// filters from json
int ndb_filter_from_json(const char *, int len, struct ndb_filter *filter, unsigned char *buf, int bufsize);

// getting field elements
unsigned char *ndb_filter_get_id_element(const struct ndb_filter *, const struct ndb_filter_elements *, int index);
const char *ndb_filter_get_string_element(const struct ndb_filter *, const struct ndb_filter_elements *, int index);
uint64_t ndb_filter_get_int_element(const struct ndb_filter_elements *, int index);
uint64_t *ndb_filter_get_int_element_ptr(struct ndb_filter_elements *, int index);

struct ndb_filter_elements *ndb_filter_current_element(const struct ndb_filter *);
struct ndb_filter_elements *ndb_filter_get_elements(const struct ndb_filter *, int);
int ndb_filter_start_field(struct ndb_filter *, enum ndb_filter_fieldtype);
int ndb_filter_start_tag_field(struct ndb_filter *, char tag);
int ndb_filter_matches(struct ndb_filter *, struct ndb_note *);
int ndb_filter_clone(struct ndb_filter *dst, struct ndb_filter *src);
int ndb_filter_end(struct ndb_filter *);
void ndb_filter_end_field(struct ndb_filter *);
void ndb_filter_destroy(struct ndb_filter *);
int ndb_filter_json(const struct ndb_filter *, char *buf, int buflen);

// SUBSCRIPTIONS
uint64_t ndb_subscribe(struct ndb *, struct ndb_filter *, int num_filters);
int ndb_wait_for_notes(struct ndb *, uint64_t subid, uint64_t *note_ids, int note_id_capacity);
int ndb_poll_for_notes(struct ndb *, uint64_t subid, uint64_t *note_ids, int note_id_capacity);
int ndb_unsubscribe(struct ndb *, uint64_t subid);
int ndb_num_subscriptions(struct ndb *);

// FULLTEXT SEARCH
int ndb_text_search(struct ndb_txn *txn, const char *query, struct ndb_text_search_results *, struct ndb_text_search_config *);
int ndb_text_search_with(struct ndb_txn *txn, const char *query, struct ndb_text_search_results *, struct ndb_text_search_config *, struct ndb_filter *filter);
void ndb_default_text_search_config(struct ndb_text_search_config *);
void ndb_text_search_config_set_order(struct ndb_text_search_config *, enum ndb_search_order);
void ndb_text_search_config_set_limit(struct ndb_text_search_config *, int limit);

// QUERY
int ndb_query(struct ndb_txn *txn, struct ndb_filter *filters, int num_filters, struct ndb_query_result *results, int result_capacity, int *count);

// STATS
int ndb_stat(struct ndb *ndb, struct ndb_stat *stat);
void ndb_stat_counts_init(struct ndb_stat_counts *counts);

// NOTE
const char *ndb_note_content(struct ndb_note *note);
struct ndb_str ndb_note_str(struct ndb_note *note, union ndb_packed_str *pstr);
uint32_t ndb_note_content_length(struct ndb_note *note);
uint32_t ndb_note_created_at(struct ndb_note *note);
uint32_t ndb_note_kind(struct ndb_note *note);
unsigned char *ndb_note_id(struct ndb_note *note);
unsigned char *ndb_note_pubkey(struct ndb_note *note);
unsigned char *ndb_note_sig(struct ndb_note *note);
void _ndb_note_set_kind(struct ndb_note *note, uint32_t kind);
struct ndb_tags *ndb_note_tags(struct ndb_note *note);
int ndb_str_len(struct ndb_str *str);

/// write the note as json to a buffer
int ndb_note_json(struct ndb_note *, char *buf, int buflen);

// TAGS
void ndb_tags_iterate_start(struct ndb_note *note, struct ndb_iterator *iter);
uint16_t ndb_tags_count(struct ndb_tags *);
uint16_t ndb_tag_count(struct ndb_tag *);

// ITER
int ndb_tags_iterate_next(struct ndb_iterator *iter);
struct ndb_str ndb_iter_tag_str(struct ndb_iterator *iter, int ind);
struct ndb_str ndb_tag_str(struct ndb_note *note, struct ndb_tag *tag, int ind);

// NAMES
const char *ndb_db_name(enum ndb_dbs db);
const char *ndb_kind_name(enum ndb_common_kind ck);
enum ndb_common_kind ndb_kind_to_common_kind(int kind);

// CONTENT PARSER
int ndb_parse_content(unsigned char *buf, int buf_size,
		      const char *content, int content_len,
		      struct ndb_blocks **blocks_p);

// BLOCKS
enum ndb_block_type ndb_get_block_type(struct ndb_block *block);
int ndb_blocks_flags(struct ndb_blocks *block);
size_t ndb_blocks_total_size(struct ndb_blocks *blocks);
int ndb_blocks_word_count(struct ndb_blocks *blocks);

/// Free blocks if they are owned, safe to call on unowned blocks as well.
void ndb_blocks_free(struct ndb_blocks *blocks);

// BLOCK DB
struct ndb_blocks *ndb_get_blocks_by_key(struct ndb *ndb, struct ndb_txn *txn, uint64_t note_key);

// BLOCK ITERATORS
void ndb_blocks_iterate_start(const char *, struct ndb_blocks *, struct ndb_block_iterator *);
struct ndb_block *ndb_blocks_iterate_next(struct ndb_block_iterator *);

// STR BLOCKS
struct ndb_str_block *ndb_block_str(struct ndb_block *);
const char *ndb_str_block_ptr(struct ndb_str_block *);
uint32_t ndb_str_block_len(struct ndb_str_block *);

// BECH32 BLOCKS
struct nostr_bech32 *ndb_bech32_block(struct ndb_block *block);

#endif
