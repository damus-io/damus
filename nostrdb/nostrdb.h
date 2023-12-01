#ifndef NOSTRDB_H
#define NOSTRDB_H

#include <inttypes.h>
#include "cursor.h"

#define NDB_PACKED_STR     0x1
#define NDB_PACKED_ID      0x2

#define NDB_FLAG_NOMIGRATE (1 << 0)
#define NDB_FLAG_SKIP_NOTE_VERIFY (1 << 1)

//#define DEBUG 1

#ifdef DEBUG
#define ndb_debug(...) printf(__VA_ARGS__)
#else
#define ndb_debug(...) (void)0
#endif

struct ndb_json_parser;
struct ndb;

// sorry, swift needs help with forward declared pointers like this
struct ndb_t {
	struct ndb *ndb;
};

struct ndb_search_key
{
	char search[24];
	unsigned char id[32];
	uint64_t timestamp;
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

struct ndb_search {
	struct ndb_search_key *key;
	uint64_t profile_key;
	void *cursor; // MDB_cursor *
};

// required to keep a read 
struct ndb_txn {
	struct ndb_lmdb *lmdb;
	void *mdb_txn;
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
};

enum ndb_ingest_filter_action {
	NDB_INGEST_REJECT,
	NDB_INGEST_ACCEPT,
	NDB_INGEST_SKIP_VALIDATION
};

// function pointer for controlling what to do after we parse an id
typedef enum ndb_idres (*ndb_id_fn)(void *, const char *);

// id callback + closure data
struct ndb_id_cb {
	ndb_id_fn fn;
	void *data;
};

struct ndb_str {
	unsigned char flag;
	union {
		const char *str;
		unsigned char *id;
	};
};

struct ndb_event {
	struct ndb_note *note;
};

struct ndb_command_result {
	int ok;
	const char *msg;
	int msglen;
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

struct ndb_keypair {
	unsigned char pubkey[32];
	unsigned char secret[32];
	
	// this corresponds to secp256k1's keypair type. it's guaranteed to
	// be 96 bytes according to their docs. I don't want to depend on
	// the secp256k1 header here so we just use raw bytes.
	unsigned char pair[96];
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
	int word_index;
};

struct ndb_text_search_result {
	struct ndb_text_search_key key;
	int prefix_chars;
};

struct ndb_text_search_results {
	struct ndb_text_search_result results[MAX_TEXT_SEARCH_RESULTS];
	int num_results;
};

// these must be byte-aligned, they are directly accessing the serialized data
// representation
#pragma pack(push, 1)


union ndb_packed_str {
	struct {
		char str[3];
		// we assume little endian everywhere. sorry not sorry.
		unsigned char flag; // NDB_PACKED_STR, etc
	} packed;

	uint32_t offset;
	unsigned char bytes[4];
};

struct ndb_tag {
	uint16_t count;
	union ndb_packed_str strs[0];
};

struct ndb_tags {
	uint16_t padding;
	uint16_t count;
	struct ndb_tag tag[0];
};

// v1
struct ndb_note {
	unsigned char version;    // v=1
	unsigned char padding[3]; // keep things aligned
	unsigned char id[32];
	unsigned char pubkey[32];
	unsigned char sig[64];

	uint64_t created_at;
	uint32_t kind;
	uint32_t content_length;
	union ndb_packed_str content;
	uint32_t strings;
	// nothing can come after tags since it contains variadic data
	struct ndb_tags tags;
};

#pragma pack(pop)

typedef enum ndb_ingest_filter_action (*ndb_ingest_filter_fn)(void *, struct ndb_note *);

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

enum ndb_filter_fieldtype {
	NDB_FILTER_IDS     = 1,
	NDB_FILTER_AUTHORS = 2,
	NDB_FILTER_KINDS   = 3,
	NDB_FILTER_GENERIC = 4,
	NDB_FILTER_SINCE   = 5,
	NDB_FILTER_UNTIL   = 6,
	NDB_FILTER_LIMIT   = 7,
};
#define NDB_NUM_FILTERS 7

// when matching generic tags, we need to know if we're dealing with
// a pointer to a 32-byte ID or a null terminated string
enum ndb_generic_element_type {
	NDB_ELEMENT_UNKNOWN = 0,
	NDB_ELEMENT_STRING  = 1,
	NDB_ELEMENT_ID      = 2,
};

union ndb_filter_element {
	const char *string;
	const unsigned char *id;
	uint64_t integer;
};

struct ndb_filter_field {
	enum ndb_filter_fieldtype type;
	enum ndb_generic_element_type elem_type;
	char generic; // for generic queries like #t
};

struct ndb_filter_elements {
	struct ndb_filter_field field;
	int count;
	union ndb_filter_element elements[0];
};

struct ndb_filter {
	struct cursor elem_buf;
	struct cursor data_buf;
	int num_elements;
	struct ndb_filter_elements *current;
	struct ndb_filter_elements *elements[NDB_NUM_FILTERS];
};

struct ndb_config {
	int flags;
	int ingester_threads;
	size_t mapsize;
	void *filter_context;
	ndb_ingest_filter_fn ingest_filter;
};

// CONFIG
void ndb_default_config(struct ndb_config *);
void ndb_config_set_ingest_threads(struct ndb_config *config, int threads);
void ndb_config_set_flags(struct ndb_config *config, int flags);
void ndb_config_set_mapsize(struct ndb_config *config, size_t mapsize);
void ndb_config_set_ingest_filter(struct ndb_config *config, ndb_ingest_filter_fn fn, void *);

// HELPERS
int ndb_calculate_id(struct ndb_note *note, unsigned char *buf, int buflen);
int ndb_sign_id(struct ndb_keypair *keypair, unsigned char id[32], unsigned char sig[64]);
int ndb_create_keypair(struct ndb_keypair *key);
int ndb_decode_key(const char *secstr, struct ndb_keypair *keypair);
int ndb_note_verify(void *secp_ctx, unsigned char pubkey[32], unsigned char id[32], unsigned char signature[64]);

// NDB
int ndb_init(struct ndb **ndb, const char *dbdir, struct ndb_config *);
int ndb_db_version(struct ndb *ndb);
int ndb_process_event(struct ndb *, const char *json, int len);
int ndb_process_events(struct ndb *, const char *ldjson, size_t len);
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
int ndb_builder_init(struct ndb_builder *builder, unsigned char *buf, int bufsize);
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
int ndb_filter_add_id_element(struct ndb_filter *, const unsigned char *id);
int ndb_filter_add_int_element(struct ndb_filter *, uint64_t integer);
int ndb_filter_add_str_element(struct ndb_filter *, const char *str);
int ndb_filter_start_field(struct ndb_filter *, enum ndb_filter_fieldtype);
int ndb_filter_start_generic_field(struct ndb_filter *, char tag);
int ndb_filter_matches(struct ndb_filter *, struct ndb_note *);
void ndb_filter_reset(struct ndb_filter *);
void ndb_filter_end_field(struct ndb_filter *);
void ndb_filter_free(struct ndb_filter *filter);

// FULLTEXT SEARCH
int ndb_text_search(struct ndb_txn *txn, const char *query, struct ndb_text_search_results *);

// stats
int ndb_stat(struct ndb *ndb, struct ndb_stat *stat);
void ndb_stat_counts_init(struct ndb_stat_counts *counts);

static inline struct ndb_str ndb_note_str(struct ndb_note *note,
					  union ndb_packed_str *pstr)
{
	struct ndb_str str;
	str.flag = pstr->packed.flag;

	if (str.flag == NDB_PACKED_STR) {
		str.str = pstr->packed.str;
		return str;
	}

	str.str = ((const char *)note) + note->strings + (pstr->offset & 0xFFFFFF);
	return str;
}

static inline struct ndb_str ndb_tag_str(struct ndb_note *note,
					 struct ndb_tag *tag, int ind)
{
	return ndb_note_str(note, &tag->strs[ind]);
}

static inline struct ndb_str ndb_iter_tag_str(struct ndb_iterator *iter,
					      int ind)
{
	return ndb_tag_str(iter->note, iter->tag, ind);
}

static inline unsigned char * ndb_note_id(struct ndb_note *note)
{
	return note->id;
}

static inline unsigned char * ndb_note_pubkey(struct ndb_note *note)
{
	return note->pubkey;
}

static inline unsigned char * ndb_note_sig(struct ndb_note *note)
{
	return note->sig;
}

static inline uint32_t ndb_note_created_at(struct ndb_note *note)
{
	return note->created_at;
}

static inline uint32_t ndb_note_kind(struct ndb_note *note)
{
	return note->kind;
}

static inline const char *ndb_note_content(struct ndb_note *note)
{
	return ndb_note_str(note, &note->content).str;
}

static inline uint32_t ndb_note_content_length(struct ndb_note *note)
{
	return note->content_length;
}

static inline struct ndb_note * ndb_note_from_bytes(unsigned char *bytes)
{
	struct ndb_note *note = (struct ndb_note *)bytes;
	if (note->version != 1)
		return 0;
	return note;
}

static inline union ndb_packed_str ndb_offset_str(uint32_t offset)
{
	// ensure accidents like -1 don't corrupt our packed_str
	union ndb_packed_str str;
	// most significant byte is reserved for ndb_packtype
	str.offset = offset & 0xFFFFFF;
	return str;
}

static inline union ndb_packed_str ndb_char_to_packed_str(char c)
{
	union ndb_packed_str str;
	str.packed.flag = NDB_PACKED_STR;
	str.packed.str[0] = c;
	str.packed.str[1] = '\0';
	return str;
}

static inline union ndb_packed_str ndb_chars_to_packed_str(char c1, char c2)
{
	union ndb_packed_str str;
	str.packed.flag = NDB_PACKED_STR;
	str.packed.str[0] = c1;
	str.packed.str[1] = c2;
	str.packed.str[2] = '\0';
	return str;
}

static inline void ndb_tags_iterate_start(struct ndb_note *note,
					  struct ndb_iterator *iter)
{
	iter->note = note;
	iter->tag = NULL;
	iter->index = -1;
}

static inline int ndb_tags_iterate_next(struct ndb_iterator *iter)
{
	if (iter->tag == NULL || iter->index == -1) {
		iter->tag = iter->note->tags.tag;
		iter->index = 0;
		return iter->note->tags.count != 0;
	}

	struct ndb_tags *tags = &iter->note->tags;

	if (++iter->index < tags->count) {
		uint32_t tag_data_size = iter->tag->count * sizeof(iter->tag->strs[0]);
		iter->tag = (struct ndb_tag *)(iter->tag->strs[0].bytes + tag_data_size);
		return 1;
	}

	return 0;
}

static inline enum ndb_common_kind
ndb_kind_to_common_kind(int kind)
{
	switch (kind)
	{
		case 0:     return NDB_CKIND_PROFILE;
		case 1:     return NDB_CKIND_TEXT;
		case 3:     return NDB_CKIND_CONTACTS;
		case 4:     return NDB_CKIND_DM;
		case 5:     return NDB_CKIND_DELETE;
		case 6:     return NDB_CKIND_REPOST;
		case 7:     return NDB_CKIND_REACTION;
		case 9735:  return NDB_CKIND_ZAP;
		case 9734:  return NDB_CKIND_ZAP_REQUEST;
		case 23194: return NDB_CKIND_NWC_REQUEST;
		case 23195: return NDB_CKIND_NWC_RESPONSE;
		case 27235: return NDB_CKIND_HTTP_AUTH;
		case 30000: return NDB_CKIND_LIST;
		case 30023: return NDB_CKIND_LONGFORM;
		case 30315: return NDB_CKIND_STATUS;
	}

	return -1;
}

static inline const char *
ndb_kind_name(enum ndb_common_kind ck)
{
	switch (ck) {
		case NDB_CKIND_PROFILE:      return "profile";
		case NDB_CKIND_TEXT:         return "text";
		case NDB_CKIND_CONTACTS:     return "contacts";
		case NDB_CKIND_DM:           return "dm";
		case NDB_CKIND_DELETE:       return "delete";
		case NDB_CKIND_REPOST:       return "repost";
		case NDB_CKIND_REACTION:     return "reaction";
		case NDB_CKIND_ZAP:          return "zap";
		case NDB_CKIND_ZAP_REQUEST:  return "zap_request";
		case NDB_CKIND_NWC_REQUEST:  return "nwc_request";
		case NDB_CKIND_NWC_RESPONSE: return "nwc_response";
		case NDB_CKIND_HTTP_AUTH:    return "http_auth";
		case NDB_CKIND_LIST:         return "list";
		case NDB_CKIND_LONGFORM:     return "longform";
		case NDB_CKIND_STATUS:       return "status";
		case NDB_CKIND_COUNT:        return "unknown";
	}

	return "unknown";
}

static inline const char *
ndb_db_name(enum ndb_dbs db)
{
	switch (db) {
		case NDB_DB_NOTE:
			return "note";
		case NDB_DB_META:
			return "note_metadata";
		case NDB_DB_PROFILE:
			return "profile";
		case NDB_DB_NOTE_ID:
			return "note_index";
		case NDB_DB_PROFILE_PK:
			return "profile_pubkey_index";
		case NDB_DB_NDB_META:
			return "nostrdb_metadata";
		case NDB_DB_PROFILE_SEARCH:
			return "profile_search";
		case NDB_DB_PROFILE_LAST_FETCH:
			return "profile_last_fetch";
		case NDB_DB_NOTE_KIND:
			return "note_kind_index";
		case NDB_DB_NOTE_TEXT:
			return "note_fulltext";
		case NDB_DBS:
			return "count";
	}

	return "unknown";
}

#endif
