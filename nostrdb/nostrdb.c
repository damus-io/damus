
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
#include "bindings/c/profile_verifier.h"
#include "secp256k1.h"
#include "secp256k1_ecdh.h"
#include "secp256k1_schnorrsig.h"

// the maximum number of things threads pop and push in bulk
static const int THREAD_QUEUE_BATCH = 4096;

// the maximum size of inbox queues
static const int DEFAULT_QUEUE_SIZE = 1000000;


#define NDB_PARSED_ID           (1 << 0)
#define NDB_PARSED_PUBKEY       (1 << 1)
#define NDB_PARSED_SIG          (1 << 2)
#define NDB_PARSED_CREATED_AT   (1 << 3)
#define NDB_PARSED_KIND         (1 << 4)
#define NDB_PARSED_CONTENT      (1 << 5)
#define NDB_PARSED_TAGS         (1 << 6)
#define NDB_PARSED_ALL          (NDB_PARSED_ID|NDB_PARSED_PUBKEY|NDB_PARSED_SIG|NDB_PARSED_CREATED_AT|NDB_PARSED_KIND|NDB_PARSED_CONTENT|NDB_PARSED_TAGS)

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

enum ndb_dbs {
	NDB_DB_NOTE,
	NDB_DB_META,
	NDB_DB_PROFILE,
	NDB_DB_NOTE_ID,
	NDB_DB_PROFILE_PK,
	NDB_DBS,
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
	// lmdb environ handles, etc
};

// A clustered key with an id and a timestamp
struct ndb_tsid {
	unsigned char id[32];
	uint64_t timestamp;
};

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
	key->timestamp = 0;
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

enum ndb_writer_msgtype {
	NDB_WRITER_QUIT, // kill thread immediately
	NDB_WRITER_NOTE, // write a note to the db
	NDB_WRITER_PROFILE, // write a profile to the db
};

struct ndb_ingester_event {
	char *json;
	int len;
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

struct ndb_writer_msg {
	enum ndb_writer_msgtype type;
	union {
		struct ndb_writer_note note;
		struct ndb_writer_profile profile;
	};
};

int ndb_begin_query(struct ndb *ndb, struct ndb_txn *txn)
{
	txn->ndb = ndb;
	MDB_txn **mdb_txn = (MDB_txn **)&txn->mdb_txn;
	return mdb_txn_begin(ndb->lmdb.env, NULL, 0, mdb_txn) == 0;
}

void ndb_end_query(struct ndb_txn *txn)
{
	mdb_txn_abort(txn->mdb_txn);
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

// get some value based on a clustered id key
int ndb_get_tsid(MDB_txn *txn, struct ndb_lmdb *lmdb, enum ndb_dbs db,
		 const unsigned char *id, MDB_val *val)
{
	MDB_val k, v;
	MDB_cursor *cur;
	int success = 0;
	struct ndb_tsid tsid;

	// position at the most recent
	ndb_tsid_high(&tsid, id);

	k.mv_data = &tsid;
	k.mv_size = sizeof(tsid);

	mdb_cursor_open(txn, lmdb->dbs[db], &cur);

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

	if (mdb_get(txn->mdb_txn, txn->ndb->lmdb.dbs[store], &k, &v)) {
		ndb_debug("ndb_get_profile_by_pubkey: mdb_get note failed\n");
		mdb_txn_abort(txn->mdb_txn);
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

	if (!ndb_get_tsid(txn->mdb_txn, &txn->ndb->lmdb, ind, pk, &k)) {
		//ndb_debug("ndb_get_profile_by_pubkey: ndb_get_tsid failed\n");
		return 0;
	}

	if (primkey)
		*primkey = *(uint64_t*)k.mv_data;

	if (mdb_get(txn->mdb_txn, txn->ndb->lmdb.dbs[store], &k, &v)) {
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

	if (!ndb_get_tsid(txn->mdb_txn, &txn->ndb->lmdb, db, id, &k))
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

static int ndb_has_note(MDB_txn *txn, struct ndb_lmdb *lmdb, const unsigned char *id)
{
	MDB_val val;

	if (!ndb_get_tsid(txn, lmdb, NDB_DB_NOTE_ID, id, &val))
		return 0;

	return 1;
}

static enum ndb_idres ndb_ingester_json_controller(void *data, const char *hexid)
{
	unsigned char id[32];
	struct ndb_ingest_controller *c = data;

	hex_decode(hexid, 64, id, sizeof(id));

	// let's see if we already have it

	if (!ndb_has_note(c->read_txn, c->lmdb, id))
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

static int ndb_process_profile_note(struct ndb_note *note,
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


static int ndb_ingester_process_event(secp256k1_context *ctx,
				      struct ndb_ingester *ingester,
				      struct ndb_ingester_event *ev,
				      struct ndb_writer_msg *out,
				      MDB_txn *read_txn
				      )
{
	struct ndb_tce tce;
	struct ndb_note *note;
	struct ndb_ingest_controller controller;
	struct ndb_id_cb cb;
	void *buf;
	size_t bufsize, note_size;

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

		// Verify! If it's an invalid note we don't need to
		// bothter writing it to the database
		if (!ndb_note_verify(ctx, note->pubkey, note->id, note->sig)) {
			ndb_debug("signature verification failed\n");
			goto cleanup;
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

		// there's nothing left to do with the original json, so free it
		free(ev->json);
		return 1;
	}

cleanup:
	free(ev->json);
	free(buf);

	return 0;
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

static int ndb_write_profile(struct ndb_lmdb *lmdb, MDB_txn *txn,
			     struct ndb_writer_profile *profile,
			     uint64_t note_key)
{
	uint64_t profile_key;
	struct ndb_tsid tsid;
	struct ndb_note *note;
	void *flatbuf;
	size_t flatbuf_len;
	int rc;

	MDB_val key, val;
	MDB_dbi profile_db, pk_db;
	
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
	profile_db = lmdb->dbs[NDB_DB_PROFILE];
	pk_db = lmdb->dbs[NDB_DB_PROFILE_PK];

	// get new key
	profile_key = ndb_get_last_key(txn, profile_db) + 1;

	// write profile to profile store
	key.mv_data = &profile_key;
	key.mv_size = sizeof(profile_key);
	val.mv_data = flatbuf;
	val.mv_size = flatbuf_len;
	//ndb_debug("profile_len %ld\n", profile->profile_len);

	if ((rc = mdb_put(txn, profile_db, &key, &val, 0))) {
		ndb_debug("write profile to db failed: %s\n", mdb_strerror(rc));
		return 0;
	}

	// write profile_pk + created_at index
	ndb_tsid_init(&tsid, note->pubkey, note->created_at);

	key.mv_data = &tsid;
	key.mv_size = sizeof(tsid);
	val.mv_data = &profile_key;
	val.mv_size = sizeof(profile_key);

	if ((rc = mdb_put(txn, pk_db, &key, &val, 0))) {
		ndb_debug("write profile_pk(%" PRIu64 ") to db failed: %s\n",
				profile_key, mdb_strerror(rc));
		return 0;
	}

	return 1;
}

static uint64_t ndb_write_note(struct ndb_lmdb *lmdb, MDB_txn *txn,
			       struct ndb_writer_note *note)
{
	int rc;
	uint64_t note_key;
	struct ndb_tsid tsid;
	MDB_dbi note_db, id_db;
	MDB_val key, val;
	
	// get dbs
	note_db = lmdb->dbs[NDB_DB_NOTE];
	id_db = lmdb->dbs[NDB_DB_NOTE_ID];

	// get new key
	note_key = ndb_get_last_key(txn, note_db) + 1;

	// write note to event store
	key.mv_data = &note_key;
	key.mv_size = sizeof(note_key);
	val.mv_data = note->note;
	val.mv_size = note->note_len;

	if ((rc = mdb_put(txn, note_db, &key, &val, 0))) {
		ndb_debug("write note to db failed: %s\n", mdb_strerror(rc));
		return 0;
	}

	// write id index key clustered with created_at
	ndb_tsid_init(&tsid, note->note->id, note->note->created_at);

	key.mv_data = &tsid;
	key.mv_size = sizeof(tsid);
	val.mv_data = &note_key;
	val.mv_size = sizeof(note_key);

	if ((rc = mdb_put(txn, id_db, &key, &val, 0))) {
		ndb_debug("write note id index to db failed: %s\n",
				mdb_strerror(rc));
		return 0;
	}

	return note_key;
}

static void *ndb_writer_thread(void *data)
{
	struct ndb_writer *writer = data;
	struct ndb_writer_msg msgs[THREAD_QUEUE_BATCH], *msg;
	int i, popped, done, any_note;
	uint64_t note_nkey;
	MDB_txn *txn;

	done = 0;
	while (!done) {
		txn = NULL;
		popped = prot_queue_pop_all(&writer->inbox, msgs, THREAD_QUEUE_BATCH);
		//ndb_debug("writer popped %d items\n", popped);

		any_note = 0;
		for (i = 0 ; i < popped; i++) {
			msg = &msgs[i];
			switch (msg->type) {
			case NDB_WRITER_NOTE: any_note = 1; break;
			case NDB_WRITER_PROFILE: any_note = 1; break;
			case NDB_WRITER_QUIT: break;
			}
		}

		if (any_note && mdb_txn_begin(writer->lmdb->env, NULL, 0, &txn))
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
					ndb_write_note(writer->lmdb, txn, &msg->note);
				if (msg->profile.record.builder) {
					// only write if parsing didn't fail
					ndb_write_profile(writer->lmdb, txn,
							  &msg->profile,
							  note_nkey);
				}
				break;
			case NDB_WRITER_NOTE:
				ndb_write_note(writer->lmdb, txn, &msg->note);
				break;
			}
		}

		// commit writes
		if (any_note && mdb_txn_commit(txn)) {
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

		if (any_event)
			mdb_txn_begin(lmdb->env, NULL, MDB_RDONLY, &read_txn);

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
				    char *json, int len)
{
	struct ndb_ingester_msg msg;
	msg.type = NDB_INGEST_EVENT;

	msg.event.json = json;
	msg.event.len = len;

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
		fprintf(stderr, "mdb_env_set_mapsize failed, error %d\n", rc);
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
	if ((rc = mdb_dbi_open(txn, "meta", MDB_CREATE | MDB_INTEGERKEY, &lmdb->dbs[NDB_DB_META]))) {
		fprintf(stderr, "mdb_dbi_open meta failed, error %d\n", rc);
		return 0;
	}

	// profile flatbuffer db
	if ((rc = mdb_dbi_open(txn, "profile", MDB_CREATE | MDB_INTEGERKEY, &lmdb->dbs[NDB_DB_PROFILE]))) {
		fprintf(stderr, "mdb_dbi_open profile failed, error %d\n", rc);
		return 0;
	}

	// id+ts index flags
	unsigned int tsid_flags = MDB_CREATE | MDB_DUPSORT | MDB_DUPFIXED;

	// index dbs
	if ((rc = mdb_dbi_open(txn, "note_id", tsid_flags, &lmdb->dbs[NDB_DB_NOTE_ID]))) {
		fprintf(stderr, "mdb_dbi_open id failed, error %d\n", rc);
		return 0;
	}
	mdb_set_compare(txn, lmdb->dbs[NDB_DB_NOTE_ID], ndb_tsid_compare);

	if ((rc = mdb_dbi_open(txn, "profile_pk", tsid_flags, &lmdb->dbs[NDB_DB_PROFILE_PK]))) {
		fprintf(stderr, "mdb_dbi_open id failed, error %d\n", rc);
		return 0;
	}
	mdb_set_compare(txn, lmdb->dbs[NDB_DB_PROFILE_PK], ndb_tsid_compare);


	// Commit the transaction
	if ((rc = mdb_txn_commit(txn))) {
		fprintf(stderr, "mdb_txn_commit failed, error %d\n", rc);
		return 0;
	}

	return 1;
}

int ndb_init(struct ndb **pndb, const char *filename, size_t mapsize, int ingester_threads)
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
		fprintf(stderr, "ndb_writer_init failed");
		return 0;
	}

	if (!ndb_ingester_init(&ndb->ingester, &ndb->writer, ingester_threads)) {
		fprintf(stderr, "failed to initialize %d ingester thread(s)",
				ingester_threads);
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

// Process a nostr event, ie: ["EVENT", "subid", {"content":"..."}...]
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

	return ndb_ingester_queue_event(&ndb->ingester, json_copy, json_len);
}

int ndb_process_events(struct ndb *ndb, const char *ldjson, size_t json_len)
{
	const char *start, *end, *very_end;
	start = ldjson;
	end = start + json_len;
	very_end = ldjson + json_len;
#if DEBUG
	int processed = 0;
#endif

	while ((end = fast_strchr(start, '\n', very_end - start))) {
		//printf("processing '%.*s'\n", (int)(end-start), start);
		if (!ndb_process_event(ndb, start, end - start)) {
			ndb_debug("ndb_process_event failed\n");
			return 0;
		}
		start = end + 1;
#if DEBUG
		processed++;
#endif
	}

	ndb_debug("ndb_process_events: processed %d events\n", processed);

	return 1;
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

static inline int toksize(jsmntok_t *tok)
{
	return tok->end - tok->start;
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

	if (parser.num_tokens < 3 || parser.toks[0].type != JSMN_ARRAY) {
		/*
		tok = &parser.toks[parser.json_parser.toknext-1];
		ndb_debug("failing at not enough takens (%d) or != JSMN_ARRAY @ '%.*s', '%.*s'\n",
				parser.num_tokens, 10, json + parser.json_parser.pos,
				toksize(tok), json + tok->start);
		tok = &parser.toks[parser.json_parser.toknext-2];
		ndb_debug("failing at not enough takens (%d) or != JSMN_ARRAY @ '%.*s', '%.*s'\n",
				parser.num_tokens, 10, json + parser.json_parser.pos,
				toksize(tok), json + tok->start);
				*/
		return 0;
	}

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
