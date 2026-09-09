/* Standalone native regression executable. Including the implementation gives
 * fixtures access to the real migration transaction without shipping test hooks. */
#include "../src/nostrdb.c"
#include <sys/stat.h>
#ifdef _WIN32
#include <direct.h>
#endif

static unsigned char voice_scratch[NDB_VOICE_REPOST_SCRATCH_SIZE];
static secp256k1_context *voice_secp;

struct voice_fixture {
    unsigned char *buffer;
    struct ndb_note *note;
    int size;
    char *json;
    char id[65], pubkey[65];
};

static struct voice_fixture voice_note(int kind, const char *content,
        const char *tags[][5], int count, unsigned char secret, int timestamp)
{
    struct voice_fixture f = {0};
    struct ndb_builder b;
    struct ndb_keypair kp = {0};
    int i, j;
    kp.secret[31] = secret;
    assert(ndb_create_keypair(&kp));
    f.buffer = malloc(512 * 1024);
    f.json = malloc(512 * 1024);
    assert(f.buffer && f.json);
    assert(ndb_builder_init(&b, f.buffer, 512 * 1024));
    ndb_builder_set_kind(&b, kind);
    ndb_builder_set_created_at(&b, 1780000000 + timestamp);
    ndb_builder_set_pubkey(&b, kp.pubkey);
    for (i = 0; i < count; i++) {
        assert(ndb_builder_new_tag(&b));
        for (j = 0; j < 5 && tags[i][j]; j++)
            assert(ndb_builder_push_tag_str(&b, tags[i][j], strlen(tags[i][j])));
    }
    assert(ndb_builder_set_content(&b, content, strlen(content)));
    f.size = ndb_builder_finalize(&b, &f.note, &kp);
    assert(f.size > 0);
    assert(ndb_note_verify(voice_secp, voice_scratch, sizeof(voice_scratch), f.note));
    assert(ndb_note_json(f.note, f.json, 512 * 1024) > 0);
    assert(hex_encode(ndb_note_id(f.note), 32, f.id));
    assert(hex_encode(ndb_note_pubkey(f.note), 32, f.pubkey));
    return f;
}

static void voice_free(struct voice_fixture *f) { free(f->buffer); free(f->json); }

static void voice_begin(struct ndb_lmdb *db, struct ndb_txn *txn, int readonly)
{
    MDB_txn *raw;
    assert(mdb_txn_begin(db->env, NULL, readonly ? MDB_RDONLY : 0, &raw) == 0);
    txn->lmdb = db; txn->mdb_txn = raw;
}

static void voice_open(struct ndb_lmdb *db, const char *path)
{
    memset(db, 0, sizeof(*db));
    assert(ndb_init_lmdb(path, db, 256 * 1024 * 1024, NULL, NULL));
}

static uint64_t voice_write(struct ndb_txn *txn, struct voice_fixture *f, int legacy)
{
    struct ndb_writer_note writer;
    ndb_writer_note_init(&writer, f->note, f->size, NULL, 0);
    return ndb_write_note(voice_secp, txn, &writer, voice_scratch, sizeof(voice_scratch),
        legacy ? NDB_FLAG_NO_FULLTEXT | NDB_FLAG_NO_NOTE_BLOCKS : 0, NULL);
}

static void voice_counts(struct ndb_txn *txn, struct voice_fixture *f,
        int direct, int thread, int quotes, int reposts)
{
    struct ndb_note_meta *meta = ndb_get_note_meta(txn, ndb_note_id(f->note));
    struct ndb_note_meta_entry *entry;
    assert(meta);
    entry = ndb_note_meta_find_entry(meta, NDB_NOTE_META_COUNTS, NULL);
    assert(entry);
    assert(*ndb_note_meta_counts_direct_replies(entry) == direct);
    assert(*ndb_note_meta_counts_thread_replies(entry) == thread);
    assert(*ndb_note_meta_counts_quotes(entry) == quotes);
    assert(*ndb_note_meta_counts_reposts(entry) == reposts);
}

static int voice_search(struct ndb_txn *txn, const char *text)
{
    struct ndb_text_search_results results;
    struct ndb_text_search_config config;
    ndb_default_text_search_config(&config);
    assert(ndb_text_search(txn, text, &results, &config));
    return results.num_results;
}

static void voice_blocks(struct ndb_txn *txn, struct voice_fixture *f)
{
    uint64_t id = ndb_get_notekey_by_id(txn, ndb_note_id(f->note));
    MDB_val key = {sizeof(id), &id}, val;
    struct ndb_blocks *blocks;
    assert(id);
    assert(mdb_get(txn->mdb_txn, txn->lmdb->dbs[NDB_DB_NOTE_BLOCKS], &key, &val) == 0);
    blocks = val.mv_data;
    assert(ndb_blocks_word_count(blocks) > 0);
}

static void voice_preserved_metadata(struct ndb_txn *txn, struct voice_fixture *f)
{
    struct ndb_note_meta_builder builder;
    struct ndb_note_meta *meta;
    struct ndb_note_meta_entry *entry;
    MDB_val key = {32, ndb_note_id(f->note)}, value;
    assert(ndb_note_meta_builder_init(&builder, voice_scratch, sizeof(voice_scratch)));
    entry = ndb_note_meta_add_entry(&builder);
    assert(entry);
    ndb_note_meta_counts_set(entry, 0, 0, 0, 0, 0);
    entry = ndb_note_meta_add_entry(&builder);
    assert(entry);
    ndb_note_meta_zap_set(entry, 2, 42000);
    ndb_note_meta_build(&builder, &meta);
    *ndb_note_meta_flags(meta) = 1ULL << NDB_NOTE_META_FLAG_SEEN;
    value.mv_data = meta; value.mv_size = ndb_note_meta_total_size(meta);
    assert(mdb_put(txn->mdb_txn, txn->lmdb->dbs[NDB_DB_META], &key, &value, 0) == 0);
}

static void voice_assert_preserved(struct ndb_txn *txn, struct voice_fixture *f)
{
    struct ndb_note_meta *meta = ndb_get_note_meta(txn, ndb_note_id(f->note));
    struct ndb_note_meta_entry *zap;
    assert(meta && *ndb_note_meta_flags(meta) == (1ULL << NDB_NOTE_META_FLAG_SEEN));
    zap = ndb_note_meta_find_entry(meta, NDB_NOTE_META_ZAP, NULL);
    assert(zap && *ndb_note_meta_zap_count(zap) == 2 && *ndb_note_meta_zap_msats(zap) == 42000);
}

static void voice_scenario(const char *path, int legacy, int fail_first)
{
    struct ndb_lmdb db;
    struct ndb_txn txn;
    struct ndb *ingest;
    struct ndb_config config;
    struct voice_fixture root = voice_note(1, "Text root", NULL, 0, 1, 0);
    const char *first_tags[][5] = {{"e", root.id, "", "root"}, {"e", root.id, "", "reply"}};
    struct voice_fixture first = voice_note(1808, "migrationneedlevoice first transcript", first_tags, 2, 2, 1);
    const char *nested_tags[][5] = {{"e", root.id, "", "root"}, {"e", first.id, "", "reply"}};
    struct voice_fixture nested = voice_note(1, "Text nested reply", nested_tags, 2, 1, 2);
    const char *deep_tags[][5] = {{"e", root.id, "", "root"}, {"e", nested.id, "", "reply"}};
    struct voice_fixture deep = voice_note(1808, "migrationdeepvoice nested transcript", deep_tags, 2, 2, 3);
    struct voice_fixture original = voice_note(1808, "migrationoriginalvoice embedded transcript", NULL, 0, 2, 5);
    const char *quote_tags[][5] = {{"q", first.id, "", first.pubkey}, {"q", original.id}, {"p", first.pubkey}};
    struct voice_fixture quote = voice_note(1808, "migrationquotevoice commentary", quote_tags, 3, 1, 4);
    const char *repost_tags[][5] = {{"e", first.id, "", "", "repost-source"},
        {"p", first.pubkey, "", "repost-source"}, {"e", original.id}, {"p", original.pubkey}, {"k", "1808"}};
    struct voice_fixture repost = voice_note(1809, original.json, repost_tags, 5, 1, 6);
    const char *bad_tags[][5] = {{"e", original.id}, {"p", original.pubkey}, {"k", "1"}};
    struct voice_fixture bad = voice_note(1809, original.json, bad_tags, 3, 1, 7);
    struct voice_fixture lonely = voice_note(1808, "Only incoming text interactions", NULL, 0, 2, 8);
    const char *lonely_tags[][5] = {{"e", lonely.id, "", "root"}};
    struct voice_fixture lonely_reply = voice_note(1, "Text reply to isolated voice target", lonely_tags, 1, 1, 9);
    struct voice_fixture irrelevant = voice_note(42, "Non-post q tags do not count", quote_tags, 3, 1, 10);
    struct voice_fixture *fixtures[] = {&root, &first, &nested, &deep, &quote, &repost, &bad, &lonely, &lonely_reply, &irrelevant};
    int fixture_count = sizeof(fixtures) / sizeof(fixtures[0]);
    unsigned char target[32];
    char *wire = malloc(1024 * 1024);
    int i, pass;
    assert(wire);
    assert(ndb_note_verify_voice_repost(voice_secp, voice_scratch, sizeof(voice_scratch), repost.note, target));
    assert(!memcmp(target, ndb_note_id(original.note), 32));
    assert(!ndb_note_verify_voice_repost(voice_secp, voice_scratch, sizeof(voice_scratch), bad.note, NULL));

    if (!legacy) {
        ndb_default_config(&config);
        ndb_config_set_mapsize(&config, 256 * 1024 * 1024);
        ndb_config_set_ingest_threads(&config, 1);
        assert(ndb_init(&ingest, path, &config));
        for (i = 0; i < fixture_count; i++) {
            snprintf(wire, 1024 * 1024, "[\"EVENT\",%s]", fixtures[i]->json);
            assert(ndb_process_client_event(ingest, wire, strlen(wire)));
        }
        ndb_destroy(ingest); /* Drains the ingester/writer before reopening. */
    }
    voice_open(&db, path);
    if (legacy) {
        voice_begin(&db, &txn, 0);
        for (i = 0; i < fixture_count; i++) assert(voice_write(&txn, fixtures[i], 1));
        assert(mdb_drop(txn.mdb_txn, db.dbs[NDB_DB_META], 0) == 0);
        voice_preserved_metadata(&txn, &first);
        assert(ndb_write_version(&txn, 6));
        assert(ndb_end_query(&txn));
    }
    if (fail_first) {
        MDB_dbi real_blocks = db.dbs[NDB_DB_NOTE_BLOCKS];
        voice_begin(&db, &txn, 0);
        db.dbs[NDB_DB_NOTE_BLOCKS] = UINT_MAX; /* Deterministic write failure after transcript indexing. */
        assert(!ndb_run_migrations(&txn));
        mdb_txn_abort(txn.mdb_txn);
        db.dbs[NDB_DB_NOTE_BLOCKS] = real_blocks;
        voice_begin(&db, &txn, 1);
        assert(ndb_db_version(&txn) == 6);
        assert(voice_search(&txn, "migrationneedlevoice") == 0);
        assert(!ndb_get_notekey_by_id(&txn, ndb_note_id(original.note)));
        voice_counts(&txn, &first, 0, 0, 0, 0);
        voice_assert_preserved(&txn, &first);
        assert(ndb_end_query(&txn));
    }
    for (pass = 0; pass < 3; pass++) {
        voice_begin(&db, &txn, 0);
        if (legacy) {
            assert(ndb_write_version(&txn, 6)); /* Reapplying must be idempotent. */
            assert(ndb_run_migrations(&txn));
        }
        assert(ndb_end_query(&txn));
        mdb_env_close(db.env);
        voice_open(&db, path);
        voice_begin(&db, &txn, 1);
        assert(ndb_db_version(&txn) == 7);
        assert(voice_search(&txn, "migrationneedlevoice") == 1);
        assert(voice_search(&txn, "migrationoriginalvoice") == 1);
        voice_blocks(&txn, &first); voice_blocks(&txn, &deep); voice_blocks(&txn, &original);
        voice_counts(&txn, &root, 1, 3, 0, 0);
        voice_counts(&txn, &first, 1, 0, 1, 0);
        voice_counts(&txn, &nested, 1, 0, 0, 0);
        voice_counts(&txn, &original, 0, 0, 0, 1);
        voice_counts(&txn, &lonely, 1, 1, 0, 0);
        if (legacy) voice_assert_preserved(&txn, &first);
        else assert(!ndb_get_notekey_by_id(&txn, ndb_note_id(bad.note)));
        assert(ndb_end_query(&txn));
        voice_begin(&db, &txn, 0);
        assert(voice_write(&txn, &first, 0) == 0);
        assert(voice_write(&txn, &repost, 0) == 0);
        assert(ndb_end_query(&txn));
    }
    mdb_env_close(db.env);
    for (i = 0; i < fixture_count; i++) voice_free(fixtures[i]);
    voice_free(&original); free(wire);
}

static void voice_atomic_failures(const char *path)
{
    struct ndb_lmdb db;
    struct ndb_txn txn;
    struct voice_fixture parent = voice_note(1, "Atomic parent", NULL, 0, 1, 20);
    const char *tags[][5] = {{"e", parent.id, "", "root"}};
    struct voice_fixture reply = voice_note(1808, "atomicvoiceneedle transcript", tags, 1, 2, 21);
    enum ndb_dbs failures[] = {NDB_DB_NOTE_ID, NDB_DB_NOTE_TAGS, NDB_DB_NOTE_TEXT, NDB_DB_NOTE_BLOCKS, NDB_DB_META};
    MDB_dbi real;
    size_t i;
    voice_open(&db, path);
    voice_begin(&db, &txn, 0);
    assert(voice_write(&txn, &parent, 0));
    assert(ndb_end_query(&txn));
    for (i = 0; i < sizeof(failures) / sizeof(failures[0]); i++) {
        voice_begin(&db, &txn, 0);
        real = db.dbs[failures[i]];
        db.dbs[failures[i]] = UINT_MAX;
        assert(!voice_write(&txn, &reply, 0));
        db.dbs[failures[i]] = real;
        assert(ndb_end_query(&txn)); /* Even committing the outer batch must leave no partial note. */
        voice_begin(&db, &txn, 1);
        assert(!ndb_get_notekey_by_id(&txn, ndb_note_id(reply.note)));
        assert(voice_search(&txn, "atomicvoiceneedle") == 0);
        assert(!ndb_get_note_meta(&txn, ndb_note_id(parent.note)));
        assert(ndb_end_query(&txn));
    }
    voice_begin(&db, &txn, 0);
    assert(voice_write(&txn, &reply, 0));
    assert(ndb_end_query(&txn));
    voice_begin(&db, &txn, 1);
    assert(voice_search(&txn, "atomicvoiceneedle") == 1);
    voice_blocks(&txn, &reply);
    voice_counts(&txn, &parent, 1, 1, 0, 0);
    assert(ndb_end_query(&txn));
    /* Existing private text interactions still contribute local counts on voice threads. */
    struct voice_fixture private_reply = voice_note(1, "Private text reply", tags, 1, 2, 22);
    *ndb_note_flags(private_reply.note) |= NDB_NOTE_FLAG_RUMOR;
    voice_begin(&db, &txn, 0);
    assert(voice_write(&txn, &private_reply, 0));
    assert(ndb_write_version(&txn, 6));
    assert(ndb_run_migrations(&txn));
    assert(ndb_end_query(&txn));
    voice_begin(&db, &txn, 1);
    voice_counts(&txn, &parent, 2, 2, 0, 0);
    uint64_t private_key = ndb_get_notekey_by_id(&txn, ndb_note_id(private_reply.note));
    assert(ndb_note_is_rumor(ndb_get_note_by_key(&txn, private_key, NULL)));
    assert(ndb_end_query(&txn));
    voice_free(&private_reply);
    mdb_env_close(db.env);
    voice_free(&parent); voice_free(&reply);
}

/* Both signatures and the native thread parser are tested without any network. */
static void voice_protocol_cases(void)
{
	struct voice_fixture a = voice_note(1, "A", NULL, 0, 1, 30);
	struct voice_fixture b = voice_note(1808, "B", NULL, 0, 2, 31);
	struct voice_fixture c = voice_note(1, "C", NULL, 0, 1, 32);
	const char *legacy[][5] = {{"e", a.id}, {"e", b.id}, {"e", c.id, "", ""}, {"e", a.id, "", "", "repost-source"}};
	const char *marked[][5] = {{"e", a.id}, {"e", b.id, "", "root"}, {"e", c.id, "", "reply"}};
	const char *source[][5] = {{"e", a.id, "", "", "repost-source"}};
	const char *repost_tags[][5] = {{"e", b.id}, {"p", b.pubkey}, {"k", "1808"}};
	struct voice_fixture repost = voice_note(1809, b.json, repost_tags, 3, 1, 33);
	struct voice_fixture forged;
	struct ndb_note_reply refs;
	int kind;
	assert(ndb_note_verify_voice_repost(voice_secp, voice_scratch, sizeof(voice_scratch), repost.note, NULL));
	repost.note->sig[0] ^= 1;
	assert(!ndb_note_verify_voice_repost(voice_secp, voice_scratch, sizeof(voice_scratch), repost.note, NULL));
	b.note->sig[0] ^= 1;
	assert(ndb_note_json(b.note, b.json, 512 * 1024) > 0);
	forged = voice_note(1809, b.json, repost_tags, 3, 1, 34);
	assert(!ndb_note_verify_voice_repost(voice_secp, voice_scratch, sizeof(voice_scratch), forged.note, NULL));
	for (kind = 1; kind <= 1808; kind += 1807) {
		struct voice_fixture positional = voice_note(kind, "Legacy reply", legacy, 4, 1, 35);
		struct voice_fixture explicit = voice_note(kind, "Marked reply", marked, 3, 1, 36);
		struct voice_fixture provenance = voice_note(kind, "Source only", source, 1, 1, 37);
		ndb_parse_reply(positional.note, &refs);
		assert(refs.root && !memcmp(refs.root, ndb_note_id(a.note), 32));
		assert(refs.reply && !memcmp(refs.reply, ndb_note_id(c.note), 32));
		ndb_parse_reply(explicit.note, &refs);
		assert(refs.root && !memcmp(refs.root, ndb_note_id(b.note), 32));
		assert(refs.reply && !memcmp(refs.reply, ndb_note_id(c.note), 32));
		ndb_parse_reply(provenance.note, &refs);
		assert(!refs.root && !refs.reply);
		voice_free(&positional); voice_free(&explicit); voice_free(&provenance);
	}
	voice_free(&a); voice_free(&b); voice_free(&c); voice_free(&repost); voice_free(&forged);
}

int main(int argc, char **argv)
{
    char path[4096];
    int i;
    assert(argc == 2); /* Caller supplies an empty temporary directory. */
    voice_secp = secp256k1_context_create(SECP256K1_CONTEXT_VERIFY);
    assert(voice_secp);
    voice_protocol_cases();
    for (i = 0; i < 4; i++) {
        snprintf(path, sizeof(path), "%s/voice-%d", argv[1], i);
#ifdef _WIN32
        assert(_mkdir(path) == 0);
#else
        assert(mkdir(path, 0700) == 0);
#endif
        if (i == 3) voice_atomic_failures(path);
        else voice_scenario(path, i != 0, i == 2);
    }
    secp256k1_context_destroy(voice_secp);
    puts("PASS: fresh ingestion, mixed counts, verified originals, migration rollback/retry, duplicate ingestion and repeated reopen");
    return 0;
}
