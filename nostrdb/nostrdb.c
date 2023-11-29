
#include "nostrdb.h"
#include "jsmn.h"
#include "hex.h"
#include "cursor.h"
#include "random.h"
#include "sha256.h"
#include "lmdb.h"
#include "util.h"
#include "threadpool.h"
#include "protected_queue.h"
#include "memchr.h"
#include <stdlib.h>
#include <limits.h>
#include <assert.h>

#include "bindings/c/profile_json_parser.h"
#include "bindings/c/profile_builder.h"
#include "bindings/c/meta_builder.h"
#include "bindings/c/meta_reader.h"
#include "bindings/c/profile_verifier.h"
#include "secp256k1.h"
#include "secp256k1_ecdh.h"
#include "secp256k1_schnorrsig.h"

#define max(a,b) ((a) > (b) ? (a) : (b))
#define min(a,b) ((a) < (b) ? (a) : (b))

// the maximum number of things threads pop and push in bulk
static const int THREAD_QUEUE_BATCH = 4096;

// the maximum size of inbox queues
static const int DEFAULT_QUEUE_SIZE = 1000000;

// increase if we need bigger filters
#define NDB_FILTER_PAGES 64

#define ndb_flag_set(flags, f) ((flags & f) == f)

#define NDB_PARSED_ID           (1 << 0)
#define NDB_PARSED_PUBKEY       (1 << 1)
#define NDB_PARSED_SIG          (1 << 2)
#define NDB_PARSED_CREATED_AT   (1 << 3)
#define NDB_PARSED_KIND         (1 << 4)
#define NDB_PARSED_CONTENT      (1 << 5)
#define NDB_PARSED_TAGS         (1 << 6)
#define NDB_PARSED_ALL          (NDB_PARSED_ID|NDB_PARSED_PUBKEY|NDB_PARSED_SIG|NDB_PARSED_CREATED_AT|NDB_PARSED_KIND|NDB_PARSED_CONTENT|NDB_PARSED_TAGS)

typedef int (*ndb_migrate_fn)(struct ndb *);
typedef int (*ndb_word_parser_fn)(void *, const char *word, int word_len,
				  int word_index);

struct ndb_migration {
	ndb_migrate_fn fn;
};

struct ndb_profile_record_builder {
	flatcc_builder_t *builder;
	void *flatbuf;
};

// controls whether to continue or stop the json parser
enum ndb_idres {
	NDB_IDRES_CONT,
	NDB_IDRES_STOP,
};

// closure data for the id-detecting ingest controller
struct ndb_ingest_controller
{
	MDB_txn *read_txn;
	struct ndb_lmdb *lmdb;
};

enum ndb_writer_msgtype {
	NDB_WRITER_QUIT, // kill thread immediately
	NDB_WRITER_NOTE, // write a note to the db
	NDB_WRITER_PROFILE, // write a profile to the db
	NDB_WRITER_DBMETA, // write ndb metadata
	NDB_WRITER_PROFILE_LAST_FETCH, // when profiles were last fetched
};

// keys used for storing data in the NDB metadata database (NDB_DB_NDB_META)
enum ndb_meta_key {
	NDB_META_KEY_VERSION = 1
};

struct ndb_json_parser {
	const char *json;
	int json_len;
	struct ndb_builder builder;
	jsmn_parser json_parser;
	jsmntok_t *toks, *toks_end;
	int i;
	int num_tokens;
};

// useful to pass to threads on its own
struct ndb_lmdb {
	MDB_env *env;
	MDB_dbi dbs[NDB_DBS];
};

struct ndb_writer {
	struct ndb_lmdb *lmdb;

	void *queue_buf;
	int queue_buflen;
	pthread_t thread_id;

	struct prot_queue inbox;
};

struct ndb_ingester {
	struct threadpool tp;
	struct ndb_writer *writer;
};


struct ndb {
	struct ndb_lmdb lmdb;
	struct ndb_ingester ingester;
	struct ndb_writer writer;
	int version;
	// lmdb environ handles, etc
};


// A clustered key with an id and a timestamp
struct ndb_tsid {
	unsigned char id[32];
	uint64_t timestamp;
};

// A u64 + timestamp id. Just using this for kinds at the moment.
struct ndb_u64_tsid {
	uint64_t u64; // kind, etc
	uint64_t timestamp;
};

#define MAX_RESULTS_PER_WORD 32
#define MAX_TEXT_SEARCH_WORDS 8

// used mainly by ndb_text_search when collecting text search results
struct ndb_keyed_text_search_result {
	struct ndb_text_search_key key;
	uint64_t note_id;
	int prefix_chars;
};

struct ndb_keyed_text_search_resultset {
	struct ndb_keyed_text_search_result results[MAX_RESULTS_PER_WORD];
	int num_results;
};

struct ndb_word
{
	const char *word;
	int word_len;
};

struct ndb_search_words
{
	struct ndb_word words[MAX_TEXT_SEARCH_WORDS];
	int num_words;
};

// used mainly by ndb_text_search when collecting text search results
struct ndb_keyed_text_search_results {
	struct ndb_keyed_text_search_resultset results[MAX_TEXT_SEARCH_WORDS];
	int num_words;
};


// ndb_text_search_key
//
// This is compressed when in lmdb:
//
//   strlen:     varint
//   str:        cstr
//   timestamp:  varint
//   word_index: varint
static int ndb_make_text_search_key(unsigned char *buf, int bufsize,
				    int word_index, int word_len, const char *str,
				    uint64_t timestamp, int *keysize)
{
	struct cursor cur;
	int size, pad;
	make_cursor(buf, buf + bufsize, &cur);

	// string length
	if (!push_varint(&cur, word_len))
		return 0;

	// non-null terminated, lowercase string
	if (!cursor_push_lowercase(&cur, str, word_len))
		return 0;

	// the index of the word in the content so that we can do more accurate
	// phrase searches
	if (!push_varint(&cur, word_index))
		return 0;

	// TODO: need update this to uint64_t
	if (!push_varint(&cur, (int)timestamp))
		return 0;

	size = cur.p - cur.start;

	// pad to 8-byte alignment
	pad = ((size + 7) & ~7) - size;
	if (pad > 0) {
		if (!cursor_memset(&cur, 0, pad)) {
			return 0;
		}
	}

	*keysize = cur.p - cur.start;
	assert((*keysize % 8) == 0);

	return 1;
}

static int ndb_make_text_search_key_low(unsigned char *buf, int bufsize,
					int wordlen, const char *word,
					int *keysize)
{
	return ndb_make_text_search_key(buf, bufsize, 0, wordlen, word, 0, keysize);
}

/** From LMDB: Compare two items lexically */
static int mdb_cmp_memn(const MDB_val *a, const MDB_val *b) {
	int diff;
	ssize_t len_diff;
	unsigned int len;

	len = a->mv_size;
	len_diff = (ssize_t) a->mv_size - (ssize_t) b->mv_size;
	if (len_diff > 0) {
		len = b->mv_size;
		len_diff = 1;
	}

	diff = memcmp(a->mv_data, b->mv_data, len);
	return diff ? diff : len_diff<0 ? -1 : len_diff;
}

static int ndb_text_search_key_compare(const MDB_val *a, const MDB_val *b)
{
	struct cursor ca, cb;
	int sa, sb;
	MDB_val a2, b2;

	make_cursor(a->mv_data, a->mv_data + a->mv_size, &ca);
	make_cursor(b->mv_data, b->mv_data + b->mv_size, &cb);

	// string size
	if (unlikely(!pull_varint(&ca, &sa) || !pull_varint(&cb, &sb)))
		return 0;

	a2.mv_data = ca.p;
	a2.mv_size = sa;

	b2.mv_data = cb.p;
	b2.mv_size = sb;

	int cmp = mdb_cmp_memn(&a2, &b2);
	if (cmp) return cmp;

	// skip over string
	ca.p += sa;
	cb.p += sb;

	// timestamp
	if (unlikely(!pull_varint(&ca, &sa) || !pull_varint(&cb, &sb)))
		return 0;

	if      (sa < sb) return -1;
	else if (sa > sb) return 1;

	// word index
	if (unlikely(!pull_varint(&ca, &sa) || !pull_varint(&cb, &sb)))
		return 0;

	if      (sa < sb) return -1;
	else if (sa > sb) return 1;

	return 0;
}

// faster peek of just the string instead of unpacking everything
// this is used to quickly discard range query matches if there is no
// common prefix
static inline int ndb_unpack_text_search_key_string(struct cursor *cur,
						    const char **str,
						    int *str_len)
{
	if (!pull_varint(cur, str_len))
		return 0;

	*str = (const char *)cur->p;

	if (!cursor_skip(cur, *str_len))
		return 0;
	
	return 1;
}

// should be called after ndb_unpack_text_search_key_string. It continues
// the unpacking of a text search key if we've already started it.
static inline int
ndb_unpack_remaining_text_search_key(struct cursor *cur,
				     struct ndb_text_search_key *key)
{
	int timestamp;

	if (!pull_varint(cur, &key->word_index))
		return 0;

	if (!pull_varint(cur, &timestamp))
		return 0;

	key->timestamp = timestamp;

	return 1;
}

// unpack a fulltext search key
//
// full version of string + unpack remaining. This is split up because text
// searching only requires to pull the string for prefix searching, and the
// remaining is optional
static inline int ndb_unpack_text_search_key(unsigned char *p, int len,
				      struct ndb_text_search_key *key)
{
	struct cursor c;
	make_cursor(p, p + len, &c);

	if (!ndb_unpack_text_search_key_string(&c, &key->str, &key->str_len))
		return 0;

	return ndb_unpack_remaining_text_search_key(&c, key);
}

// Copies only lowercase characters to the destination string and fills the rest with null bytes.
// `dst` and `src` are pointers to the destination and source strings, respectively.
// `n` is the maximum number of characters to copy.
static void lowercase_strncpy(char *dst, const char *src, int n) {
	int j = 0, i = 0;

	if (!dst || !src || n == 0) {
		return;
	}

	while (src[i] != '\0' && j < n) {
		dst[j++] = tolower(src[i++]);
	}

	// Null-terminate and fill the destination string
	while (j < n) {
		dst[j++] = '\0';
	}
}

int ndb_filter_init(struct ndb_filter *filter)
{
	struct cursor cur;
	int page_size, elem_pages, data_pages, buf_size;

	page_size = 4096; // assuming this, not a big deal if we're wrong
	elem_pages = NDB_FILTER_PAGES / 4;
	data_pages = NDB_FILTER_PAGES - elem_pages;
	buf_size = page_size * NDB_FILTER_PAGES;

	unsigned char *buf = malloc(buf_size);
	if (!buf)
		return 0;

	// init memory arena for the cursor
	make_cursor(buf, buf + buf_size, &cur);

	cursor_slice(&cur, &filter->elem_buf, page_size * elem_pages);
	cursor_slice(&cur, &filter->data_buf, page_size * data_pages);

	// make sure we are fully allocated
	assert(cur.p == cur.end);

	// make sure elem_buf is the start of the buffer
	assert(filter->elem_buf.start == cur.start);

	filter->num_elements = 0;
	filter->elements[0] = (struct ndb_filter_elements*) buf;
	filter->current = NULL;

	return 1;
}

void ndb_filter_reset(struct ndb_filter *filter)
{
	filter->num_elements = 0;
	filter->elem_buf.p = filter->elem_buf.start;
	filter->data_buf.p = filter->data_buf.start;
	filter->current = NULL;
}

void ndb_filter_free(struct ndb_filter *filter)
{
	if (filter->elem_buf.start)
		free(filter->elem_buf.start);

	memset(filter, 0, sizeof(*filter));
}

static const char *ndb_filter_field_name(enum ndb_filter_fieldtype field)
{
	switch (field) {
	case NDB_FILTER_IDS: return "ids";
	case NDB_FILTER_AUTHORS: return "authors";
	case NDB_FILTER_KINDS: return "kinds";
	case NDB_FILTER_GENERIC: return "generic";
	case NDB_FILTER_SINCE: return "since";
	case NDB_FILTER_UNTIL: return "until";
	case NDB_FILTER_LIMIT: return "limit";
	}

	return "unknown";
}

static int ndb_filter_start_field_impl(struct ndb_filter *filter, enum ndb_filter_fieldtype field, char generic)
{
	int i;
	struct ndb_filter_elements *els, *el;

	if (filter->current) {
		fprintf(stderr, "ndb_filter_start_field: filter field already in progress, did you forget to call ndb_filter_end_field?\n");
		return 0;
	}

	// you can only start and end fields once
	for (i = 0; i < filter->num_elements; i++) {
		el = filter->elements[i];
		if (el->field.type == field) {
			fprintf(stderr, "ndb_filter_start_field: field '%s' already exists\n",
					ndb_filter_field_name(field));
			return 0;
		}
	}

	els = (struct ndb_filter_elements *) filter->elem_buf.p ;
	filter->current = els;

	// advance elem buffer to the variable data section
	if (!cursor_skip(&filter->elem_buf, sizeof(struct ndb_filter_elements))) {
		fprintf(stderr, "ndb_filter_start_field: '%s' oom (todo: realloc?)\n",
				ndb_filter_field_name(field));
		return 0;
	}

	els->field.type = field;
	els->field.generic = generic;
	els->field.elem_type = 0;
	els->count = 0;

	return 1;
}

int ndb_filter_start_field(struct ndb_filter *filter, enum ndb_filter_fieldtype field)
{
	return ndb_filter_start_field_impl(filter, field, 0);
}

int ndb_filter_start_generic_field(struct ndb_filter *filter, char tag)
{
	return ndb_filter_start_field_impl(filter, NDB_FILTER_GENERIC, tag);
}

static int ndb_filter_add_element(struct ndb_filter *filter, union ndb_filter_element el)
{
	unsigned char *data;
	const char *str;

	if (!filter->current)
		return 0;

	data = filter->data_buf.p;

	switch (filter->current->field.type) {
	case NDB_FILTER_IDS:
	case NDB_FILTER_AUTHORS:
		if (!cursor_push(&filter->data_buf, (unsigned char *)el.id, 32))
			return 0;
		el.id = data;
		break;
	case NDB_FILTER_KINDS:
		break;
	case NDB_FILTER_SINCE:
	case NDB_FILTER_UNTIL:
	case NDB_FILTER_LIMIT:
		// only one allowed for since/until
		if (filter->current->count != 0)
			return 0;
		break;
	case NDB_FILTER_GENERIC:
		str = (const char *)filter->data_buf.p;
		if (!cursor_push_c_str(&filter->data_buf, el.string))
			return 0;
		// push a pointer of the string in the databuf as an element
		el.string = str;
		break;
	}

	if (!cursor_push(&filter->elem_buf, (unsigned char*)&el, sizeof(el)))
		return 0;

	filter->current->count++;

	return 1;
}

static int ndb_filter_set_elem_type(struct ndb_filter *filter,
				    enum ndb_generic_element_type elem_type)
{
	enum ndb_generic_element_type current_elem_type;

	if (!filter->current)
		return 0;

	current_elem_type = filter->current->field.elem_type;

	// element types must be uniform
	if (current_elem_type != elem_type && current_elem_type != NDB_ELEMENT_UNKNOWN) {
		fprintf(stderr, "ndb_filter_set_elem_type: element types must be uniform\n");
		return 0;
	}

	filter->current->field.elem_type = elem_type;

	return 1;
}

int ndb_filter_add_str_element(struct ndb_filter *filter, const char *str)
{
	union ndb_filter_element el;

	if (!filter->current)
		return 0;

	// only generic queries are allowed to have strings
	switch (filter->current->field.type) {
	case NDB_FILTER_SINCE:
	case NDB_FILTER_UNTIL:
	case NDB_FILTER_LIMIT:
	case NDB_FILTER_IDS:
	case NDB_FILTER_AUTHORS:
	case NDB_FILTER_KINDS:
		return 0;
	case NDB_FILTER_GENERIC:
		break;
	}

	if (!ndb_filter_set_elem_type(filter, NDB_ELEMENT_STRING))
		return 0;

	el.string = str;
	return ndb_filter_add_element(filter, el);
}

int ndb_filter_add_int_element(struct ndb_filter *filter, uint64_t integer)
{
	union ndb_filter_element el;
	if (!filter->current)
		return 0;

	switch (filter->current->field.type) {
	case NDB_FILTER_IDS:
	case NDB_FILTER_AUTHORS:
	case NDB_FILTER_GENERIC:
		return 0;
	case NDB_FILTER_KINDS:
	case NDB_FILTER_SINCE:
	case NDB_FILTER_UNTIL:
	case NDB_FILTER_LIMIT:
		break;
	}

	el.integer = integer;

	return ndb_filter_add_element(filter, el);
}

int ndb_filter_add_id_element(struct ndb_filter *filter, const unsigned char *id)
{
	union ndb_filter_element el;

	if (!filter->current)
		return 0;

	// only certain filter types allow pushing id elements
	switch (filter->current->field.type) {
	case NDB_FILTER_SINCE:
	case NDB_FILTER_UNTIL:
	case NDB_FILTER_LIMIT:
		return 0;
	case NDB_FILTER_IDS:
	case NDB_FILTER_AUTHORS:
	case NDB_FILTER_KINDS:
	case NDB_FILTER_GENERIC:
		break;
	}

	if (!ndb_filter_set_elem_type(filter, NDB_ELEMENT_ID))
		return 0;

	// this is needed so that generic filters know its an id
	el.id = id;

	return ndb_filter_add_element(filter, el);
}

// TODO: build a hashtable so this is O(1)
static int ndb_generic_filter_matches(struct ndb_filter_elements *els,
				      struct ndb_note *note)
{
	int i;
	union ndb_filter_element el;
	struct ndb_iterator iter, *it = &iter;
	struct ndb_str str;

	ndb_tags_iterate_start(note, it);

	while (ndb_tags_iterate_next(it)) {
		// we're looking for tags with 2 or more entries: ["p", id], etc
		if (it->tag->count < 2)
			continue;

		str = ndb_note_str(note, &it->tag->strs[0]);

		// we only care about packed strings (single char, etc)
		if (str.flag != NDB_PACKED_STR)
			continue;

		// do we have #e matching e (or p, etc)
		if (str.str[0] != els->field.generic || str.str[1] != 0)
			continue;

		str = ndb_note_str(note, &it->tag->strs[1]);

		switch (els->field.elem_type) {
		case NDB_ELEMENT_ID:
			// if our filter element type is an id, then we
			// expect a packed id in the tag, otherwise skip
			if (str.flag != NDB_PACKED_ID)
				continue;
			break;
		case NDB_ELEMENT_STRING:
			// if our filter element type is a string, then
			// we should not expect an id
			if (str.flag == NDB_PACKED_ID)
				continue;
			break;
		case NDB_ELEMENT_UNKNOWN:
		default:
			// For some reason the element type is not set. It's
			// possible nothing was added to the generic filter?
			// Let's just fail here and log a note for debugging
			fprintf(stderr, "UNUSUAL ndb_generic_filter_matches: have unknown element type %d\n", els->field.elem_type);
			return 0;
		}

		for (i = 0; i < els->count; i++) {
			el = els->elements[i];
			switch (els->field.elem_type) {
			case NDB_ELEMENT_ID:
				if (!memcmp(el.id, str.id, 32))
					return 1;
				break;
			case NDB_ELEMENT_STRING:
				if (!strcmp(el.string, str.str))
					return 1;
				break;
			case NDB_ELEMENT_UNKNOWN:
				return 0;
			}
		}
	}

	return 0;
}

// returns 1 if a filter matches a note
int ndb_filter_matches(struct ndb_filter *filter, struct ndb_note *note)
{
	int i, j;
	struct ndb_filter_elements *els;

	for (i = 0; i < filter->num_elements; i++) {
		els = filter->elements[i];

		switch (els->field.type) {
		case NDB_FILTER_KINDS:
			for (j = 0; j < els->count; j++) {
				if ((unsigned int)els->elements[j].integer == note->kind)
					goto cont;
			}
			break;
		// TODO: add filter hashtable for large id lists
		case NDB_FILTER_IDS:
			for (j = 0; j < els->count; j++) {
				if (!memcmp(els->elements[j].id, note->id, 32))
					goto cont;
			}
			break;
		case NDB_FILTER_AUTHORS:
			for (j = 0; j < els->count; j++) {
				if (!memcmp(els->elements[j].id, note->pubkey, 32))
					goto cont;
			}
			break;
		case NDB_FILTER_GENERIC:
			if (ndb_generic_filter_matches(els, note))
				continue;
			break;
		case NDB_FILTER_SINCE:
			assert(els->count == 1);
			if (note->created_at >= els->elements[0].integer)
				continue;
			break;
		case NDB_FILTER_UNTIL:
			assert(els->count == 1);
			if (note->created_at < els->elements[0].integer)
				continue;
		case NDB_FILTER_LIMIT:
cont:
			continue;
		}

		// all need to match
		return 0;
	}

	return 1;
}

void ndb_filter_end_field(struct ndb_filter *filter)
{
	filter->elements[filter->num_elements++] = filter->current;
	filter->current = NULL;
}

static void ndb_make_search_key(struct ndb_search_key *key, unsigned char *id,
			        uint64_t timestamp, const char *search)
{
	memcpy(key->id, id, 32);
	key->timestamp = timestamp;
	lowercase_strncpy(key->search, search, sizeof(key->search) - 1);
	key->search[sizeof(key->search) - 1] = '\0';
}

static int ndb_write_profile_search_index(struct ndb_txn *txn,
					  struct ndb_search_key *index_key,
					  uint64_t profile_key)
{
	int rc;
	MDB_val key, val;
	
	key.mv_data = index_key;
	key.mv_size = sizeof(*index_key);
	val.mv_data = &profile_key;
	val.mv_size = sizeof(profile_key);

	if ((rc = mdb_put(txn->mdb_txn, txn->lmdb->dbs[NDB_DB_PROFILE_SEARCH],
			  &key, &val, 0)))
	{
		ndb_debug("ndb_write_profile_search_index failed: %s\n",
			  mdb_strerror(rc));
		return 0;
	}

	return 1;
}


// map usernames and display names to profile keys for user searching
static int ndb_write_profile_search_indices(struct ndb_txn *txn,
					    struct ndb_note *note,
					    uint64_t profile_key,
					    void *profile_root)
{
	struct ndb_search_key index;
	NdbProfileRecord_table_t profile_record;
	NdbProfile_table_t profile;

	profile_record = NdbProfileRecord_as_root(profile_root);
	profile = NdbProfileRecord_profile_get(profile_record);

	const char *name = NdbProfile_name_get(profile);
	const char *display_name = NdbProfile_display_name_get(profile);

	// words + pubkey + created
	if (name) {
		ndb_make_search_key(&index, note->pubkey, note->created_at,
				    name);
		if (!ndb_write_profile_search_index(txn, &index, profile_key))
			return 0;
	}

	if (display_name) {
		// don't write the same name/display_name twice
		if (name && !strcmp(display_name, name)) {
			return 1;
		}
		ndb_make_search_key(&index, note->pubkey, note->created_at,
				    display_name);
		if (!ndb_write_profile_search_index(txn, &index, profile_key))
			return 0;
	}

	return 1;
}


static int _ndb_begin_query(struct ndb *ndb, struct ndb_txn *txn, int flags)
{
	txn->lmdb = &ndb->lmdb;
	MDB_txn **mdb_txn = (MDB_txn **)&txn->mdb_txn;
	return mdb_txn_begin(txn->lmdb->env, NULL, flags, mdb_txn) == 0;
}

int ndb_begin_query(struct ndb *ndb, struct ndb_txn *txn)
{
	return _ndb_begin_query(ndb, txn, MDB_RDONLY);
}

// this should only be used in migrations, etc
static int ndb_begin_rw_query(struct ndb *ndb, struct ndb_txn *txn)
{
	return _ndb_begin_query(ndb, txn, 0);
}


// Migrations
//

static int ndb_migrate_user_search_indices(struct ndb *ndb)
{
	int rc;
	MDB_cursor *cur;
	MDB_val k, v;
	void *profile_root;
	NdbProfileRecord_table_t record;
	struct ndb_txn txn;
	struct ndb_note *note;
	uint64_t note_key, profile_key;
	size_t len;
	int count;

	if (!ndb_begin_rw_query(ndb, &txn)) {
		fprintf(stderr, "ndb_migrate_user_search_indices: ndb_begin_rw_query failed\n");
		return 0;
	}

	if ((rc = mdb_cursor_open(txn.mdb_txn, ndb->lmdb.dbs[NDB_DB_PROFILE], &cur))) {
		fprintf(stderr, "ndb_migrate_user_search_indices: mdb_cursor_open failed, error %d\n", rc);
		return 0;
	}

	count = 0;

	// loop through all profiles and write search indices
	while (mdb_cursor_get(cur, &k, &v, MDB_NEXT) == 0) {
		profile_root = v.mv_data;
		profile_key = *((uint64_t*)k.mv_data);
		record = NdbProfileRecord_as_root(profile_root);
		note_key = NdbProfileRecord_note_key(record);
		note = ndb_get_note_by_key(&txn, note_key, &len);

		if (note == NULL) {
			fprintf(stderr, "ndb_migrate_user_search_indices: note lookup failed\n");
			return 0;
		}

		if (!ndb_write_profile_search_indices(&txn, note, profile_key,
						      profile_root)) {

			fprintf(stderr, "ndb_migrate_user_search_indices: ndb_write_profile_search_indices failed\n");
			return 0;
		}

		count++;
	}

	fprintf(stderr, "migrated %d profiles to include search indices\n", count);

	mdb_cursor_close(cur);

	ndb_end_query(&txn);

	return 1;
}

static int ndb_migrate_lower_user_search_indices(struct ndb *ndb)
{
	MDB_txn *txn;

	if (mdb_txn_begin(ndb->lmdb.env, NULL, 0, &txn)) {
		fprintf(stderr, "ndb_migrate_lower_user_search_indices: ndb_txn_begin failed\n");
		return 0;
	}

	// just drop the search db so we can rebuild it
	if (mdb_drop(txn, ndb->lmdb.dbs[NDB_DB_PROFILE_SEARCH], 0)) {
		fprintf(stderr, "ndb_migrate_lower_user_search_indices: mdb_drop failed\n");
		return 0;
	}

	mdb_txn_commit(txn);

	return ndb_migrate_user_search_indices(ndb);
}

int ndb_process_profile_note(struct ndb_note *note, struct ndb_profile_record_builder *profile);


int ndb_db_version(struct ndb *ndb)
{
	int rc;
	uint64_t version, version_key;
	MDB_val k, v;
	MDB_txn *txn;

	version_key = NDB_META_KEY_VERSION;
	k.mv_data = &version_key;
	k.mv_size = sizeof(version_key);

	if ((rc = mdb_txn_begin(ndb->lmdb.env, NULL, 0, &txn))) {
		fprintf(stderr, "ndb_db_version: mdb_txn_begin failed, error %d\n", rc);
		return -1;
	}

	if (mdb_get(txn, ndb->lmdb.dbs[NDB_DB_NDB_META], &k, &v)) {
		version = -1;
	} else {
		if (v.mv_size != 8) {
			fprintf(stderr, "run_migrations: invalid version size?");
			return 0;
		}
		version = *((uint64_t*)v.mv_data);
	}

	mdb_txn_abort(txn);
	return version;
}

// custom kind+timestamp comparison function. This is used by lmdb to perform
// b+ tree searches over the kind+timestamp index
static int ndb_u64_tsid_compare(const MDB_val *a, const MDB_val *b)
{
	struct ndb_u64_tsid *tsa, *tsb;
	tsa = a->mv_data;
	tsb = b->mv_data;

	if (tsa->u64 < tsb->u64)
		return -1;
	else if (tsa->u64 > tsb->u64)
		return 1;

	if (tsa->timestamp < tsb->timestamp)
		return -1;
	else if (tsa->timestamp > tsb->timestamp)
		return 1;

	return 0;
}

static int ndb_tsid_compare(const MDB_val *a, const MDB_val *b)
{
	struct ndb_tsid *tsa, *tsb;
	MDB_val a2 = *a, b2 = *b;

	a2.mv_size = sizeof(tsa->id);
	b2.mv_size = sizeof(tsb->id);

	int cmp = mdb_cmp_memn(&a2, &b2);
	if (cmp) return cmp;

	tsa = a->mv_data;
	tsb = b->mv_data;

	if (tsa->timestamp < tsb->timestamp)
		return -1;
	else if (tsa->timestamp > tsb->timestamp)
		return 1;
	return 0;
}

static inline void ndb_tsid_low(struct ndb_tsid *key, unsigned char *id)
{
	memcpy(key->id, id, 32);
	key->timestamp = 0;
}

static inline void ndb_tsid_init(struct ndb_tsid *key, unsigned char *id,
				 uint64_t timestamp)
{
	memcpy(key->id, id, 32);
	key->timestamp = timestamp;
}

static inline void ndb_u64_tsid_init(struct ndb_u64_tsid *key, uint64_t integer,
				     uint64_t timestamp)
{
	key->u64 = integer;
	key->timestamp = timestamp;
}

// useful for range-searching for the latest key with a clustered created_at timen
static inline void ndb_tsid_high(struct ndb_tsid *key, const unsigned char *id)
{
	memcpy(key->id, id, 32);
	key->timestamp = UINT64_MAX;
}

enum ndb_ingester_msgtype {
	NDB_INGEST_EVENT, // write json to the ingester queue for processing 
	NDB_INGEST_QUIT,  // kill ingester thread immediately
};

struct ndb_ingester_event {
	char *json;
	unsigned client : 1; // ["EVENT", {...}] messages
	unsigned len : 31;
};

struct ndb_writer_note {
	struct ndb_note *note;
	size_t note_len;
};

struct ndb_writer_profile {
	struct ndb_writer_note note;
	struct ndb_profile_record_builder record;
};

struct ndb_ingester_msg {
	enum ndb_ingester_msgtype type;
	union {
		struct ndb_ingester_event event;
	};
};

struct ndb_writer_ndb_meta {
	// these are 64 bit because I'm paranoid of db-wide alignment issues
	uint64_t version;
};

// Used in the writer thread when writing ndb_profile_fetch_record's
//   kv = pubkey: recor
struct ndb_writer_last_fetch {
	unsigned char pubkey[32];
	uint64_t fetched_at;
};

// The different types of messages that the writer thread can write to the
// database
struct ndb_writer_msg {
	enum ndb_writer_msgtype type;
	union {
		struct ndb_writer_note note;
		struct ndb_writer_profile profile;
		struct ndb_writer_ndb_meta ndb_meta;
		struct ndb_writer_last_fetch last_fetch;
	};
};

static inline int ndb_writer_queue_msg(struct ndb_writer *writer,
				       struct ndb_writer_msg *msg)
{
	return prot_queue_push(&writer->inbox, msg);
}

static int ndb_migrate_utf8_profile_names(struct ndb *ndb)
{
	int rc;
	MDB_cursor *cur;
	MDB_val k, v;
	void *profile_root;
	NdbProfileRecord_table_t record;
	struct ndb_txn txn;
	struct ndb_note *note, *copied_note;
	uint64_t note_key;
	size_t len;
	int count, failed;
	struct ndb_writer_msg out;

	if (!ndb_begin_rw_query(ndb, &txn)) {
		fprintf(stderr, "ndb_migrate_utf8_profile_names: ndb_begin_rw_query failed\n");
		return 0;
	}

	if ((rc = mdb_cursor_open(txn.mdb_txn, ndb->lmdb.dbs[NDB_DB_PROFILE], &cur))) {
		fprintf(stderr, "ndb_migrate_utf8_profile_names: mdb_cursor_open failed, error %d\n", rc);
		return 0;
	}

	count = 0;
	failed = 0;

	// loop through all profiles and write search indices
	while (mdb_cursor_get(cur, &k, &v, MDB_NEXT) == 0) {
		profile_root = v.mv_data;
		record = NdbProfileRecord_as_root(profile_root);
		note_key = NdbProfileRecord_note_key(record);
		note = ndb_get_note_by_key(&txn, note_key, &len);

		if (note == NULL) {
			fprintf(stderr, "ndb_migrate_utf8_profile_names: note lookup failed\n");
			return 0;
		}

		struct ndb_profile_record_builder *b = &out.profile.record;

		// reprocess profile
		if (!ndb_process_profile_note(note, b)) {
			failed++;
			continue;
		}

		// the writer needs to own this note, and its expected to free it
		copied_note = malloc(len);
		memcpy(copied_note, note, len);

		out.type = NDB_WRITER_PROFILE;
		out.profile.note.note = copied_note;
		out.profile.note.note_len = len;

		ndb_writer_queue_msg(&ndb->writer, &out);

		count++;
	}

	fprintf(stderr, "migrated %d profiles to fix utf8 profile names\n", count);

	if (failed != 0) {
		fprintf(stderr, "failed to migrate %d profiles to fix utf8 profile names\n", failed);
	}

	mdb_cursor_close(cur);

	ndb_end_query(&txn);

	return 1;
}

static struct ndb_migration MIGRATIONS[] = {
	{ .fn = ndb_migrate_user_search_indices },
	{ .fn = ndb_migrate_lower_user_search_indices },
	{ .fn = ndb_migrate_utf8_profile_names }
};


int ndb_end_query(struct ndb_txn *txn)
{
	// this works on read or write queries. 
	return mdb_txn_commit(txn->mdb_txn) == 0;
}

int ndb_note_verify(void *ctx, unsigned char pubkey[32], unsigned char id[32],
		    unsigned char sig[64])
{
	secp256k1_xonly_pubkey xonly_pubkey;
	int ok;

	ok = secp256k1_xonly_pubkey_parse((secp256k1_context*)ctx, &xonly_pubkey,
					  pubkey) != 0;
	if (!ok) return 0;

	ok = secp256k1_schnorrsig_verify((secp256k1_context*)ctx, sig, id, 32,
					 &xonly_pubkey) > 0;
	if (!ok) return 0;

	return 1;
}

static inline int ndb_writer_queue_msgs(struct ndb_writer *writer,
					struct ndb_writer_msg *msgs,
					int num_msgs)
{
	return prot_queue_push_all(&writer->inbox, msgs, num_msgs);
}

static int ndb_writer_queue_note(struct ndb_writer *writer,
				 struct ndb_note *note, size_t note_len)
{
	struct ndb_writer_msg msg;
	msg.type = NDB_WRITER_NOTE;

	msg.note.note = note;
	msg.note.note_len = note_len;

	return prot_queue_push(&writer->inbox, &msg);
}

static void ndb_writer_last_profile_fetch(struct ndb_txn *txn,
					  const unsigned char *pubkey,
					  uint64_t fetched_at)
{
	int rc;
	MDB_val key, val;
	
	key.mv_data = (unsigned char*)pubkey;
	key.mv_size = 32;
	val.mv_data = &fetched_at;
	val.mv_size = sizeof(fetched_at);

	if ((rc = mdb_put(txn->mdb_txn, txn->lmdb->dbs[NDB_DB_PROFILE_LAST_FETCH],
			  &key, &val, 0)))
	{
		ndb_debug("write version to ndb_meta failed: %s\n",
				mdb_strerror(rc));
		return;
	}

	//fprintf(stderr, "writing version %" PRIu64 "\n", version);
}


// We just received a profile that we haven't processed yet, but it could
// be an older one! Make sure we only write last fetched profile if it's a new
// one
//
// To do this, we first check the latest profile in the database. If the
// created_date for this profile note is newer, then we write a
// last_profile_fetch record, otherwise we do not.
//
// WARNING: This function is only valid when called from the writer thread
static int ndb_maybe_write_last_profile_fetch(struct ndb_txn *txn,
					       struct ndb_note *note)
{
	size_t len;
	uint64_t profile_key, note_key;
	void *root;
	struct ndb_note *last_profile;
	NdbProfileRecord_table_t record;

	if ((root = ndb_get_profile_by_pubkey(txn, note->pubkey, &len, &profile_key))) {
		record = NdbProfileRecord_as_root(root);
		note_key = NdbProfileRecord_note_key(record);
		last_profile = ndb_get_note_by_key(txn, note_key, &len);
		if (last_profile == NULL) {
			return 0;
		}

		// found profile, let's see if it's newer than ours
		if (note->created_at > last_profile->created_at) {
			// this is a new profile note, record last fetched time
			ndb_writer_last_profile_fetch(txn, note->pubkey, time(NULL));
		}
	} else {
		// couldn't fetch profile. record last fetched time
		ndb_writer_last_profile_fetch(txn, note->pubkey, time(NULL));
	}

	return 1;
}

int ndb_write_last_profile_fetch(struct ndb *ndb, const unsigned char *pubkey,
				 uint64_t fetched_at)
{
	struct ndb_writer_msg msg;
	msg.type = NDB_WRITER_PROFILE_LAST_FETCH;
	memcpy(&msg.last_fetch.pubkey[0], pubkey, 32);
	msg.last_fetch.fetched_at = fetched_at;

	return ndb_writer_queue_msg(&ndb->writer, &msg);
}

// get some value based on a clustered id key
int ndb_get_tsid(struct ndb_txn *txn, enum ndb_dbs db, const unsigned char *id,
		 MDB_val *val)
{
	MDB_val k, v;
	MDB_cursor *cur;
	int success = 0, rc;
	struct ndb_tsid tsid;

	// position at the most recent
	ndb_tsid_high(&tsid, id);

	k.mv_data = &tsid;
	k.mv_size = sizeof(tsid);

	if ((rc = mdb_cursor_open(txn->mdb_txn, txn->lmdb->dbs[db], &cur))) {
		ndb_debug("ndb_get_tsid: failed to open cursor: '%s'\n", mdb_strerror(rc));
		return 0;
	}

	// Position cursor at the next key greater than or equal to the specified key
	if (mdb_cursor_get(cur, &k, &v, MDB_SET_RANGE)) {
		// Failed :(. It could be the last element?
		if (mdb_cursor_get(cur, &k, &v, MDB_LAST))
			goto cleanup;
	} else {
		// if set range worked and our key exists, it should be
		// the one right before this one
		if (mdb_cursor_get(cur, &k, &v, MDB_PREV))
			goto cleanup;
	}

	if (memcmp(k.mv_data, id, 32) == 0) {
		*val = v;
		success = 1;
	}

cleanup:
	mdb_cursor_close(cur);
	return success;
}

static void *ndb_lookup_by_key(struct ndb_txn *txn, uint64_t key,
			       enum ndb_dbs store, size_t *len)
{
	MDB_val k, v;

	k.mv_data = &key;
	k.mv_size = sizeof(key);

	if (mdb_get(txn->mdb_txn, txn->lmdb->dbs[store], &k, &v)) {
		ndb_debug("ndb_get_profile_by_pubkey: mdb_get note failed\n");
		return NULL;
	}

	if (len)
		*len = v.mv_size;

	return v.mv_data;
}

static void *ndb_lookup_tsid(struct ndb_txn *txn, enum ndb_dbs ind,
			     enum ndb_dbs store, const unsigned char *pk,
			     size_t *len, uint64_t *primkey)
{
	MDB_val k, v;
	void *res = NULL;
	if (len)
		*len = 0;

	if (!ndb_get_tsid(txn, ind, pk, &k)) {
		//ndb_debug("ndb_get_profile_by_pubkey: ndb_get_tsid failed\n");
		return 0;
	}

	if (primkey)
		*primkey = *(uint64_t*)k.mv_data;

	if (mdb_get(txn->mdb_txn, txn->lmdb->dbs[store], &k, &v)) {
		ndb_debug("ndb_get_profile_by_pubkey: mdb_get note failed\n");
		return 0;
	}

	res = v.mv_data;
	assert(((uint64_t)res % 4) == 0);
	if (len)
		*len = v.mv_size;
	return res;
}

void *ndb_get_profile_by_pubkey(struct ndb_txn *txn, const unsigned char *pk, size_t *len, uint64_t *key)
{
	return ndb_lookup_tsid(txn, NDB_DB_PROFILE_PK, NDB_DB_PROFILE, pk, len, key);
}

struct ndb_note *ndb_get_note_by_id(struct ndb_txn *txn, const unsigned char *id, size_t *len, uint64_t *key)
{
	return ndb_lookup_tsid(txn, NDB_DB_NOTE_ID, NDB_DB_NOTE, id, len, key);
}

static inline uint64_t ndb_get_indexkey_by_id(struct ndb_txn *txn,
					      enum ndb_dbs db,
					      const unsigned char *id)
{
	MDB_val k;

	if (!ndb_get_tsid(txn, db, id, &k))
		return 0;

	return *(uint32_t*)k.mv_data;
}

uint64_t ndb_get_notekey_by_id(struct ndb_txn *txn, const unsigned char *id)
{
	return ndb_get_indexkey_by_id(txn, NDB_DB_NOTE_ID, id);
}

uint64_t ndb_get_profilekey_by_pubkey(struct ndb_txn *txn, const unsigned char *id)
{
	return ndb_get_indexkey_by_id(txn, NDB_DB_PROFILE_PK, id);
}

struct ndb_note *ndb_get_note_by_key(struct ndb_txn *txn, uint64_t key, size_t *len)
{
	return ndb_lookup_by_key(txn, key, NDB_DB_NOTE, len);
}

void *ndb_get_profile_by_key(struct ndb_txn *txn, uint64_t key, size_t *len)
{
	return ndb_lookup_by_key(txn, key, NDB_DB_PROFILE, len);
}

uint64_t
ndb_read_last_profile_fetch(struct ndb_txn *txn, const unsigned char *pubkey)
{
	MDB_val k, v;

	k.mv_data = (unsigned char*)pubkey;
	k.mv_size = 32;

	if (mdb_get(txn->mdb_txn, txn->lmdb->dbs[NDB_DB_PROFILE_LAST_FETCH], &k, &v)) {
		//ndb_debug("ndb_read_last_profile_fetch: mdb_get note failed\n");
		return 0;
	}

	return *((uint64_t*)v.mv_data);
}


static int ndb_has_note(struct ndb_txn *txn, const unsigned char *id)
{
	MDB_val val;

	if (!ndb_get_tsid(txn, NDB_DB_NOTE_ID, id, &val))
		return 0;

	return 1;
}

static void ndb_txn_from_mdb(struct ndb_txn *txn, struct ndb_lmdb *lmdb,
			     MDB_txn *mdb_txn)
{
	txn->lmdb = lmdb;
	txn->mdb_txn = mdb_txn;
}

static enum ndb_idres ndb_ingester_json_controller(void *data, const char *hexid)
{
	unsigned char id[32];
	struct ndb_ingest_controller *c = data;
	struct ndb_txn txn;

	hex_decode(hexid, 64, id, sizeof(id));

	// let's see if we already have it

	ndb_txn_from_mdb(&txn, c->lmdb, c->read_txn);
	if (!ndb_has_note(&txn, id))
		return NDB_IDRES_CONT;

	return NDB_IDRES_STOP;
}

static int ndbprofile_parse_json(flatcc_builder_t *B,
        const char *buf, size_t bufsiz, int flags, NdbProfile_ref_t *profile)
{
	flatcc_json_parser_t parser, *ctx = &parser;
	flatcc_json_parser_init(ctx, B, buf, buf + bufsiz, flags);

	if (flatcc_builder_start_buffer(B, 0, 0, 0))
		return 0;

	NdbProfile_parse_json_table(ctx, buf, buf + bufsiz, profile);
	if (ctx->error)
		return 0;
 
	if (!flatcc_builder_end_buffer(B, *profile))
		return 0;

	ctx->end_loc = buf;


	return 1;
}

void ndb_profile_record_builder_init(struct ndb_profile_record_builder *b)
{
	b->builder = malloc(sizeof(*b->builder));
	b->flatbuf = NULL;
}

void ndb_profile_record_builder_free(struct ndb_profile_record_builder *b)
{
	if (b->builder)
		free(b->builder);
	if (b->flatbuf)
		free(b->flatbuf);

	b->builder = NULL;
	b->flatbuf = NULL;
}

int ndb_process_profile_note(struct ndb_note *note,
			     struct ndb_profile_record_builder *profile)
{
	int res;

	NdbProfile_ref_t profile_table;
	flatcc_builder_t *builder;

	ndb_profile_record_builder_init(profile);
	builder = profile->builder;
	flatcc_builder_init(builder);

	NdbProfileRecord_start_as_root(builder);

	//printf("parsing profile '%.*s'\n", note->content_length, ndb_note_content(note));
	if (!(res = ndbprofile_parse_json(builder, ndb_note_content(note),
					  note->content_length,
					  flatcc_json_parser_f_skip_unknown,
					  &profile_table)))
	{
		ndb_debug("profile_parse_json failed %d '%.*s'\n", res,
			  note->content_length, ndb_note_content(note));
		ndb_profile_record_builder_free(profile);
		return 0;
	}

	uint64_t received_at = time(NULL);
	const char *lnurl = "fixme";

	NdbProfileRecord_profile_add(builder, profile_table);
	NdbProfileRecord_received_at_add(builder, received_at);

	flatcc_builder_ref_t lnurl_off;
	lnurl_off = flatcc_builder_create_string_str(builder, lnurl);

	NdbProfileRecord_lnurl_add(builder, lnurl_off);

	//*profile = flatcc_builder_finalize_aligned_buffer(builder, profile_len);
	return 1;
}

static int ndb_ingester_process_note(secp256k1_context *ctx,
				     struct ndb_note *note,
				     size_t note_size,
				     struct ndb_writer_msg *out)
{
	//printf("ndb_ingester_process_note ");
	//print_hex(note->id, 32);
	//printf("\n");

	// Verify! If it's an invalid note we don't need to
	// bother writing it to the database
	if (!ndb_note_verify(ctx, note->pubkey, note->id, note->sig)) {
		ndb_debug("signature verification failed\n");
		return 0;
	}

	// we didn't find anything. let's send it
	// to the writer thread
	note = realloc(note, note_size);
	assert(((uint64_t)note % 4) == 0);

	if (note->kind == 0) {
		struct ndb_profile_record_builder *b = 
			&out->profile.record;

		ndb_process_profile_note(note, b);

		out->type = NDB_WRITER_PROFILE;
		out->profile.note.note = note;
		out->profile.note.note_len = note_size;
	} else {
		out->type = NDB_WRITER_NOTE;
		out->note.note = note;
		out->note.note_len = note_size;
	}

	return 1;
}


static int ndb_ingester_process_event(secp256k1_context *ctx,
				      struct ndb_ingester *ingester,
				      struct ndb_ingester_event *ev,
				      struct ndb_writer_msg *out,
				      MDB_txn *read_txn
				      )
{
	struct ndb_tce tce;
	struct ndb_fce fce;
	struct ndb_note *note;
	struct ndb_ingest_controller controller;
	struct ndb_id_cb cb;
	void *buf;
	int ok;
	size_t bufsize, note_size;

	ok = 0;

	// we will use this to check if we already have it in the DB during
	// ID parsing
	controller.read_txn = read_txn;
	controller.lmdb = ingester->writer->lmdb;
	cb.fn = ndb_ingester_json_controller;
	cb.data = &controller;

	// since we're going to be passing this allocated note to a different
	// thread, we can't use thread-local buffers. just allocate a block
        bufsize = max(ev->len * 8.0, 4096);
	buf = malloc(bufsize);
	if (!buf) {
		ndb_debug("couldn't malloc buf\n");
		return 0;
	}

	note_size =
		ev->client ? 
		ndb_client_event_from_json(ev->json, ev->len, &fce, buf, bufsize, &cb) :
		ndb_ws_event_from_json(ev->json, ev->len, &tce, buf, bufsize, &cb);

	if (note_size == -42) {
		// we already have this!
		//ndb_debug("already have id??\n");
		goto cleanup;
	} else if (note_size == 0) {
		ndb_debug("failed to parse '%.*s'\n", ev->len, ev->json);
		goto cleanup;
	}

	//ndb_debug("parsed evtype:%d '%.*s'\n", tce.evtype, ev->len, ev->json);

	if (ev->client) {
		switch (fce.evtype) {
		case NDB_FCE_EVENT:
			note = fce.event.note;
			if (note != buf) {
				ndb_debug("note buffer not equal to malloc'd buffer\n");
				goto cleanup;
			}

			if (!ndb_ingester_process_note(ctx, note, note_size, out))
				goto cleanup;
			else {
				// we're done with the original json, free it
				free(ev->json);
				return 1;
			}
		}
	} else {
		switch (tce.evtype) {
		case NDB_TCE_NOTICE: goto cleanup;
		case NDB_TCE_EOSE:   goto cleanup;
		case NDB_TCE_OK:     goto cleanup;
		case NDB_TCE_EVENT:
			note = tce.event.note;
			if (note != buf) {
				ndb_debug("note buffer not equal to malloc'd buffer\n");
				goto cleanup;
			}

			if (!ndb_ingester_process_note(ctx, note, note_size, out))
				goto cleanup;
			else {
				// we're done with the original json, free it
				free(ev->json);
				return 1;
			}
		}
	}


cleanup:
	free(ev->json);
	free(buf);

	return ok;
}

static uint64_t ndb_get_last_key(MDB_txn *txn, MDB_dbi db)
{
	MDB_cursor *mc;
	MDB_val key, val;

	if (mdb_cursor_open(txn, db, &mc))
		return 0;

	if (mdb_cursor_get(mc, &key, &val, MDB_LAST)) {
		mdb_cursor_close(mc);
		return 0;
	}

	mdb_cursor_close(mc);

	assert(key.mv_size == 8);
        return *((uint64_t*)key.mv_data);
}

//
// make a search key meant for user queries without any other note info
static void ndb_make_search_key_low(struct ndb_search_key *key, const char *search)
{
	memset(key->id, 0, sizeof(key->id));
	key->timestamp = 0;
	lowercase_strncpy(key->search, search, sizeof(key->search) - 1);
	key->search[sizeof(key->search) - 1] = '\0';
}

int ndb_search_profile(struct ndb_txn *txn, struct ndb_search *search, const char *query)
{
	int rc;
	struct ndb_search_key s;
	MDB_val k, v;
	search->cursor = NULL;

	MDB_cursor **cursor = (MDB_cursor **)&search->cursor;

	ndb_make_search_key_low(&s, query);

	k.mv_data = &s;
	k.mv_size = sizeof(s);

	if ((rc = mdb_cursor_open(txn->mdb_txn,
				  txn->lmdb->dbs[NDB_DB_PROFILE_SEARCH],
				  cursor))) {
		printf("search_profile: cursor opened failed: %s\n",
				mdb_strerror(rc));
		return 0;
	}

	// Position cursor at the next key greater than or equal to the specified key
	if (mdb_cursor_get(search->cursor, &k, &v, MDB_SET_RANGE)) {
		printf("search_profile: cursor get failed\n");
		goto cleanup;
	} else {
		search->key = k.mv_data;
		assert(v.mv_size == 8);
		search->profile_key = *((uint64_t*)v.mv_data);
		return 1;
	}

cleanup:
	mdb_cursor_close(search->cursor);
	search->cursor = NULL;
	return 0;
}

void ndb_search_profile_end(struct ndb_search *search)
{
	if (search->cursor)
		mdb_cursor_close(search->cursor);
}

int ndb_search_profile_next(struct ndb_search *search)
{
	int rc;
	MDB_val k, v;
	unsigned char *init_id;

	init_id = search->key->id;
	k.mv_data = search->key;
	k.mv_size = sizeof(*search->key);

retry:
	if ((rc = mdb_cursor_get(search->cursor, &k, &v, MDB_NEXT))) {
		ndb_debug("ndb_search_profile_next: %s\n",
				mdb_strerror(rc));
		return 0;
	} else {
		search->key = k.mv_data;
		assert(v.mv_size == 8);
		search->profile_key = *((uint64_t*)v.mv_data);

		// skip duplicate pubkeys
		if (!memcmp(init_id, search->key->id, 32))
			goto retry;
	}

	return 1;
}

static int ndb_search_key_cmp(const MDB_val *a, const MDB_val *b)
{
	int cmp;
	struct ndb_search_key *ska, *skb;

	ska = a->mv_data;
	skb = b->mv_data;

	MDB_val a2 = *a;
	MDB_val b2 = *b;

	a2.mv_data = ska->search;
	a2.mv_size = sizeof(ska->search) + sizeof(ska->id);

	cmp = mdb_cmp_memn(&a2, &b2);
	if (cmp) return cmp;

	if (ska->timestamp < skb->timestamp)
		return -1;
	else if (ska->timestamp > skb->timestamp)
		return 1;

	return 0;
}

static int ndb_write_profile_pk_index(struct ndb_txn *txn, struct ndb_note *note, uint64_t profile_key)
	
{
	MDB_val key, val;
	int rc;
	struct ndb_tsid tsid;
	MDB_dbi pk_db;

	pk_db = txn->lmdb->dbs[NDB_DB_PROFILE_PK];

	// write profile_pk + created_at index
	ndb_tsid_init(&tsid, note->pubkey, note->created_at);

	key.mv_data = &tsid;
	key.mv_size = sizeof(tsid);
	val.mv_data = &profile_key;
	val.mv_size = sizeof(profile_key);

	if ((rc = mdb_put(txn->mdb_txn, pk_db, &key, &val, 0))) {
		ndb_debug("write profile_pk(%" PRIu64 ") to db failed: %s\n",
				profile_key, mdb_strerror(rc));
		return 0;
	}

	return 1;
}

static int ndb_write_profile(struct ndb_txn *txn,
			     struct ndb_writer_profile *profile,
			     uint64_t note_key)
{
	uint64_t profile_key;
	struct ndb_note *note;
	void *flatbuf;
	size_t flatbuf_len;
	int rc;

	MDB_val key, val;
	MDB_dbi profile_db;
	
	note = profile->note.note;

	// add note_key to profile record
	NdbProfileRecord_note_key_add(profile->record.builder, note_key);
	NdbProfileRecord_end_as_root(profile->record.builder);

	flatbuf = profile->record.flatbuf =
		flatcc_builder_finalize_aligned_buffer(profile->record.builder, &flatbuf_len);

	assert(((uint64_t)flatbuf % 8) == 0);

	// TODO: this may not be safe!?
	flatbuf_len = (flatbuf_len + 7) & ~7;

	//assert(NdbProfileRecord_verify_as_root(flatbuf, flatbuf_len) == 0);

	// get dbs
	profile_db = txn->lmdb->dbs[NDB_DB_PROFILE];

	// get new key
	profile_key = ndb_get_last_key(txn->mdb_txn, profile_db) + 1;

	// write profile to profile store
	key.mv_data = &profile_key;
	key.mv_size = sizeof(profile_key);
	val.mv_data = flatbuf;
	val.mv_size = flatbuf_len;

	if ((rc = mdb_put(txn->mdb_txn, profile_db, &key, &val, 0))) {
		ndb_debug("write profile to db failed: %s\n", mdb_strerror(rc));
		return 0;
	}

	// write last fetched record
	if (!ndb_maybe_write_last_profile_fetch(txn, note)) {
		ndb_debug("failed to write last profile fetched record\n");
		return 0;
	}

	// write profile pubkey index
	if (!ndb_write_profile_pk_index(txn, note, profile_key)) {
		ndb_debug("failed to write profile pubkey index\n");
		return 0;
	}

	// write name, display_name profile search indices
	if (!ndb_write_profile_search_indices(txn, note, profile_key,
					      flatbuf)) {
		ndb_debug("failed to write profile search indices\n");
		return 0;
	}

	return 1;
}

// find the last id tag in a note (e, p, etc)
static unsigned char *ndb_note_last_id_tag(struct ndb_note *note, char type)
{
	unsigned char *last = NULL;
	struct ndb_iterator iter;
	struct ndb_str str;

	// get the liked event id (last id)
	ndb_tags_iterate_start(note, &iter);

	while (ndb_tags_iterate_next(&iter)) {
		if (iter.tag->count < 2)
			continue;

		str = ndb_note_str(note, &iter.tag->strs[0]);

		// assign liked to the last e tag
		if (str.flag == NDB_PACKED_STR && str.str[0] == type) {
			str = ndb_note_str(note, &iter.tag->strs[1]);
			if (str.flag == NDB_PACKED_ID)
				last = str.id;
		}
	}

	return last;
}

void *ndb_get_note_meta(struct ndb_txn *txn, const unsigned char *id, size_t *len)
{
	MDB_val k, v;

	k.mv_data = (unsigned char*)id;
	k.mv_size = 32;

	if (mdb_get(txn->mdb_txn, txn->lmdb->dbs[NDB_DB_META], &k, &v)) {
		ndb_debug("ndb_get_note_meta: mdb_get note failed\n");
		return NULL;
	}

	if (len)
		*len = v.mv_size;

	return v.mv_data;
}

// When receiving a reaction note, look for the liked id and increase the
// reaction counter in the note metadata database
//
// TODO: I found some bugs when implementing this feature. If the same note id
// is processed multiple times in the same ingestion block, then it will count
// the like twice. This is because it hasn't been written to the DB yet and the
// ingestor doesn't know about notes that are being processed at the same time.
// One fix for this is to maintain a hashtable in the ingestor and make sure
// the same note is not processed twice.
// 
// I'm not sure how common this would be, so I'm not going to worry about it
// for now, but it's something to keep in mind.
static int ndb_write_reaction_stats(struct ndb_txn *txn, struct ndb_note *note)
{
	size_t len;
	void *root;
	int reactions, rc;
	MDB_val key, val;
	NdbEventMeta_table_t meta;
	unsigned char *liked = ndb_note_last_id_tag(note, 'e');

	if (liked == NULL)
		return 0;

	root = ndb_get_note_meta(txn, liked, &len);

	flatcc_builder_t builder;
	flatcc_builder_init(&builder);
	NdbEventMeta_start_as_root(&builder);

	// no meta record, let's make one
	if (root == NULL) {
		NdbEventMeta_reactions_add(&builder, 1);
	} else {
		// clone existing and add to it
		meta = NdbEventMeta_as_root(root);
	
		reactions = NdbEventMeta_reactions_get(meta);
		NdbEventMeta_clone(&builder, meta);
		NdbEventMeta_reactions_add(&builder, reactions + 1);
	}

	NdbProfileRecord_end_as_root(&builder);
	root = flatcc_builder_finalize_aligned_buffer(&builder, &len);
	assert(((uint64_t)root % 8) == 0);

	if (root == NULL) {
		ndb_debug("failed to create note metadata record\n");
		return 0;
	}

	// metadata is keyed on id because we want to collect stats regardless
	// if we have the note yet or not
	key.mv_data = liked;
	key.mv_size = 32;
	
	val.mv_data = root;
	val.mv_size = len;

	// write the new meta record
	//ndb_debug("writing stats record for ");
	//print_hex(liked, 32);
	//ndb_debug("\n");

	if ((rc = mdb_put(txn->mdb_txn, txn->lmdb->dbs[NDB_DB_META], &key, &val, 0))) {
		ndb_debug("write reaction stats to db failed: %s\n", mdb_strerror(rc));
		return 0;
	}

	free(root);

	return 1;
}


static int ndb_write_note_id_index(struct ndb_txn *txn, struct ndb_note *note,
				   uint64_t note_key)
	
{
	struct ndb_tsid tsid;
	int rc;
	MDB_val key, val;
	MDB_dbi id_db;

	ndb_tsid_init(&tsid, note->id, note->created_at);

	key.mv_data = &tsid;
	key.mv_size = sizeof(tsid);
	val.mv_data = &note_key;
	val.mv_size = sizeof(note_key);

	id_db = txn->lmdb->dbs[NDB_DB_NOTE_ID];

	if ((rc = mdb_put(txn->mdb_txn, id_db, &key, &val, 0))) {
		ndb_debug("write note id index to db failed: %s\n",
				mdb_strerror(rc));
		return 0;
	}

	return 1;
}

static int ndb_write_note_kind_index(struct ndb_txn *txn, struct ndb_note *note,
				     uint64_t note_key)
{
	struct ndb_u64_tsid tsid;
	int rc;
	MDB_val key, val;
	MDB_dbi kind_db;

	ndb_u64_tsid_init(&tsid, note->kind, note->created_at);

	key.mv_data = &tsid;
	key.mv_size = sizeof(tsid);
	val.mv_data = &note_key;
	val.mv_size = sizeof(note_key);

	kind_db = txn->lmdb->dbs[NDB_DB_NOTE_KIND];

	if ((rc = mdb_put(txn->mdb_txn, kind_db, &key, &val, 0))) {
		ndb_debug("write note kind index to db failed: %s\n",
				mdb_strerror(rc));
		return 0;
	}

	return 1;
}

/**
  * Checks if a given Unicode code point is a punctuation character
  *
  * @param codepoint The Unicode code point to check. @return true if the
  * code point is a punctuation character, false otherwise.
  */
static inline int is_punctuation(unsigned int codepoint) {
	// Check for underscore (underscore is not treated as punctuation)
	if (codepoint == '_')
		return 0;

	// Check for ASCII punctuation
	if (ispunct(codepoint))
		return 1;

	// Check for Unicode punctuation exceptions (punctuation allowed in hashtags)
	if (codepoint == 0x301C || codepoint == 0xFF5E) // Japanese Wave Dash / Tilde
		return 0;

	// Check for Unicode punctuation
	// NOTE: We may need to adjust the codepoint ranges in the future,
	// to include/exclude certain types of Unicode characters in hashtags.
	// Unicode Blocks Reference: https://www.compart.com/en/unicode/block
	return (
		// Latin-1 Supplement No-Break Space (NBSP): U+00A0
		(codepoint == 0x00A0) ||

		// Latin-1 Supplement Punctuation: U+00A1 to U+00BF
		(codepoint >= 0x00A1 && codepoint <= 0x00BF) ||

		// General Punctuation: U+2000 to U+206F
		(codepoint >= 0x2000 && codepoint <= 0x206F) ||

		// Currency Symbols: U+20A0 to U+20CF
		(codepoint >= 0x20A0 && codepoint <= 0x20CF) ||

		// Supplemental Punctuation: U+2E00 to U+2E7F
		(codepoint >= 0x2E00 && codepoint <= 0x2E7F) ||

		// CJK Symbols and Punctuation: U+3000 to U+303F
		(codepoint >= 0x3000 && codepoint <= 0x303F) ||

		// Ideographic Description Characters: U+2FF0 to U+2FFF
		(codepoint >= 0x2FF0 && codepoint <= 0x2FFF)
	);
}

static inline int is_whitespace(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
}

static inline int is_right_boundary(int c) {
	return is_whitespace(c) || is_punctuation(c);
}

static inline int parse_byte(struct cursor *cursor, unsigned char *c)
{
	if (unlikely(cursor->p >= cursor->end))
		return 0;

	*c = *cursor->p;

	return 1;
}

static inline int peek_char(struct cursor *cur, int ind) {
	if ((cur->p + ind < cur->start) || (cur->p + ind >= cur->end))
		return -1;

	return *(cur->p + ind);
}

static int parse_utf8_char(struct cursor *cursor, unsigned int *code_point,
			   unsigned int *utf8_length)
{
	unsigned char first_byte;
	if (!parse_byte(cursor, &first_byte))
		return 0; // Not enough data

	// Determine the number of bytes in this UTF-8 character
	int remaining_bytes = 0;
	if (first_byte < 0x80) {
		*code_point = first_byte;
		return 1;
	} else if ((first_byte & 0xE0) == 0xC0) {
		remaining_bytes = 1;
		*utf8_length = remaining_bytes + 1;
		*code_point = first_byte & 0x1F;
	} else if ((first_byte & 0xF0) == 0xE0) {
		remaining_bytes = 2;
		*utf8_length = remaining_bytes + 1;
		*code_point = first_byte & 0x0F;
	} else if ((first_byte & 0xF8) == 0xF0) {
		remaining_bytes = 3;
		*utf8_length = remaining_bytes + 1;
		*code_point = first_byte & 0x07;
	} else {
		remaining_bytes = 0;
		*utf8_length = 1; // Assume 1 byte length for unrecognized UTF-8 characters
		// TODO: We need to gracefully handle unrecognized UTF-8 characters
		//printf("Invalid UTF-8 byte: %x\n", *code_point);
		*code_point = ((first_byte & 0xF0) << 6); // Prevent testing as punctuation
		return 0; // Invalid first byte
	}

	// Peek at remaining bytes
	for (int i = 0; i < remaining_bytes; ++i) {
		signed char next_byte;
		if ((next_byte = peek_char(cursor, i+1)) == -1) {
			*utf8_length = 1;
			return 0; // Not enough data
		}

		if ((next_byte & 0xC0) != 0x80) {
			*utf8_length = 1;
			return 0; // Invalid byte in sequence
		}

		*code_point = (*code_point << 6) | (next_byte & 0x3F);
	}

	return 1;
}


static inline int is_utf8_byte(unsigned char c) {
    return c & 0x80;
}

static inline int consume_until_boundary(struct cursor *cur) {
	unsigned int c;
	unsigned int char_length = 1;
	unsigned int *utf8_char_length = &char_length;

	while (cur->p < cur->end) {
		c = *cur->p;
		*utf8_char_length = 1;

		if (is_whitespace(c))
			return 1;

		// Need to check for UTF-8 characters, which can be multiple
		// bytes long
		if (is_utf8_byte(c)) {
			if (!parse_utf8_char(cur, &c, utf8_char_length)) {
				if (!is_right_boundary(c)){
					// TODO: We should work towards
					// handling all UTF-8 characters.
					//printf("Invalid UTF-8 code point: %x\n", c);
				}
			}
		}

		if (is_right_boundary(c))
			return 1;

		// Need to use a variable character byte length for UTF-8 (2-4 bytes)
		if (cur->p + *utf8_char_length <= cur->end)
			cur->p += *utf8_char_length;
		else
			cur->p++;
	}

	return 1;
}

static void consume_whitespace_or_punctuation(struct cursor *cur)
{
	while (cur->p < cur->end) {
		if (!is_right_boundary(*cur->p))
			return;
		cur->p++;
	}
}

static int ndb_write_word_to_index(struct ndb_txn *txn, const char *word,
				   int word_len, int word_index,
				   uint64_t timestamp, uint64_t note_id)
{
	// cap to some reasonable key size
	unsigned char buffer[1024];
	int keysize, rc;
	MDB_val k, v;
	MDB_dbi text_db;

	// build our compressed text index key
	if (!ndb_make_text_search_key(buffer, sizeof(buffer), word_index,
				      word_len, word, timestamp, &keysize)) {
		// probably too big

		return 0;
	}

	k.mv_data = buffer;
	k.mv_size = keysize;

	v.mv_data = &note_id;
	v.mv_size = sizeof(note_id);

	text_db = txn->lmdb->dbs[NDB_DB_NOTE_TEXT];

	if ((rc = mdb_put(txn->mdb_txn, text_db, &k, &v, 0))) {
		ndb_debug("write note text index to db failed: %s\n",
				mdb_strerror(rc));
		return 0;
	}

	return 1;
}



// break a string into individual words for querying or for building the
// fulltext search index. This is callback based so we don't need to
// build up an intermediate structure
static int ndb_parse_words(struct cursor *cur, void *ctx, ndb_word_parser_fn fn)
{
	int word_len, words;
	const char *word;

	words = 0;

	while (cur->p < cur->end) {
		consume_whitespace_or_punctuation(cur);
		if (cur->p >= cur->end)
			break;
		word = (const char *)cur->p;

		if (!consume_until_boundary(cur))
			break;

		// start of word or end
		word_len = cur->p - (unsigned char *)word;
		if (word_len == 0 && cur->p >= cur->end)
			break;

		if (!fn(ctx, word, word_len, words))
			continue;

		words++;
	}

	return 1;
}

struct ndb_word_writer_ctx
{
	struct ndb_txn *txn;
	struct ndb_note *note;
	uint64_t note_id;
};

static int ndb_fulltext_word_writer(void *ctx,
		const char *word, int word_len, int words)
{
	struct ndb_word_writer_ctx *wctx = ctx;

	if (!ndb_write_word_to_index(wctx->txn, word, word_len, words,
				     wctx->note->created_at, wctx->note_id)) {
		// too big to write this one, just skip it
		ndb_debug("failed to write word '%.*s' to index\n", word_len, word);

		return 0;
	}

	//fprintf(stderr, "wrote '%.*s' to note text index\n", word_len, word);
	return 1;
}

static int ndb_write_note_fulltext_index(struct ndb_txn *txn,
					 struct ndb_note *note,
					 uint64_t note_id)
{
	struct cursor cur;
	unsigned char *content;
	struct ndb_str str;
	struct ndb_word_writer_ctx ctx;

	str = ndb_note_str(note, &note->content);
	// I don't think this should happen?
	if (unlikely(str.flag == NDB_PACKED_ID))
		return 0;

	content = (unsigned char *)str.str;

	make_cursor(content, content + note->content_length, &cur);

	ctx.txn = txn;
	ctx.note = note;
	ctx.note_id = note_id;

	ndb_parse_words(&cur, &ctx, ndb_fulltext_word_writer);

	return 1;
}

static int ndb_parse_search_words(void *ctx, const char *word_str, int word_len, int word_index)
{
	struct ndb_search_words *words = ctx;
	struct ndb_word *word;

	if (words->num_words + 1 > MAX_TEXT_SEARCH_WORDS)
		return 0;

	word = &words->words[words->num_words++];
	word->word = word_str;
	word->word_len = word_len;

	return 1;
}

static void ndb_keyed_text_search_results_init(struct ndb_keyed_text_search_results *r)
{
	r->num_words = 0;
}

static void ndb_search_words_init(struct ndb_search_words *words)
{
	words->num_words = 0;
}


static int prefix_count(const char *str1, int len1, const char *str2, int len2) {
	int i, count = 0;
	int min_len = len1 < len2 ? len1 : len2;

	for (i = 0; i < min_len; i++) {
		// case insensitive
		if (tolower(str1[i]) == tolower(str2[i]))
			count++;
		else
			break;
	}

	return count;
}


// This is called when scanning the full text search index. Scanning stops
// when we no longer have a prefix match for the word
static int ndb_text_search_next_word(MDB_cursor *cursor, MDB_cursor_op op,
	MDB_val *k, MDB_val *v, struct ndb_word *search_word,
	struct ndb_keyed_text_search_resultset *results)
{
	struct ndb_keyed_text_search_result *result;
	struct cursor key_cursor;

	make_cursor(k->mv_data, k->mv_data + k->mv_size, &key_cursor);

	// if we won't have enough to store the result, then bail
	if (results->num_results + 1 > MAX_RESULTS_PER_WORD)
		return 0;

	// place to store the results if we get a successful one. num_results
	// is incremented at the end if so
	result = &results->results[results->num_results];

	// When op is MDB_SET_RANGE, this initializes the search. Position
	// the cursor at the next key greater than or equal to the specified
	// key.
	//
	// Subsequent searches should use MDB_NEXT
	if (mdb_cursor_get(cursor, k, v, op))
		return 0;

	result->note_id = *((uint64_t*)v->mv_data);

	// On success, this could still be not related at all.
	// It could just be adjacent to the word. Let's check
	// if we have a matching prefix at least.

	// Before we unpack the entire key, let's quickly
	// unpack just the string to check the prefix. We don't
	// need to unpack the entire key if the prefix doesn't
	// match
	make_cursor(k->mv_data, k->mv_data + k->mv_size, &key_cursor);
	if (!ndb_unpack_text_search_key_string(&key_cursor,
					       &result->key.str,
					       &result->key.str_len)) {
		// this should never happen
		fprintf(stderr, "UNUSUAL: failed to unpack text search key string\n");
		return 0;
	}

	// Empty strings shouldn't happen but let's
	// protect against these cases
	if (result->key.str_len < 1)
		return 0;

	// make sure we at least have a matching prefix. exact
	// matches are nice but range searches allow us to
	// match prefixes as well. A single-char prefix is
	// suffient, but maybe we could up this in the future.
	// 
	// TODO: How are we handling utf-8 prefix matches like
	// japanese?
	//
	if (result->key.str[0] != tolower(search_word->word[0]))
		return 0;

	// count the number of prefix-matched characters. This will be used
	// for ranking search results
	result->prefix_chars = prefix_count(result->key.str,
					    result->key.str_len,
					    search_word->word,
					    search_word->word_len);

	// Unpack the remaining text search key, we will need this information
	// when building up our search results.
	if (!ndb_unpack_remaining_text_search_key(&key_cursor, &result->key)) {
		// This should never happen
		fprintf(stderr, "UNUSUAL: failed to unpack text search key\n");
		return 0;
	}

	// let's actually register this result now. the key has already been
	// fully unpacked
	results->num_results++;

	return 1;
}

static void ndb_print_text_search_key(struct ndb_text_search_key *key)
{
	fprintf(stderr, "K<'%.*s' %d %" PRIu64 ">", key->str_len, key->str,
						    key->word_index,
						    key->timestamp);
}

static void ndb_print_keyed_text_search_result(struct ndb_keyed_text_search_result *r)
{
	ndb_print_text_search_key(&r->key);
	fprintf(stderr, " note_id:%" PRIu64 "\n", r->note_id);
}

// convert the keyed results into actual results that include phrase results.
// This works by looping over all of the results
static int ndb_process_text_search_results(
		struct ndb_keyed_text_search_results *keyed_results,
		struct ndb_text_search_results *results)
{
	int i, j;
	struct ndb_keyed_text_search_resultset *resultset;
	struct ndb_keyed_text_search_result *result;

	// Phrase search. Find keyed adjacent keyed search results
	for (i = 0; i < keyed_results->num_words; i++) {
		resultset = &keyed_results->results[i];
		for (j = 0; j < resultset->num_results; j++) {
			result = &resultset->results[j];
			ndb_print_keyed_text_search_result(result);
		}
	}

	return 1;
}

static void ndb_keyed_text_search_resultset_init(
		struct ndb_keyed_text_search_resultset *resultset) {
	resultset->num_results = 0;
}

static void ndb_text_search_results_init(struct ndb_text_search_results *res)
{
	res->num_phrase_results = 0;
	res->num_other_results = 0;
}

int ndb_text_search(struct ndb_txn *txn, const char *query,
		    struct ndb_text_search_results *results)
{
	unsigned char buffer[1024];
	struct ndb_keyed_text_search_results keyed_results;
	struct ndb_keyed_text_search_resultset *keyed_resultset;
	struct ndb_search_words search_words;
	struct ndb_word *search_word;
	struct cursor cur;
	MDB_dbi text_db;
	MDB_cursor *cursor;
	MDB_val k, v;
	int i, j, keysize, num_words;
	MDB_cursor_op op = MDB_SET_RANGE;
	//int num_note_ids;

	ndb_keyed_text_search_results_init(&keyed_results);
	ndb_text_search_results_init(results);
	ndb_search_words_init(&search_words);
	
	//num_note_ids = 0;
	text_db = txn->lmdb->dbs[NDB_DB_NOTE_TEXT];
	make_cursor((unsigned char *)query, (unsigned char *)query + strlen(query), &cur);

	ndb_parse_words(&cur, &search_words, ndb_parse_search_words);

	if ((i = mdb_cursor_open(txn->mdb_txn, text_db, &cursor))) {
		fprintf(stderr, "nd_text_search: mdb_cursor_open failed, error %d\n", i);
		return 0;
	}

	fprintf(stderr, "search query: '%s'\n", query);

	// number of actual result words
	// for every search word up to a max of MAX_TEXT_SEARCH_WORDS words (8)

	num_words = min(search_words.num_words, MAX_TEXT_SEARCH_WORDS);

	for (i = 0; i < num_words; i++) {
		search_word = &search_words.words[i];

		// shouldn't happen but let's be defensive a bit
		if (search_word->word_len == 0)
			continue;

		// construct a packed fulltext search key using this word
		// this key doesn't contain any timestamp or index info,
		// so it should range match instead of exact match
		if (!ndb_make_text_search_key_low(buffer, sizeof(buffer),
						  search_word->word_len,
						  search_word->word,
						  &keysize)) {
			// word is too big to fit in 1024-sized key
			continue;
		}

		k.mv_data = buffer;
		k.mv_size = keysize;
		op = MDB_SET_RANGE;

		keyed_resultset = &keyed_results.results[keyed_results.num_words];
		ndb_keyed_text_search_resultset_init(keyed_resultset);

		// try to match the word as many times as possible before
		// moving on to the next word
		for (j = 0; j < MAX_RESULTS_PER_WORD; j++)
		{
			if (!ndb_text_search_next_word(cursor, op, &k, &v,
						       search_word,
						       keyed_resultset)) {
				break;
			}

			op = MDB_NEXT;
		}

		if (keyed_resultset->num_results > 0)
			keyed_results.num_words++;

		/*
		if ((note = ndb_get_note_by_key(txn, note_id, &len))) {
			fprintf(stderr, "found note: '%s' for query word '%.*s'\n",
				ndb_note_str(note, &note->content).str,
				word->word_len, word->word);
		}
		*/
	}

	// convert our keyed results into 
	ndb_process_text_search_results(&keyed_results, results);

	mdb_cursor_close(cursor);

	return 1;
}

static uint64_t ndb_write_note(struct ndb_txn *txn,
			       struct ndb_writer_note *note)
{
	int rc;
	uint64_t note_key;
	MDB_dbi note_db;
	MDB_val key, val;
	
	// get dbs
	note_db = txn->lmdb->dbs[NDB_DB_NOTE];

	// get new key
	note_key = ndb_get_last_key(txn->mdb_txn, note_db) + 1;

	// write note to event store
	key.mv_data = &note_key;
	key.mv_size = sizeof(note_key);
	val.mv_data = note->note;
	val.mv_size = note->note_len;

	if ((rc = mdb_put(txn->mdb_txn, note_db, &key, &val, 0))) {
		ndb_debug("write note to db failed: %s\n", mdb_strerror(rc));
		return 0;
	}

	// write id index key clustered with created_at
	if (!ndb_write_note_id_index(txn, note->note, note_key))
		return 0;

	// write note kind index
	if (!ndb_write_note_kind_index(txn, note->note, note_key))
		return 0;

	// only do fulltext index on kind1 notes
	if (note->note->kind == 1) {
		if (!ndb_write_note_fulltext_index(txn, note->note, note_key))
			return 0;
	}

	if (note->note->kind == 7) {
		ndb_write_reaction_stats(txn, note->note);
	}

	return note_key;
}

// only to be called from the writer thread
static void ndb_write_version(struct ndb_txn *txn, uint64_t version)
{
	int rc;
	MDB_val key, val;
	uint64_t version_key;

	version_key = NDB_META_KEY_VERSION;
	
	key.mv_data = &version_key;
	key.mv_size = sizeof(version_key);
	val.mv_data = &version;
	val.mv_size = sizeof(version);

	if ((rc = mdb_put(txn->mdb_txn, txn->lmdb->dbs[NDB_DB_NDB_META], &key, &val, 0))) {
		ndb_debug("write version to ndb_meta failed: %s\n",
				mdb_strerror(rc));
		return;
	}

	//fprintf(stderr, "writing version %" PRIu64 "\n", version);
}

static void *ndb_writer_thread(void *data)
{
	struct ndb_writer *writer = data;
	struct ndb_writer_msg msgs[THREAD_QUEUE_BATCH], *msg;
	int i, popped, done, any_note;
	uint64_t note_nkey;
	MDB_txn *mdb_txn = NULL;
	struct ndb_txn txn;
	ndb_txn_from_mdb(&txn, writer->lmdb, mdb_txn);

	done = 0;
	while (!done) {
		txn.mdb_txn = NULL;
		popped = prot_queue_pop_all(&writer->inbox, msgs, THREAD_QUEUE_BATCH);
		//ndb_debug("writer popped %d items\n", popped);

		any_note = 0;
		for (i = 0 ; i < popped; i++) {
			msg = &msgs[i];
			switch (msg->type) {
			case NDB_WRITER_NOTE: any_note = 1; break;
			case NDB_WRITER_PROFILE: any_note = 1; break;
			case NDB_WRITER_DBMETA: any_note = 1; break;
			case NDB_WRITER_PROFILE_LAST_FETCH: any_note = 1; break;
			case NDB_WRITER_QUIT: break;
			}
		}

		if (any_note && mdb_txn_begin(txn.lmdb->env, NULL, 0, (MDB_txn **)&txn.mdb_txn))
		{
			fprintf(stderr, "writer thread txn_begin failed");
			// should definitely not happen unless DB is full
			// or something ?
			assert(false);
		}

		for (i = 0; i < popped; i++) {
			msg = &msgs[i];

			switch (msg->type) {
			case NDB_WRITER_QUIT:
				// quits are handled before this
				done = 1;
				continue;
			case NDB_WRITER_PROFILE:
				note_nkey = 
					ndb_write_note(&txn, &msg->note);
				if (msg->profile.record.builder) {
					// only write if parsing didn't fail
					ndb_write_profile(&txn, &msg->profile,
							  note_nkey);
				}
				break;
			case NDB_WRITER_NOTE:
				ndb_write_note(&txn, &msg->note);
				//printf("wrote note ");
				//print_hex(msg->note.note->id, 32);
				//printf("\n");
				break;
			case NDB_WRITER_DBMETA:
				ndb_write_version(&txn, msg->ndb_meta.version);
				break;
			case NDB_WRITER_PROFILE_LAST_FETCH:
				ndb_writer_last_profile_fetch(&txn,
						msg->last_fetch.pubkey,
						msg->last_fetch.fetched_at
						);
				break;
			}
		}

		// commit writes
		if (any_note && !ndb_end_query(&txn)) {
			fprintf(stderr, "writer thread txn commit failed");
			assert(false);
		}

		// free notes
		for (i = 0; i < popped; i++) {
			msg = &msgs[i];
			if (msg->type == NDB_WRITER_NOTE)
				free(msg->note.note);
			else if (msg->type == NDB_WRITER_PROFILE) {
				free(msg->profile.note.note);
				ndb_profile_record_builder_free(&msg->profile.record);
			}
		}
	}

	ndb_debug("quitting writer thread\n");
	return NULL;
}

static void *ndb_ingester_thread(void *data)
{
	secp256k1_context *ctx;
	struct thread *thread = data;
	struct ndb_ingester *ingester = (struct ndb_ingester *)thread->ctx;
	struct ndb_lmdb *lmdb = ingester->writer->lmdb;
	struct ndb_ingester_msg msgs[THREAD_QUEUE_BATCH], *msg;
	struct ndb_writer_msg outs[THREAD_QUEUE_BATCH], *out;
	int i, to_write, popped, done, any_event;
	MDB_txn *read_txn = NULL;
	int rc;

	ctx = secp256k1_context_create(SECP256K1_CONTEXT_VERIFY);
	ndb_debug("started ingester thread\n");

	done = 0;
	while (!done) {
		to_write = 0;
		any_event = 0;

		popped = prot_queue_pop_all(&thread->inbox, msgs, THREAD_QUEUE_BATCH);
		//ndb_debug("ingester popped %d items\n", popped);

		for (i = 0; i < popped; i++) {
			msg = &msgs[i];
			if (msg->type == NDB_INGEST_EVENT) {
				any_event = 1;
				break;
			}
		}

		if (any_event && (rc = mdb_txn_begin(lmdb->env, NULL, MDB_RDONLY, &read_txn))) {
			// this is bad
			fprintf(stderr, "UNUSUAL ndb_ingester: mdb_txn_begin failed: '%s'\n",
					mdb_strerror(rc));
			continue;
		}

		for (i = 0; i < popped; i++) {
			msg = &msgs[i];
			switch (msg->type) {
			case NDB_INGEST_QUIT:
				done = 1;
				break;

			case NDB_INGEST_EVENT:
				out = &outs[to_write];
				if (ndb_ingester_process_event(ctx, ingester,
							       &msg->event, out,
							       read_txn)) {
					to_write++;
				}
			}
		}

		if (any_event)
			mdb_txn_abort(read_txn);

		if (to_write > 0) {
			//ndb_debug("pushing %d events to write queue\n", to_write); 
			if (!ndb_writer_queue_msgs(ingester->writer, outs, to_write)) {
				ndb_debug("failed pushing %d events to write queue\n", to_write); 
			}
		}
	}

	ndb_debug("quitting ingester thread\n");
	secp256k1_context_destroy(ctx);
	return NULL;
}


static int ndb_writer_init(struct ndb_writer *writer, struct ndb_lmdb *lmdb)
{
	writer->lmdb = lmdb;
	writer->queue_buflen = sizeof(struct ndb_writer_msg) * DEFAULT_QUEUE_SIZE;
	writer->queue_buf = malloc(writer->queue_buflen);
	if (writer->queue_buf == NULL) {
		fprintf(stderr, "ndb: failed to allocate space for writer queue");
		return 0;
	}

	// init the writer queue.
	prot_queue_init(&writer->inbox, writer->queue_buf,
			writer->queue_buflen, sizeof(struct ndb_writer_msg));

	// spin up the writer thread
	if (pthread_create(&writer->thread_id, NULL, ndb_writer_thread, writer))
	{
		fprintf(stderr, "ndb writer thread failed to create\n");
		return 0;
	}
	
	return 1;
}

// initialize the ingester queue and then spawn the thread
static int ndb_ingester_init(struct ndb_ingester *ingester,
			     struct ndb_writer *writer, int num_threads)
{
	int elem_size, num_elems;
	static struct ndb_ingester_msg quit_msg = { .type = NDB_INGEST_QUIT };

	// TODO: configurable queue sizes
	elem_size = sizeof(struct ndb_ingester_msg);
	num_elems = DEFAULT_QUEUE_SIZE;

	ingester->writer = writer;

	if (!threadpool_init(&ingester->tp, num_threads, elem_size, num_elems,
			     &quit_msg, ingester, ndb_ingester_thread))
	{
		fprintf(stderr, "ndb ingester threadpool failed to init\n");
		return 0;
	}

	return 1;
}

static int ndb_writer_destroy(struct ndb_writer *writer)
{
	struct ndb_writer_msg msg;

	// kill thread
	msg.type = NDB_WRITER_QUIT;
	if (!prot_queue_push(&writer->inbox, &msg)) {
		// queue is too full to push quit message. just kill it.
		pthread_exit(&writer->thread_id);
	} else {
		pthread_join(writer->thread_id, NULL);
	}

	// cleanup
	prot_queue_destroy(&writer->inbox);

	free(writer->queue_buf);

	return 1;
}

static int ndb_ingester_destroy(struct ndb_ingester *ingester)
{
	threadpool_destroy(&ingester->tp);
	return 1;
}

static int ndb_ingester_queue_event(struct ndb_ingester *ingester,
				    char *json, unsigned len, unsigned client)
{
	struct ndb_ingester_msg msg;
	msg.type = NDB_INGEST_EVENT;

	msg.event.json = json;
	msg.event.len = len;
	msg.event.client = client;

	return threadpool_dispatch(&ingester->tp, &msg);
}

static int ndb_init_lmdb(const char *filename, struct ndb_lmdb *lmdb, size_t mapsize)
{
	int rc;
	MDB_txn *txn;

	if ((rc = mdb_env_create(&lmdb->env))) {
		fprintf(stderr, "mdb_env_create failed, error %d\n", rc);
		return 0;
	}

	if ((rc = mdb_env_set_mapsize(lmdb->env, mapsize))) {
		fprintf(stderr, "mdb_env_set_mapsize failed, error %d\n", rc);
		return 0;
	}

	if ((rc = mdb_env_set_maxdbs(lmdb->env, NDB_DBS))) {
		fprintf(stderr, "mdb_env_set_maxdbs failed, error %d\n", rc);
		return 0;
	}

	if ((rc = mdb_env_open(lmdb->env, filename, 0, 0664))) {
		fprintf(stderr, "mdb_env_open failed, error %d\n", rc);
		return 0;
	}

	// Initialize DBs
	if ((rc = mdb_txn_begin(lmdb->env, NULL, 0, &txn))) {
		fprintf(stderr, "mdb_txn_begin failed, error %d\n", rc);
		return 0;
	}

	// note flatbuffer db
	if ((rc = mdb_dbi_open(txn, "note", MDB_CREATE | MDB_INTEGERKEY, &lmdb->dbs[NDB_DB_NOTE]))) {
		fprintf(stderr, "mdb_dbi_open event failed, error %d\n", rc);
		return 0;
	}

	// note metadata db
	if ((rc = mdb_dbi_open(txn, "meta", MDB_CREATE, &lmdb->dbs[NDB_DB_META]))) {
		fprintf(stderr, "mdb_dbi_open meta failed, error %d\n", rc);
		return 0;
	}

	// profile flatbuffer db
	if ((rc = mdb_dbi_open(txn, "profile", MDB_CREATE | MDB_INTEGERKEY, &lmdb->dbs[NDB_DB_PROFILE]))) {
		fprintf(stderr, "mdb_dbi_open profile failed, error %d\n", rc);
		return 0;
	}

	// profile search db
	if ((rc = mdb_dbi_open(txn, "profile_search", MDB_CREATE, &lmdb->dbs[NDB_DB_PROFILE_SEARCH]))) {
		fprintf(stderr, "mdb_dbi_open profile_search failed, error %d\n", rc);
		return 0;
	}
	mdb_set_compare(txn, lmdb->dbs[NDB_DB_PROFILE_SEARCH], ndb_search_key_cmp);

	// ndb metadata (db version, etc)
	if ((rc = mdb_dbi_open(txn, "ndb_meta", MDB_CREATE | MDB_INTEGERKEY, &lmdb->dbs[NDB_DB_NDB_META]))) {
		fprintf(stderr, "mdb_dbi_open ndb_meta failed, error %d\n", rc);
		return 0;
	}

	// profile last fetches
	if ((rc = mdb_dbi_open(txn, "profile_last_fetch", MDB_CREATE, &lmdb->dbs[NDB_DB_PROFILE_LAST_FETCH]))) {
		fprintf(stderr, "mdb_dbi_open profile last fetch, error %d\n", rc);
		return 0;
	}

	// id+ts index flags
	unsigned int tsid_flags = MDB_CREATE | MDB_DUPSORT | MDB_DUPFIXED;

	// index dbs
	if ((rc = mdb_dbi_open(txn, "note_id", tsid_flags, &lmdb->dbs[NDB_DB_NOTE_ID]))) {
		fprintf(stderr, "mdb_dbi_open id failed: %s\n", mdb_strerror(rc));
		return 0;
	}
	mdb_set_compare(txn, lmdb->dbs[NDB_DB_NOTE_ID], ndb_tsid_compare);

	if ((rc = mdb_dbi_open(txn, "profile_pk", tsid_flags, &lmdb->dbs[NDB_DB_PROFILE_PK]))) {
		fprintf(stderr, "mdb_dbi_open id failed: %s\n", mdb_strerror(rc));
		return 0;
	}
	mdb_set_compare(txn, lmdb->dbs[NDB_DB_PROFILE_PK], ndb_tsid_compare);

	if ((rc = mdb_dbi_open(txn, "note_kind", tsid_flags, &lmdb->dbs[NDB_DB_NOTE_KIND]))) {
		fprintf(stderr, "mdb_dbi_open id failed: %s\n", mdb_strerror(rc));
		return 0;
	}
	mdb_set_compare(txn, lmdb->dbs[NDB_DB_NOTE_KIND], ndb_u64_tsid_compare);

	if ((rc = mdb_dbi_open(txn, "note_text", MDB_CREATE | MDB_DUPSORT,
			       &lmdb->dbs[NDB_DB_NOTE_TEXT]))) {
		fprintf(stderr, "mdb_dbi_open id failed: %s\n", mdb_strerror(rc));
		return 0;
	}
	mdb_set_compare(txn, lmdb->dbs[NDB_DB_NOTE_TEXT], ndb_text_search_key_compare);

	// Commit the transaction
	if ((rc = mdb_txn_commit(txn))) {
		fprintf(stderr, "mdb_txn_commit failed, error %d\n", rc);
		return 0;
	}

	return 1;
}

static int ndb_queue_write_version(struct ndb *ndb, uint64_t version)
{
	struct ndb_writer_msg msg;
	msg.type = NDB_WRITER_DBMETA;
	msg.ndb_meta.version = version;
	return ndb_writer_queue_msg(&ndb->writer, &msg);
}

static int ndb_run_migrations(struct ndb *ndb)
{
	uint64_t version, latest_version, i;
	
	latest_version = sizeof(MIGRATIONS) / sizeof(MIGRATIONS[0]);

	if ((version = ndb_db_version(ndb)) == -1) {
		ndb_debug("run_migrations: no version found, assuming new db\n");
		version = latest_version;

		// no version found. fresh db?
		if (!ndb_queue_write_version(ndb, version)) {
			fprintf(stderr, "run_migrations: failed writing db version");
			return 0;
		}

		return 1;
	} else {
		ndb_debug("ndb: version %" PRIu64 " found\n", version);
	}

	if (version < latest_version)
		ndb_debug("nostrdb: migrating v%d -> v%d\n",
				(int)version, (int)latest_version);

	for (i = version; i < latest_version; i++) {
		if (!MIGRATIONS[i].fn(ndb)) {
			fprintf(stderr, "run_migrations: migration v%d -> v%d failed\n", (int)i, (int)(i+1));
			return 0;
		}

		if (!ndb_queue_write_version(ndb, i+1)) {
			fprintf(stderr, "run_migrations: failed writing db version");
			return 0;
		}

		version = i+1;
	}

	ndb->version = version;

	return 1;
}

int ndb_init(struct ndb **pndb, const char *filename, size_t mapsize, int ingester_threads, int flags)
{
	struct ndb *ndb;
	//MDB_dbi ind_id; // TODO: ind_pk, etc

	ndb = *pndb = calloc(1, sizeof(struct ndb));
	if (ndb == NULL) {
		fprintf(stderr, "ndb_init: malloc failed\n");
		return 0;
	}

	if (!ndb_init_lmdb(filename, &ndb->lmdb, mapsize))
		return 0;

	if (!ndb_writer_init(&ndb->writer, &ndb->lmdb)) {
		fprintf(stderr, "ndb_writer_init failed\n");
		return 0;
	}

	if (!ndb_ingester_init(&ndb->ingester, &ndb->writer, ingester_threads)) {
		fprintf(stderr, "failed to initialize %d ingester thread(s)\n",
				ingester_threads);
		return 0;
	}

	if (!ndb_flag_set(flags, NDB_FLAG_NOMIGRATE) && !ndb_run_migrations(ndb)) {
		fprintf(stderr, "failed to run migrations\n");
		return 0;
	}

	// Initialize LMDB environment and spin up threads
	return 1;
}

void ndb_destroy(struct ndb *ndb)
{
	if (ndb == NULL)
		return;

	// ingester depends on writer and must be destroyed first
	ndb_ingester_destroy(&ndb->ingester);
	ndb_writer_destroy(&ndb->writer);

	mdb_env_close(ndb->lmdb.env);

	free(ndb);
}

// Process a nostr event from a client
//
// ie: ["EVENT", {"content":"..."} ...]
//
// The client-sent variation of ndb_process_event
int ndb_process_client_event(struct ndb *ndb, const char *json, int len)
{
	// Since we need to return as soon as possible, and we're not
	// making any assumptions about the lifetime of the string, we
	// definitely need to copy the json here. In the future once we
	// have our thread that manages a websocket connection, we can
	// avoid the copy and just use the buffer we get from that
	// thread.
	char *json_copy = strdupn(json, len);
	if (json_copy == NULL)
		return 0;

	return ndb_ingester_queue_event(&ndb->ingester, json_copy, len, 1);
}

// Process anostr event from a relay,
//
// ie: ["EVENT", "subid", {"content":"..."}...]
// 
// This function returns as soon as possible, first copying the passed
// json and then queueing it up for processing. Worker threads then take
// the json and process it.
//
// Processing:
//
// 1. The event is parsed into ndb_notes and the signature is validated
// 2. A quick lookup is made on the database to see if we already have
//    the note id, if we do we don't need to waste time on json parsing
//    or note validation.
// 3. Once validation is done we pass it to the writer queue for writing
//    to LMDB.
//
int ndb_process_event(struct ndb *ndb, const char *json, int json_len)
{
	// Since we need to return as soon as possible, and we're not
	// making any assumptions about the lifetime of the string, we
	// definitely need to copy the json here. In the future once we
	// have our thread that manages a websocket connection, we can
	// avoid the copy and just use the buffer we get from that
	// thread.
	char *json_copy = strdupn(json, json_len);
	if (json_copy == NULL)
		return 0;

	return ndb_ingester_queue_event(&ndb->ingester, json_copy, json_len, 0);
}


int _ndb_process_events(struct ndb *ndb, const char *ldjson, size_t json_len, int client)
{
	const char *start, *end, *very_end;
	start = ldjson;
	end = start + json_len;
	very_end = ldjson + json_len;
	int (* process)(struct ndb *, const char *, int);
#if DEBUG
	int processed = 0;
#endif
	process = client ? ndb_process_client_event : ndb_process_event;

	while ((end = fast_strchr(start, '\n', very_end - start))) {
		//printf("processing '%.*s'\n", (int)(end-start), start);
		if (!process(ndb, start, end - start)) {
			ndb_debug("ndb_process_client_event failed\n");
			return 0;
		}
		start = end + 1;
#if DEBUG
		processed++;
#endif
	}

#if DEBUG
	ndb_debug("ndb_process_events: processed %d events\n", processed);
#endif

	return 1;
}

int ndb_process_client_events(struct ndb *ndb, const char *ldjson, size_t json_len)
{
	return _ndb_process_events(ndb, ldjson, json_len, 1);
}

int ndb_process_events(struct ndb *ndb, const char *ldjson, size_t json_len)
{
	return _ndb_process_events(ndb, ldjson, json_len, 0);
}

static inline int cursor_push_tag(struct cursor *cur, struct ndb_tag *tag)
{
	return cursor_push_u16(cur, tag->count);
}

int ndb_builder_init(struct ndb_builder *builder, unsigned char *buf,
		     int bufsize)
{
	struct ndb_note *note;
	int half, size, str_indices_size;

	// come on bruh
	if (bufsize < sizeof(struct ndb_note) * 2)
		return 0;

	str_indices_size = bufsize / 32;
	size = bufsize - str_indices_size;
	half = size / 2;

	//debug("size %d half %d str_indices %d\n", size, half, str_indices_size);

	// make a safe cursor of our available memory
	make_cursor(buf, buf + bufsize, &builder->mem);

	note = builder->note = (struct ndb_note *)buf;

	// take slices of the memory into subcursors
	if (!(cursor_slice(&builder->mem, &builder->note_cur, half) &&
	      cursor_slice(&builder->mem, &builder->strings, half) &&
	      cursor_slice(&builder->mem, &builder->str_indices, str_indices_size))) {
		return 0;
	}

	memset(note, 0, sizeof(*note));
	builder->note_cur.p += sizeof(*note);

	note->strings = builder->strings.start - buf;
	note->version = 1;

	return 1;
}



static inline int ndb_json_parser_init(struct ndb_json_parser *p,
				       const char *json, int json_len,
				       unsigned char *buf, int bufsize)
{
	int half = bufsize / 2;

	unsigned char *tok_start = buf + half;
	unsigned char *tok_end = buf + bufsize;

	p->toks = (jsmntok_t*)tok_start;
	p->toks_end = (jsmntok_t*)tok_end;
	p->num_tokens = 0;
	p->json = json;
	p->json_len = json_len;

	// ndb_builder gets the first half of the buffer, and jsmn gets the
	// second half. I like this way of alloating memory (without actually
	// dynamically allocating memory). You get one big chunk upfront and
	// then submodules can recursively subdivide it. Maybe you could do
	// something even more clever like golden-ratio style subdivision where
	// the more important stuff gets a larger chunk and then it spirals
	// downward into smaller chunks. Thanks for coming to my TED talk.

	if (!ndb_builder_init(&p->builder, buf, half))
		return 0;

	jsmn_init(&p->json_parser);

	return 1;
}

static inline int ndb_json_parser_parse(struct ndb_json_parser *p,
					struct ndb_id_cb *cb)
{
	jsmntok_t *tok;
	int cap = ((unsigned char *)p->toks_end - (unsigned char*)p->toks)/sizeof(*p->toks);
	int res =
		jsmn_parse(&p->json_parser, p->json, p->json_len, p->toks, cap, cb != NULL);

	// got an ID!
	if (res == -42) {
		tok = &p->toks[p->json_parser.toknext-1];

		switch (cb->fn(cb->data, p->json + tok->start)) {
		case NDB_IDRES_CONT:
			res = jsmn_parse(&p->json_parser, p->json, p->json_len,
					 p->toks, cap, 0);
			break;
		case NDB_IDRES_STOP:
			return -42;
		}
	} else if (res == 0) {
		return 0;
	}

	p->num_tokens = res;
	p->i = 0;

	return 1;
}

static inline int toksize(jsmntok_t *tok)
{
	return tok->end - tok->start;
}



static int cursor_push_unescaped_char(struct cursor *cur, char c1, char c2)
{
	switch (c2) {
	case 't':  return cursor_push_byte(cur, '\t');
	case 'n':  return cursor_push_byte(cur, '\n');
	case 'r':  return cursor_push_byte(cur, '\r');
	case 'b':  return cursor_push_byte(cur, '\b');
	case 'f':  return cursor_push_byte(cur, '\f');
	case '\\': return cursor_push_byte(cur, '\\');
	case '/':  return cursor_push_byte(cur, '/');
	case '"':  return cursor_push_byte(cur, '"');
	case 'u':
		// these aren't handled yet
		return 0;
	default:
		return cursor_push_byte(cur, c1) && cursor_push_byte(cur, c2);
	}
}

static int cursor_push_escaped_char(struct cursor *cur, char c)
{
        switch (c) {
        case '"':  return cursor_push_str(cur, "\\\"");
        case '\\': return cursor_push_str(cur, "\\\\");
        case '\b': return cursor_push_str(cur, "\\b");
        case '\f': return cursor_push_str(cur, "\\f");
        case '\n': return cursor_push_str(cur, "\\n");
        case '\r': return cursor_push_str(cur, "\\r");
        case '\t': return cursor_push_str(cur, "\\t");
        // TODO: \u hex hex hex hex
        }
        return cursor_push_byte(cur, c);
}

static int cursor_push_hex_str(struct cursor *cur, unsigned char *buf, int len)
{
	int i;

	if (len % 2 != 0)
		return 0;

        if (!cursor_push_byte(cur, '"'))
                return 0;

	for (i = 0; i < len; i++) {
		unsigned int c = ((const unsigned char *)buf)[i];
		if (!cursor_push_byte(cur, hexchar(c >> 4)))
			return 0;
		if (!cursor_push_byte(cur, hexchar(c & 0xF)))
			return 0;
	}

        if (!cursor_push_byte(cur, '"'))
                return 0;

	return 1;
}

static int cursor_push_jsonstr(struct cursor *cur, const char *str)
{
	int i;
        int len;

	len = strlen(str);

        if (!cursor_push_byte(cur, '"'))
                return 0;

        for (i = 0; i < len; i++) {
                if (!cursor_push_escaped_char(cur, str[i]))
                        return 0;
        }

        if (!cursor_push_byte(cur, '"'))
                return 0;

        return 1;
}


static inline int cursor_push_json_tag_str(struct cursor *cur, struct ndb_str str)
{
	if (str.flag == NDB_PACKED_ID)
		return cursor_push_hex_str(cur, str.id, 32);

	return cursor_push_jsonstr(cur, str.str);
}

static int cursor_push_json_tag(struct cursor *cur, struct ndb_note *note,
				struct ndb_tag *tag)
{
        int i;

        if (!cursor_push_byte(cur, '['))
                return 0;

        for (i = 0; i < tag->count; i++) {
                if (!cursor_push_json_tag_str(cur, ndb_note_str(note, &tag->strs[i])))
                        return 0;
                if (i != tag->count-1 && !cursor_push_byte(cur, ','))
			return 0;
        }

        return cursor_push_byte(cur, ']');
}

static int cursor_push_json_tags(struct cursor *cur, struct ndb_note *note)
{
	int i;
	struct ndb_iterator iter, *it = &iter;
	ndb_tags_iterate_start(note, it);

        if (!cursor_push_byte(cur, '['))
                return 0;

	i = 0;
	while (ndb_tags_iterate_next(it)) {
		if (!cursor_push_json_tag(cur, note, it->tag))
			return 0;
                if (i != note->tags.count-1 && !cursor_push_str(cur, ","))
			return 0;
		i++;
	}

        if (!cursor_push_byte(cur, ']'))
                return 0;

	return 1;
}

static int ndb_event_commitment(struct ndb_note *ev, unsigned char *buf, int buflen)
{
	char timebuf[16] = {0};
	char kindbuf[16] = {0};
	char pubkey[65];
	struct cursor cur;
	int ok;

	if (!hex_encode(ev->pubkey, sizeof(ev->pubkey), pubkey, sizeof(pubkey)))
		return 0;

	make_cursor(buf, buf + buflen, &cur);

	// TODO: update in 2106 ...
	snprintf(timebuf, sizeof(timebuf), "%d", (uint32_t)ev->created_at);
	snprintf(kindbuf, sizeof(kindbuf), "%d", ev->kind);

	ok =
		cursor_push_str(&cur, "[0,\"") &&
		cursor_push_str(&cur, pubkey) &&
		cursor_push_str(&cur, "\",") &&
		cursor_push_str(&cur, timebuf) &&
		cursor_push_str(&cur, ",") &&
		cursor_push_str(&cur, kindbuf) &&
		cursor_push_str(&cur, ",") &&
		cursor_push_json_tags(&cur, ev) &&
		cursor_push_str(&cur, ",") &&
		cursor_push_jsonstr(&cur, ndb_note_str(ev, &ev->content).str) &&
		cursor_push_str(&cur, "]");

	if (!ok)
		return 0;

	return cur.p - cur.start;
}

int ndb_calculate_id(struct ndb_note *note, unsigned char *buf, int buflen) {
	int len;

	if (!(len = ndb_event_commitment(note, buf, buflen)))
		return 0;

	//fprintf(stderr, "%.*s\n", len, buf);

	sha256((struct sha256*)note->id, buf, len);

	return 1;
}

int ndb_sign_id(struct ndb_keypair *keypair, unsigned char id[32],
		unsigned char sig[64])
{
	unsigned char aux[32];
	secp256k1_keypair *pair = (secp256k1_keypair*) keypair->pair;

	if (!fill_random(aux, sizeof(aux)))
		return 0;

	secp256k1_context *ctx =
		secp256k1_context_create(SECP256K1_CONTEXT_NONE);

	return secp256k1_schnorrsig_sign32(ctx, sig, id, pair, aux);
}

int ndb_create_keypair(struct ndb_keypair *kp)
{
	secp256k1_keypair *keypair = (secp256k1_keypair*)kp->pair;
	secp256k1_xonly_pubkey pubkey;

	secp256k1_context *ctx =
		secp256k1_context_create(SECP256K1_CONTEXT_NONE);;

	/* Try to create a keypair with a valid context, it should only
	 * fail if the secret key is zero or out of range. */
	if (!secp256k1_keypair_create(ctx, keypair, kp->secret))
		return 0;

	if (!secp256k1_keypair_xonly_pub(ctx, &pubkey, NULL, keypair))
		return 0;

	/* Serialize the public key. Should always return 1 for a valid public key. */
	return secp256k1_xonly_pubkey_serialize(ctx, kp->pubkey, &pubkey);
}

int ndb_decode_key(const char *secstr, struct ndb_keypair *keypair)
{
	if (!hex_decode(secstr, strlen(secstr), keypair->secret, 32)) {
		fprintf(stderr, "could not hex decode secret key\n");
		return 0;
	}

	return ndb_create_keypair(keypair);
}

int ndb_builder_finalize(struct ndb_builder *builder, struct ndb_note **note,
			 struct ndb_keypair *keypair)
{
	int strings_len = builder->strings.p - builder->strings.start;
	unsigned char *note_end = builder->note_cur.p + strings_len;
	int total_size = note_end - builder->note_cur.start;

	// move the strings buffer next to the end of our ndb_note
	memmove(builder->note_cur.p, builder->strings.start, strings_len);

	// set the strings location
	builder->note->strings = builder->note_cur.p - builder->note_cur.start;

	// record the total size
	//builder->note->size = total_size;

	*note = builder->note;

	// generate id and sign if we're building this manually
	if (keypair) {
		// use the remaining memory for building our id buffer
		unsigned char *end   = builder->mem.end;
		unsigned char *start = (unsigned char*)(*note) + total_size;

		ndb_builder_set_pubkey(builder, keypair->pubkey);

		if (!ndb_calculate_id(builder->note, start, end - start))
			return 0;

		if (!ndb_sign_id(keypair, (*note)->id, (*note)->sig))
			return 0;
	}

	// make sure we're aligned as a whole
	total_size = (total_size + 7) & ~7;
	assert((total_size % 8) == 0);
	return total_size;
}

struct ndb_note * ndb_builder_note(struct ndb_builder *builder)
{
	return builder->note;
}

/// find an existing string via str_indices. these indices only exist in the
/// builder phase just for this purpose.
static inline int ndb_builder_find_str(struct ndb_builder *builder,
				       const char *str, int len,
				       union ndb_packed_str *pstr)
{
	// find existing matching string to avoid duplicate strings
	int indices = cursor_count(&builder->str_indices, sizeof(uint32_t));
	for (int i = 0; i < indices; i++) {
		uint32_t index = ((uint32_t*)builder->str_indices.start)[i];
		const char *some_str = (const char*)builder->strings.start + index;

		if (!memcmp(some_str, str, len)) {
			// found an existing matching str, use that index
			*pstr = ndb_offset_str(index);
			return 1;
		}
	}

	return 0;
}

static int ndb_builder_push_str(struct ndb_builder *builder, const char *str,
				int len, union ndb_packed_str *pstr)
{
	uint32_t loc;

	// no string found, push a new one
	loc = builder->strings.p - builder->strings.start;
	if (!(cursor_push(&builder->strings, (unsigned char*)str, len) &&
	      cursor_push_byte(&builder->strings, '\0'))) {
		return 0;
	}

	*pstr = ndb_offset_str(loc);

	// record in builder indices. ignore return value, if we can't cache it
	// then whatever
	cursor_push_u32(&builder->str_indices, loc);

	return 1;
}

static int ndb_builder_push_packed_id(struct ndb_builder *builder,
				      unsigned char *id,
				      union ndb_packed_str *pstr)
{
	// Don't both find id duplicates. very rarely are they duplicated
	// and it slows things down quite a bit. If we really care about this
	// We can switch to a hash table.
	//if (ndb_builder_find_str(builder, (const char*)id, 32, pstr)) {
	//	pstr->packed.flag = NDB_PACKED_ID;
	//	return 1;
	//}

	if (ndb_builder_push_str(builder, (const char*)id, 32, pstr)) {
		pstr->packed.flag = NDB_PACKED_ID;
		return 1;
	}

	return 0;
}


/// Check for small strings to pack
static inline int ndb_builder_try_compact_str(struct ndb_builder *builder,
					      const char *str, int len,
					      union ndb_packed_str *pstr,
					      int pack_ids)
{
	unsigned char id_buf[32];

	if (len == 0) {
		*pstr = ndb_char_to_packed_str(0);
		return 1;
	} else if (len == 1) {
		*pstr = ndb_char_to_packed_str(str[0]);
		return 1;
	} else if (len == 2) {
		*pstr = ndb_chars_to_packed_str(str[0], str[1]);
		return 1;
	} else if (pack_ids && len == 64 && hex_decode(str, 64, id_buf, 32)) {
		return ndb_builder_push_packed_id(builder, id_buf, pstr);
	}

	return 0;
}


static int ndb_builder_push_unpacked_str(struct ndb_builder *builder,
					 const char *str, int len,
					 union ndb_packed_str *pstr)
{
	if (ndb_builder_find_str(builder, str, len, pstr))
		return 1;

	return ndb_builder_push_str(builder, str, len, pstr);
}

int ndb_builder_make_str(struct ndb_builder *builder, const char *str, int len,
			 union ndb_packed_str *pstr, int pack_ids)
{
	if (ndb_builder_try_compact_str(builder, str, len, pstr, pack_ids))
		return 1;

	return ndb_builder_push_unpacked_str(builder, str, len, pstr);
}

int ndb_builder_set_content(struct ndb_builder *builder, const char *content,
			    int len)
{
	int pack_ids = 0;
	builder->note->content_length = len;
	return ndb_builder_make_str(builder, content, len,
				    &builder->note->content, pack_ids);
}


static inline int jsoneq(const char *json, jsmntok_t *tok, int tok_len,
			 const char *s)
{
	if (tok->type == JSMN_STRING && (int)strlen(s) == tok_len &&
	    memcmp(json + tok->start, s, tok_len) == 0) {
		return 1;
	}
	return 0;
}

static int ndb_builder_finalize_tag(struct ndb_builder *builder,
				    union ndb_packed_str offset)
{
	if (!cursor_push_u32(&builder->note_cur, offset.offset))
		return 0;
	builder->current_tag->count++;
	return 1;
}

/// Unescape and push json strings
static int ndb_builder_make_json_str(struct ndb_builder *builder,
				     const char *str, int len,
				     union ndb_packed_str *pstr,
				     int *written, int pack_ids)
{
	// let's not care about de-duping these. we should just unescape
	// in-place directly into the strings table. 
	if (written)
		*written = len;

	const char *p, *end, *start;
	unsigned char *builder_start;

	// always try compact strings first
	if (ndb_builder_try_compact_str(builder, str, len, pstr, pack_ids))
		return 1;

	end = str + len;
	start = str; // Initialize start to the beginning of the string

	*pstr = ndb_offset_str(builder->strings.p - builder->strings.start);
	builder_start = builder->strings.p;

	for (p = str; p < end; p++) {
		if (*p == '\\' && p+1 < end) {
			// Push the chunk of unescaped characters before this escape sequence
			if (start < p && !cursor_push(&builder->strings,
						(unsigned char *)start,
						p - start)) {
				return 0;
			}

			if (!cursor_push_unescaped_char(&builder->strings, *p, *(p+1)))
				return 0;

			p++; // Skip the character following the backslash
			start = p + 1; // Update the start pointer to the next character
		}
	}

	// Handle the last chunk after the last escape sequence (or if there are no escape sequences at all)
	if (start < p && !cursor_push(&builder->strings, (unsigned char *)start,
				      p - start)) {
		return 0;
	}

	if (written)
		*written = builder->strings.p - builder_start;

	// TODO: dedupe these!?
	return cursor_push_byte(&builder->strings, '\0');
}

static int ndb_builder_push_json_tag(struct ndb_builder *builder,
				     const char *str, int len)
{
	union ndb_packed_str pstr;
	int pack_ids = 1;
	if (!ndb_builder_make_json_str(builder, str, len, &pstr, NULL, pack_ids))
		return 0;
	return ndb_builder_finalize_tag(builder, pstr);
}

// Push a json array into an ndb tag ["p", "abcd..."] -> struct ndb_tag
static int ndb_builder_tag_from_json_array(struct ndb_json_parser *p,
					   jsmntok_t *array)
{
	jsmntok_t *str_tok;
	const char *str;

	if (array->size == 0)
		return 0;

	if (!ndb_builder_new_tag(&p->builder))
		return 0;

	for (int i = 0; i < array->size; i++) {
		str_tok = &array[i+1];
		str = p->json + str_tok->start;

		if (!ndb_builder_push_json_tag(&p->builder, str,
					       toksize(str_tok))) {
			return 0;
		}
	}

	return 1;
}

// Push json tags into ndb data
//   [["t", "hashtag"], ["p", "abcde..."]] -> struct ndb_tags
static inline int ndb_builder_process_json_tags(struct ndb_json_parser *p,
						jsmntok_t *array)
{
	jsmntok_t *tag = array;

	if (array->size == 0)
		return 1;

	for (int i = 0; i < array->size; i++) {
		if (!ndb_builder_tag_from_json_array(p, &tag[i+1]))
			return 0;
		tag += tag[i+1].size;
	}

	return 1;
}

static int parse_unsigned_int(const char *start, int len, unsigned int *num)
{
	unsigned int number = 0;
	const char *p = start, *end = start + len;
	int digits = 0;

	while (p < end) {
		char c = *p;

		if (c < '0' || c > '9')
			break;

		// Check for overflow
		char digit = c - '0';
		if (number > (UINT_MAX - digit) / 10)
			return 0; // Overflow detected

		number = number * 10 + digit;

		p++;
		digits++;
	}

	if (digits == 0)
		return 0;

	*num = number;
	return 1;
}

int ndb_client_event_from_json(const char *json, int len, struct ndb_fce *fce,
			       unsigned char *buf, int bufsize, struct ndb_id_cb *cb)
{
	jsmntok_t *tok = NULL;
	int tok_len, res;
	struct ndb_json_parser parser;

	ndb_json_parser_init(&parser, json, len, buf, bufsize);

	if ((res = ndb_json_parser_parse(&parser, cb)) < 0)
		return res;

	if (parser.num_tokens <= 3 || parser.toks[0].type != JSMN_ARRAY)
		return 0;

	parser.i = 1;
	tok = &parser.toks[parser.i++];
	tok_len = toksize(tok);
	if (tok->type != JSMN_STRING)
		return 0;

	if (tok_len == 5 && !memcmp("EVENT", json + tok->start, 5)) {
		fce->evtype = NDB_FCE_EVENT;
		struct ndb_event *ev = &fce->event;
		return ndb_parse_json_note(&parser, &ev->note);
	}

	return 0;
}


int ndb_ws_event_from_json(const char *json, int len, struct ndb_tce *tce,
			   unsigned char *buf, int bufsize,
			   struct ndb_id_cb *cb)
{
	jsmntok_t *tok = NULL;
	int tok_len, res;
	struct ndb_json_parser parser;

	tce->subid_len = 0;
	tce->subid = "";

	ndb_json_parser_init(&parser, json, len, buf, bufsize);

	if ((res = ndb_json_parser_parse(&parser, cb)) < 0)
		return res;

	if (parser.num_tokens < 3 || parser.toks[0].type != JSMN_ARRAY)
		return 0;

	parser.i = 1;
	tok = &parser.toks[parser.i++];
	tok_len = toksize(tok);
	if (tok->type != JSMN_STRING)
		return 0;

	if (tok_len == 5 && !memcmp("EVENT", json + tok->start, 5)) {
		tce->evtype = NDB_TCE_EVENT;
		struct ndb_event *ev = &tce->event;

		tok = &parser.toks[parser.i++];
		if (tok->type != JSMN_STRING)
			return 0;

		tce->subid = json + tok->start;
		tce->subid_len = toksize(tok);

		return ndb_parse_json_note(&parser, &ev->note);
	} else if (tok_len == 4 && !memcmp("EOSE", json + tok->start, 4)) { 
		tce->evtype = NDB_TCE_EOSE;

		tok = &parser.toks[parser.i++];
		if (tok->type != JSMN_STRING)
			return 0;

		tce->subid = json + tok->start;
		tce->subid_len = toksize(tok);
		return 1;
	} else if (tok_len == 2 && !memcmp("OK", json + tok->start, 2)) {
		if (parser.num_tokens != 5)
			return 0;

		struct ndb_command_result *cr = &tce->command_result;

		tce->evtype = NDB_TCE_OK;

		tok = &parser.toks[parser.i++];
		if (tok->type != JSMN_STRING)
			return 0;

		tce->subid = json + tok->start;
		tce->subid_len = toksize(tok);

		tok = &parser.toks[parser.i++];
		if (tok->type != JSMN_PRIMITIVE || toksize(tok) == 0)
			return 0;

		cr->ok = (json + tok->start)[0] == 't';

		tok = &parser.toks[parser.i++];
		if (tok->type != JSMN_STRING)
			return 0;

		tce->command_result.msg = json + tok->start;
		tce->command_result.msglen = toksize(tok);

		return 1;
	}

	return 0;
}

int ndb_parse_json_note(struct ndb_json_parser *parser, struct ndb_note **note)
{
	jsmntok_t *tok = NULL;
	unsigned char hexbuf[64];
	const char *json = parser->json;
	const char *start;
	int i, tok_len, parsed;

	parsed = 0;

	if (parser->toks[parser->i].type != JSMN_OBJECT)
		return 0;

	// TODO: build id buffer and verify at end

	for (i = parser->i + 1; i < parser->num_tokens; i++) {
		tok = &parser->toks[i];
		start = json + tok->start;
		tok_len = toksize(tok);

		//printf("toplevel %.*s %d\n", tok_len, json + tok->start, tok->type);
		if (tok_len == 0 || i + 1 >= parser->num_tokens)
			continue;

		if (start[0] == 'p' && jsoneq(json, tok, tok_len, "pubkey")) {
			// pubkey
			tok = &parser->toks[i+1];
			hex_decode(json + tok->start, toksize(tok), hexbuf, sizeof(hexbuf));
			parsed |= NDB_PARSED_PUBKEY;
			ndb_builder_set_pubkey(&parser->builder, hexbuf);
		} else if (tok_len == 2 && start[0] == 'i' && start[1] == 'd') {
			// id
			tok = &parser->toks[i+1];
			hex_decode(json + tok->start, toksize(tok), hexbuf, sizeof(hexbuf));
			parsed |= NDB_PARSED_ID;
			ndb_builder_set_id(&parser->builder, hexbuf);
		} else if (tok_len == 3 && start[0] == 's' && start[1] == 'i' && start[2] == 'g') {
			// sig
			tok = &parser->toks[i+1];
			hex_decode(json + tok->start, toksize(tok), hexbuf, sizeof(hexbuf));
			parsed |= NDB_PARSED_SIG;
			ndb_builder_set_sig(&parser->builder, hexbuf);
		} else if (start[0] == 'k' && jsoneq(json, tok, tok_len, "kind")) {
			// kind
			tok = &parser->toks[i+1];
			start = json + tok->start;
			if (tok->type != JSMN_PRIMITIVE || tok_len <= 0)
				return 0;
			if (!parse_unsigned_int(start, toksize(tok),
						&parser->builder.note->kind))
					return 0;
			parsed |= NDB_PARSED_KIND;
		} else if (start[0] == 'c') {
			if (jsoneq(json, tok, tok_len, "created_at")) {
				// created_at
				tok = &parser->toks[i+1];
				start = json + tok->start;
				if (tok->type != JSMN_PRIMITIVE || tok_len <= 0)
					return 0;
				// TODO: update to int64 in 2106 ... xD
				unsigned int bigi;
				if (!parse_unsigned_int(start, toksize(tok), &bigi))
					return 0;
				parser->builder.note->created_at = bigi;
				parsed |= NDB_PARSED_CREATED_AT;
			} else if (jsoneq(json, tok, tok_len, "content")) {
				// content
				tok = &parser->toks[i+1];
				union ndb_packed_str pstr;
				tok_len = toksize(tok);
				int written, pack_ids = 0;
				if (!ndb_builder_make_json_str(&parser->builder,
							json + tok->start,
							tok_len, &pstr,
							&written, pack_ids)) {
					ndb_debug("ndb_builder_make_json_str failed\n");
					return 0;
				}
				parser->builder.note->content_length = written;
				parser->builder.note->content = pstr;
				parsed |= NDB_PARSED_CONTENT;
			}
		} else if (start[0] == 't' && jsoneq(json, tok, tok_len, "tags")) {
			tok = &parser->toks[i+1];
			ndb_builder_process_json_tags(parser, tok);
			i += tok->size;
			parsed |= NDB_PARSED_TAGS;
		}
	}

	//ndb_debug("parsed %d = %d, &->%d", parsed, NDB_PARSED_ALL, parsed & NDB_PARSED_ALL);
	if (parsed != NDB_PARSED_ALL)
		return 0;

	return ndb_builder_finalize(&parser->builder, note, NULL);
}

int ndb_note_from_json(const char *json, int len, struct ndb_note **note,
		       unsigned char *buf, int bufsize)
{
	struct ndb_json_parser parser;
	int res;

	ndb_json_parser_init(&parser, json, len, buf, bufsize);
	if ((res = ndb_json_parser_parse(&parser, NULL)) < 0)
		return res;

	if (parser.num_tokens < 1)
		return 0;

	return ndb_parse_json_note(&parser, note);
}

void ndb_builder_set_pubkey(struct ndb_builder *builder, unsigned char *pubkey)
{
	memcpy(builder->note->pubkey, pubkey, 32);
}

void ndb_builder_set_id(struct ndb_builder *builder, unsigned char *id)
{
	memcpy(builder->note->id, id, 32);
}

void ndb_builder_set_sig(struct ndb_builder *builder, unsigned char *sig)
{
	memcpy(builder->note->sig, sig, 64);
}

void ndb_builder_set_kind(struct ndb_builder *builder, uint32_t kind)
{
	builder->note->kind = kind;
}

void ndb_builder_set_created_at(struct ndb_builder *builder, uint64_t created_at)
{
	builder->note->created_at = created_at;
}

int ndb_builder_new_tag(struct ndb_builder *builder)
{
	builder->note->tags.count++;
	struct ndb_tag tag = {0};
	builder->current_tag = (struct ndb_tag *)builder->note_cur.p;
	return cursor_push_tag(&builder->note_cur, &tag);
}

void ndb_stat_counts_init(struct ndb_stat_counts *counts)
{
	counts->count = 0;
	counts->key_size = 0;
	counts->value_size = 0;
}

static void ndb_stat_init(struct ndb_stat *stat)
{
	// init stats
	int i;

	for (i = 0; i < NDB_CKIND_COUNT; i++) {
		ndb_stat_counts_init(&stat->common_kinds[i]);
	}

	for (i = 0; i < NDB_DBS; i++) {
		ndb_stat_counts_init(&stat->dbs[i]);
	}

	ndb_stat_counts_init(&stat->other_kinds);
}

int ndb_stat(struct ndb *ndb, struct ndb_stat *stat)
{
	int rc;
	MDB_cursor *cur;
	MDB_val k, v;
	MDB_dbi db;
	struct ndb_txn txn;
	struct ndb_note *note;
	int i;
	enum ndb_common_kind common_kind;

	// initialize to 0
	ndb_stat_init(stat);

	if (!ndb_begin_query(ndb, &txn)) {
		fprintf(stderr, "ndb_stat failed at ndb_begin_query\n");
		return 0;
	}

	// stat each dbi in the database
	for (i = 0; i < NDB_DBS; i++)
	{
		db = ndb->lmdb.dbs[i];

		if ((rc = mdb_cursor_open(txn.mdb_txn, db, &cur))) {
			fprintf(stderr, "ndb_stat: mdb_cursor_open failed, error '%s'\n",
					mdb_strerror(rc));
			return 0;
		}

		// loop over every entry and count kv sizes
		while (mdb_cursor_get(cur, &k, &v, MDB_NEXT) == 0) {
			// we gather more detailed per-kind stats if we're in
			// the notes db
			if (i == NDB_DB_NOTE) {
				note = v.mv_data;
				common_kind = ndb_kind_to_common_kind(note->kind);

				// uncommon kind? just count them in bulk
				if (common_kind == -1) {
					stat->other_kinds.count++;
					stat->other_kinds.key_size += k.mv_size;
					stat->other_kinds.value_size += v.mv_size;
				} else {
					stat->common_kinds[common_kind].count++;
					stat->common_kinds[common_kind].key_size += k.mv_size;
					stat->common_kinds[common_kind].value_size += v.mv_size;
				}
			}

			stat->dbs[i].count++;
			stat->dbs[i].key_size += k.mv_size;
			stat->dbs[i].value_size += v.mv_size;
		}

		// close the cursor, they are per-dbi
		mdb_cursor_close(cur);
	}

	ndb_end_query(&txn);

	return 1;
}

/// Push an element to the current tag
/// 
/// Basic idea is to call ndb_builder_new_tag
inline int ndb_builder_push_tag_str(struct ndb_builder *builder,
				    const char *str, int len)
{
	union ndb_packed_str pstr;
	int pack_ids = 1;
	if (!ndb_builder_make_str(builder, str, len, &pstr, pack_ids))
		return 0;
	return ndb_builder_finalize_tag(builder, pstr);
}


