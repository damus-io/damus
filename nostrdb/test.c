
#include "nostrdb.h"
#include "hex.h"
#include "io.h"
#include "bolt11/bolt11.h"
#include "bolt11/amount.h"
#include "protected_queue.h"
#include "memchr.h"
#include "print_util.h"
#include "bindings/c/profile_reader.h"
#include "bindings/c/profile_verifier.h"
#include "bindings/c/meta_reader.h"
#include "bindings/c/meta_verifier.h"

#include <stdio.h>
#include <assert.h>
#include <unistd.h>

#define ARRAY_SIZE(x) (sizeof(x) / sizeof(x[0]))

static const char *test_dir = "./testdata/db";

static NdbProfile_table_t lookup_profile(struct ndb_txn *txn, uint64_t pk)
{
	void *root;
	size_t len;
	assert((root = ndb_get_profile_by_key(txn, pk, &len)));
	assert(root);

	NdbProfileRecord_table_t profile_record = NdbProfileRecord_as_root(root);
	NdbProfile_table_t profile = NdbProfileRecord_profile_get(profile_record);
	return profile;
}

static void print_search(struct ndb_txn *txn, struct ndb_search *search)
{
	NdbProfile_table_t profile = lookup_profile(txn, search->profile_key);
	const char *name = NdbProfile_name_get(profile);
	const char *display_name = NdbProfile_display_name_get(profile);
	printf("searched_name name:'%s' display_name:'%s' pk:%" PRIu64 " ts:%" PRIu64 " id:", name, display_name, search->profile_key, search->key->timestamp);
	print_hex(search->key->id, 32);
	printf("\n");
}


static void test_filters()
{
	struct ndb_filter filter, *f;
	struct ndb_note *note;
	unsigned char buffer[4096];

	const char *test_note = "{\"id\": \"160e76ca67405d7ce9ef7d2dd72f3f36401c8661a73d45498af842d40b01b736\",\"pubkey\": \"67c67870aebc327eb2a2e765e6dbb42f0f120d2c4e4e28dc16b824cf72a5acc1\",\"created_at\": 1700688516,\"kind\": 1337,\"tags\": [[\"t\",\"hashtag\"],[\"t\",\"grownostr\"],[\"p\",\"4d2e7a6a8e08007ace5a03391d21735f45caf1bf3d67b492adc28967ab46525e\"]],\"content\": \"\",\"sig\": \"20c2d070261ed269559ada40ca5ac395c389681ee3b5f7d50de19dd9b328dd70cf27d9d13875e87c968d9b49fa05f66e90f18037be4529b9e582c7e2afac3f06\"}";

	f = &filter;
	assert(ndb_note_from_json(test_note, strlen(test_note), &note, buffer, sizeof(buffer)));

	assert(ndb_filter_init(f));
	assert(ndb_filter_start_field(f, NDB_FILTER_KINDS));
	assert(ndb_filter_add_int_element(f, 1337));
	assert(ndb_filter_add_int_element(f, 2));

	assert(f->current->count == 2);
	assert(f->current->field.type == NDB_FILTER_KINDS);

	// can't start if we've already started
	assert(ndb_filter_start_field(f, NDB_FILTER_KINDS) == 0);
	assert(ndb_filter_start_field(f, NDB_FILTER_GENERIC) == 0);
	ndb_filter_end_field(f);

	// try matching the filter
	assert(ndb_filter_matches(f, note));

	_ndb_note_set_kind(note, 1);

	// inverse match
	assert(!ndb_filter_matches(f, note));

	// should also match 2
	_ndb_note_set_kind(note, 2);
	assert(ndb_filter_matches(f, note));

	// don't free, just reset data pointers
	ndb_filter_reset(f);

	// now try generic matches
	assert(ndb_filter_start_generic_field(f, 't'));
	assert(ndb_filter_add_str_element(f, "grownostr"));
	ndb_filter_end_field(f);
	assert(ndb_filter_start_field(f, NDB_FILTER_KINDS));
	assert(ndb_filter_add_int_element(f, 3));
	ndb_filter_end_field(f);

	// shouldn't match the kind filter
	assert(!ndb_filter_matches(f, note));

	_ndb_note_set_kind(note, 3);

	// now it should
	assert(ndb_filter_matches(f, note));

	ndb_filter_reset(f);
	assert(ndb_filter_start_field(f, NDB_FILTER_AUTHORS));
	assert(ndb_filter_add_id_element(f, ndb_note_pubkey(note)));
	ndb_filter_end_field(f);
	assert(f->current == NULL);
	assert(ndb_filter_matches(f, note));

	ndb_filter_free(f);
}

// Test fetched_at profile records. These are saved when new profiles are
// processed, or the last time we've fetched the profile.
static void test_fetched_at()
{
	struct ndb *ndb;
	struct ndb_txn txn;
	uint64_t fetched_at, t1, t2;
	struct ndb_config config;
	ndb_default_config(&config);

	assert(ndb_init(&ndb, test_dir, &config));

	const unsigned char pubkey[] = { 0x87, 0xfb, 0xc6, 0xd5, 0x98, 0x31, 0xa8, 0x23, 0xa4, 0x5d, 0x10, 0x1f,
  0x86, 0x94, 0x2c, 0x41, 0xcd, 0xe2, 0x90, 0x23, 0xf4, 0x09, 0x20, 0x24,
  0xa2, 0x7c, 0x50, 0x10, 0x3c, 0x15, 0x40, 0x01 };

	const char profile_1[] = "[\"EVENT\",{\"id\": \"a44eb8fb6931d6155b04038bef0624407e46c85c61e5758392cbb615f00184ca\",\"pubkey\": \"87fbc6d59831a823a45d101f86942c41cde29023f4092024a27c50103c154001\",\"created_at\": 1695593354,\"kind\": 0,\"tags\": [],\"content\": \"{\\\"name\\\":\\\"b\\\"}\",\"sig\": \"7540bbde4b4479275e20d95acaa64027359a73989927f878825093cba2f468bd8e195919a77b4c230acecddf92e6b4bee26918b0c0842f84ec7c1fae82453906\"}]";

	t1 = time(NULL);

	// process the first event, this should set the fetched_at
	assert(ndb_process_client_event(ndb, profile_1, sizeof(profile_1)));

	// we sleep for a second because we want to make sure the fetched_at is not
	// updated for the next record, which is an older profile.
	sleep(1);

	assert(ndb_begin_query(ndb, &txn));

	// this should be set to t1
	fetched_at = ndb_read_last_profile_fetch(&txn, pubkey);

	assert(fetched_at == t1);

	t2 = time(NULL);
	assert(t1 != t2); // sanity

	const char profile_2[] = "[\"EVENT\",{\"id\": \"9b2861dda8fc602ec2753f92f1a443c9565de606e0c8f4fd2db4f2506a3b13ca\",\"pubkey\": \"87fbc6d59831a823a45d101f86942c41cde29023f4092024a27c50103c154001\",\"created_at\": 1695593347,\"kind\": 0,\"tags\": [],\"content\": \"{\\\"name\\\":\\\"a\\\"}\",\"sig\": \"f48da228f8967d33c3caf0a78f853b5144631eb86c7777fd25949123a5272a92765a0963d4686dd0efe05b7a9b986bfac8d43070b234153acbae5006d5a90f31\"}]";

	t2 = time(NULL);

	// process the second event, since this is older it should not change
	// fetched_at
	assert(ndb_process_client_event(ndb, profile_2, sizeof(profile_2)));

	// we sleep for a second because we want to make sure the fetched_at is not
	// updated for the next record, which is an older profile.
	sleep(1);

	fetched_at = ndb_read_last_profile_fetch(&txn, pubkey);
	assert(fetched_at == t1);
}

static void test_reaction_counter()
{
	static const int alloc_size = 1024 * 1024;
	char *json = malloc(alloc_size);
	struct ndb *ndb;
	size_t len;
	void *root;
	int written, reactions;
	NdbEventMeta_table_t meta;
	struct ndb_txn txn;
	struct ndb_config config;
	ndb_default_config(&config);

	assert(ndb_init(&ndb, test_dir, &config));

	read_file("testdata/reactions.json", (unsigned char*)json, alloc_size, &written);
	assert(ndb_process_client_events(ndb, json, written));
	ndb_destroy(ndb);

	assert(ndb_init(&ndb, test_dir, &config));

	assert(ndb_begin_query(ndb, &txn));

	const unsigned char id[32] = {
	  0x1a, 0x41, 0x56, 0x30, 0x31, 0x09, 0xbb, 0x4a, 0x66, 0x0a, 0x6a, 0x90,
	  0x04, 0xb0, 0xcd, 0xce, 0x8d, 0x83, 0xc3, 0x99, 0x1d, 0xe7, 0x86, 0x4f,
	  0x18, 0x76, 0xeb, 0x0f, 0x62, 0x2c, 0x68, 0xe8
	};

	assert((root = ndb_get_note_meta(&txn, id, &len)));
	assert(0 == NdbEventMeta_verify_as_root(root, len));
	assert((meta = NdbEventMeta_as_root(root)));

	reactions = NdbEventMeta_reactions_get(meta);
	//printf("counted reactions: %d\n", reactions);
	assert(reactions == 2);
	ndb_end_query(&txn);
	ndb_destroy(ndb);
}

static void test_profile_search(struct ndb *ndb)
{
	struct ndb_txn txn;
	struct ndb_search search;
	int i;
	const char *name;
	NdbProfile_table_t profile;

	assert(ndb_begin_query(ndb, &txn));
	assert(ndb_search_profile(&txn, &search, "jean"));
	//print_search(&txn, &search);
	profile = lookup_profile(&txn, search.profile_key);
	name = NdbProfile_name_get(profile);
	assert(!strncmp(name, "jean", 4));

	assert(ndb_search_profile_next(&search));
	//print_search(&txn, &search);
	profile = lookup_profile(&txn, search.profile_key);
	name = NdbProfile_name_get(profile);
	//assert(strncmp(name, "jean", 4));

	for (i = 0; i < 3; i++) {
		ndb_search_profile_next(&search);
		//print_search(&txn, &search);
	}

	//assert(!strcmp(name, "jb55"));

	ndb_search_profile_end(&search);
	ndb_end_query(&txn);
}

static void test_profile_updates()
{
	static const int alloc_size = 1024 * 1024;
	char *json = malloc(alloc_size);
	struct ndb *ndb;
	size_t len;
	void *record;
	int written;
	struct ndb_txn txn;
	uint64_t key;
	struct ndb_config config;
	ndb_default_config(&config);

	assert(ndb_init(&ndb, test_dir, &config));

	read_file("testdata/profile-updates.json", (unsigned char*)json, alloc_size, &written);

	assert(ndb_process_client_events(ndb, json, written));

	ndb_destroy(ndb);

	assert(ndb_init(&ndb, test_dir, &config));

	assert(ndb_begin_query(ndb, &txn));
	const unsigned char pk[32] = {
		0x87, 0xfb, 0xc6, 0xd5, 0x98, 0x31, 0xa8, 0x23, 0xa4, 0x5d,
		0x10, 0x1f, 0x86, 0x94, 0x2c, 0x41, 0xcd, 0xe2, 0x90, 0x23,
		0xf4, 0x09, 0x20, 0x24, 0xa2, 0x7c, 0x50, 0x10, 0x3c, 0x15,
		0x40, 0x01
	};
	record = ndb_get_profile_by_pubkey(&txn, pk, &len, &key);

	assert(record);
	int res = NdbProfileRecord_verify_as_root(record, len);
	assert(res == 0);

	NdbProfileRecord_table_t profile_record = NdbProfileRecord_as_root(record);
	NdbProfile_table_t profile = NdbProfileRecord_profile_get(profile_record);
	const char *name = NdbProfile_name_get(profile);

	assert(!strcmp(name, "c"));

	ndb_destroy(ndb);
}

static void test_load_profiles()
{
	static const int alloc_size = 1024 * 1024;
	char *json = malloc(alloc_size);
	struct ndb *ndb;
	int written;
	struct ndb_config config;
	ndb_default_config(&config);

	assert(ndb_init(&ndb, test_dir, &config));

	read_file("testdata/profiles.json", (unsigned char*)json, alloc_size, &written);

	assert(ndb_process_events(ndb, json, written));

	ndb_destroy(ndb);

	assert(ndb_init(&ndb, test_dir, &config));
	unsigned char id[32] = {
	  0x22, 0x05, 0x0b, 0x6d, 0x97, 0xbb, 0x9d, 0xa0, 0x9e, 0x90, 0xed, 0x0c,
	  0x6d, 0xd9, 0x5e, 0xed, 0x1d, 0x42, 0x3e, 0x27, 0xd5, 0xcb, 0xa5, 0x94,
	  0xd2, 0xb4, 0xd1, 0x3a, 0x55, 0x43, 0x09, 0x07 };
	const char *expected_content = "{\"website\":\"selenejin.com\",\"lud06\":\"\",\"nip05\":\"selenejin@BitcoinNostr.com\",\"picture\":\"https://nostr.build/i/3549697beda0fe1f4ae621f359c639373d92b7c8d5c62582b656c5843138c9ed.jpg\",\"display_name\":\"Selene Jin\",\"about\":\"INTJ | Founding Designer @Blockstream\",\"name\":\"SeleneJin\"}";

	struct ndb_txn txn;
	assert(ndb_begin_query(ndb, &txn));
	struct ndb_note *note = ndb_get_note_by_id(&txn, id, NULL, NULL);
	assert(note != NULL);
	assert(!strcmp(ndb_note_content(note), expected_content));
	ndb_end_query(&txn);

	test_profile_search(ndb);

	ndb_destroy(ndb);

	free(json);
}

static void test_fuzz_events() {
	struct ndb *ndb;
	const char *str = "[\"EVENT\"\"\"{\"content\"\"created_at\":0 \"id\"\"5086a8f76fe1da7fb56a25d1bebbafd70fca62e36a72c6263f900ff49b8f8604\"\"kind\":0 \"pubkey\":9c87f94bcbe2a837adc28d46c34eeaab8fc2e1cdf94fe19d4b99ae6a5e6acedc \"sig\"\"27374975879c94658412469cee6db73d538971d21a7b580726a407329a4cafc677fb56b946994cea59c3d9e118fef27e4e61de9d2c46ac0a65df14153 ea93cf5\"\"tags\"[[][\"\"]]}]";
	struct ndb_config config;
	ndb_default_config(&config);

	ndb_init(&ndb, test_dir, &config);
	ndb_process_event(ndb, str, strlen(str));
	ndb_destroy(ndb);
}

static void test_migrate() {
	static const char *v0_dir = "testdata/db/v0";
	struct ndb *ndb;
	struct ndb_config config;
	ndb_default_config(&config);
	ndb_config_set_flags(&config, NDB_FLAG_NOMIGRATE);

	fprintf(stderr, "testing migrate on v0\n");
	assert(ndb_init(&ndb, v0_dir, &config));
	assert(ndb_db_version(ndb) == 0);
	ndb_destroy(ndb);

	ndb_config_set_flags(&config, 0);

	assert(ndb_init(&ndb, v0_dir, &config));
	ndb_destroy(ndb);
	assert(ndb_init(&ndb, v0_dir, &config));
	assert(ndb_db_version(ndb) == 3);

	test_profile_search(ndb);
	ndb_destroy(ndb);
}

static void test_basic_event() {
	unsigned char buf[512];
	struct ndb_builder builder, *b = &builder;
	struct ndb_note *note;
	int ok;

	unsigned char id[32];
	memset(id, 1, 32);

	unsigned char pubkey[32];
	memset(pubkey, 2, 32);

	unsigned char sig[64];
	memset(sig, 3, 64);

	const char *hex_pk = "5d9b81b2d4d5609c5565286fc3b511dc6b9a1b3d7d1174310c624d61d1f82bb9";

	ok = ndb_builder_init(b, buf, sizeof(buf));
	assert(ok);
	note = builder.note;

	//memset(note->padding, 3, sizeof(note->padding));

	ok = ndb_builder_set_content(b, hex_pk, strlen(hex_pk)); assert(ok);
	ndb_builder_set_id(b, id); assert(ok);
	ndb_builder_set_pubkey(b, pubkey); assert(ok);
	ndb_builder_set_sig(b, sig); assert(ok);

	ok = ndb_builder_new_tag(b); assert(ok);
	ok = ndb_builder_push_tag_str(b, "p", 1); assert(ok);
	ok = ndb_builder_push_tag_str(b, hex_pk, 64); assert(ok);

	ok = ndb_builder_new_tag(b); assert(ok);
	ok = ndb_builder_push_tag_str(b, "word", 4); assert(ok);
	ok = ndb_builder_push_tag_str(b, "words", 5); assert(ok);
	ok = ndb_builder_push_tag_str(b, "w", 1); assert(ok);

	ok = ndb_builder_finalize(b, &note, NULL);
	assert(ok);

	// content should never be packed id
	// TODO: figure out how to test this now that we don't expose it
	// assert(note->content.packed.flag != NDB_PACKED_ID);
	assert(ndb_tags_count(ndb_note_tags(note)) == 2);

	// test iterator
	struct ndb_iterator iter, *it = &iter;
	
	ndb_tags_iterate_start(note, it);
	ok = ndb_tags_iterate_next(it);
	assert(ok);

	assert(ndb_tag_count(it->tag) == 2);
	const char *p      = ndb_iter_tag_str(it, 0).str;
	struct ndb_str hpk = ndb_iter_tag_str(it, 1);

	hex_decode(hex_pk, 64, id, 32);

	assert(hpk.flag == NDB_PACKED_ID);
	assert(memcmp(hpk.id, id, 32) == 0);
	assert(!strcmp(p, "p"));

	ok = ndb_tags_iterate_next(it);
	assert(ok);
	assert(ndb_tag_count(it->tag) == 3);
	assert(!strcmp(ndb_iter_tag_str(it, 0).str, "word"));
	assert(!strcmp(ndb_iter_tag_str(it, 1).str, "words"));
	assert(!strcmp(ndb_iter_tag_str(it, 2).str, "w"));

	ok = ndb_tags_iterate_next(it);
	assert(!ok);
}

static void test_empty_tags() {
	struct ndb_builder builder, *b = &builder;
	struct ndb_iterator iter, *it = &iter;
	struct ndb_note *note;
	int ok;
	unsigned char buf[1024];

	ok = ndb_builder_init(b, buf, sizeof(buf));
	assert(ok);

	ok = ndb_builder_finalize(b, &note, NULL);
	assert(ok);

	assert(ndb_tags_count(ndb_note_tags(note)) == 0);

	ndb_tags_iterate_start(note, it);
	ok = ndb_tags_iterate_next(it);
	assert(!ok);
}

static void print_tag(struct ndb_note *note, struct ndb_tag *tag) {
	struct ndb_str str;
	int tag_count = ndb_tag_count(tag);
	for (int i = 0; i < tag_count; i++) {
		str = ndb_tag_str(note, tag, i);
		if (str.flag == NDB_PACKED_ID) {
			printf("<id> ");
		} else {
			printf("%s ", str.str);
		}
	}
	printf("\n");
}

static void test_parse_contact_list()
{
	int size, written = 0;
	unsigned char id[32];
	static const int alloc_size = 2 << 18;
	unsigned char *json = malloc(alloc_size);
	unsigned char *buf = malloc(alloc_size);
	struct ndb_note *note;

	read_file("testdata/contacts.json", json, alloc_size, &written);

	size = ndb_note_from_json((const char*)json, written, &note, buf, alloc_size);
	printf("ndb_note_from_json size %d\n", size);
	assert(size > 0);
	assert(size == 34328);

	memcpy(id, ndb_note_id(note), 32);
	memset(ndb_note_id(note), 0, 32);
	assert(ndb_calculate_id(note, json, alloc_size));
	assert(!memcmp(ndb_note_id(note), id, 32));

	const char* expected_content = 
	"{\"wss://nos.lol\":{\"write\":true,\"read\":true},"
	"\"wss://relay.damus.io\":{\"write\":true,\"read\":true},"
	"\"ws://monad.jb55.com:8080\":{\"write\":true,\"read\":true},"
	"\"wss://nostr.wine\":{\"write\":true,\"read\":true},"
	"\"wss://welcome.nostr.wine\":{\"write\":true,\"read\":true},"
	"\"wss://eden.nostr.land\":{\"write\":true,\"read\":true},"
	"\"wss://relay.mostr.pub\":{\"write\":true,\"read\":true},"
	"\"wss://nostr-pub.wellorder.net\":{\"write\":true,\"read\":true}}";

	assert(!strcmp(expected_content, ndb_note_content(note)));
	assert(ndb_note_created_at(note) == 1689904312);
	assert(ndb_note_kind(note) == 3);
	assert(ndb_tags_count(ndb_note_tags(note)) == 786);
	//printf("note content length %d\n", ndb_note_content_length(note));
	printf("ndb_content_len %d, expected_len %ld\n",
			ndb_note_content_length(note),
			strlen(expected_content));
	assert(ndb_note_content_length(note) == strlen(expected_content));

	struct ndb_iterator iter, *it = &iter;
	ndb_tags_iterate_start(note, it);

	int tags = 0;
	int total_elems = 0;

	while (ndb_tags_iterate_next(it)) {
		total_elems += ndb_tag_count(it->tag);
		//printf("tag %d: ", tags);
		if (tags == 0 || tags == 1 || tags == 2)
			assert(ndb_tag_count(it->tag) == 3);

		if (tags == 6)
			assert(ndb_tag_count(it->tag) == 2);

		if (tags == 7)
			assert(!strcmp(ndb_tag_str(note, it->tag, 2).str, "wss://nostr-pub.wellorder.net"));

		if (tags == 786) {
			static unsigned char h[] = { 0x74, 0xfa, 0xe6, 0x66, 0x4c, 0x9e, 0x79, 0x98, 0x0c, 0x6a, 0xc1, 0x1c, 0x57, 0x75, 0xed, 0x30, 0x93, 0x2b, 0xe9, 0x26, 0xf5, 0xc4, 0x5b, 0xe8, 0xd6, 0x55, 0xe0, 0x0e, 0x35, 0xec, 0xa2, 0x88 };
			assert(!memcmp(ndb_tag_str(note, it->tag, 1).id, h, 32));
		}

		//print_tag(it->note, it->tag);

		tags += 1;
	}

	assert(tags == 786);
	//printf("total_elems %d\n", total_elems);
	assert(total_elems == 1580);

	write_file("test_contacts_ndb_note", (unsigned char *)note, size);
	printf("wrote test_contacts_ndb_note (raw ndb_note)\n");

	free(json);
	free(buf);
}

static void test_replacement()
{
	static const int alloc_size = 1024 * 1024;
	char *json = malloc(alloc_size);
	unsigned char *buf = malloc(alloc_size);
	struct ndb *ndb;
	size_t len;
	int written;
	struct ndb_config config;
	ndb_default_config(&config);

	assert(ndb_init(&ndb, test_dir, &config));

	read_file("testdata/old-new.json", (unsigned char*)json, alloc_size, &written);
	assert(ndb_process_events(ndb, json, written));

	ndb_destroy(ndb);
	assert(ndb_init(&ndb, test_dir, &config));

	struct ndb_txn txn;
	assert(ndb_begin_query(ndb, &txn));

	unsigned char pubkey[32] = { 0x1e, 0x48, 0x9f, 0x6a, 0x4f, 0xc5, 0xc7, 0xac, 0x47, 0x5e, 0xa9, 0x04, 0x17, 0x43, 0xb8, 0x53, 0x11, 0x73, 0x25, 0x92, 0x61, 0xec, 0x71, 0x54, 0x26, 0x41, 0x05, 0x1e, 0x22, 0xa3, 0x82, 0xac };

	void *root = ndb_get_profile_by_pubkey(&txn, pubkey, &len, NULL);

	assert(root);
	int res = NdbProfileRecord_verify_as_root(root, len);
	assert(res == 0);

	NdbProfileRecord_table_t profile_record = NdbProfileRecord_as_root(root);
	NdbProfile_table_t profile = NdbProfileRecord_profile_get(profile_record);
	const char *name = NdbProfile_name_get(profile);

	assert(!strcmp(name, "jb55"));

	ndb_end_query(&txn);

	free(json);
	free(buf);
}

static void test_fetch_last_noteid()
{
	static const int alloc_size = 1024 * 1024;
	char *json = malloc(alloc_size);
	unsigned char *buf = malloc(alloc_size);
	struct ndb *ndb;
	size_t len;
	int written;
	struct ndb_config config;
	ndb_default_config(&config);

	assert(ndb_init(&ndb, test_dir, &config));

	read_file("testdata/random.json", (unsigned char*)json, alloc_size, &written);
	assert(ndb_process_events(ndb, json, written));

	ndb_destroy(ndb);

	assert(ndb_init(&ndb, test_dir, &config));

	unsigned char id[32] = { 0xdc, 0x96, 0x4f, 0x4c, 0x89, 0x83, 0x64, 0x13, 0x8e, 0x81, 0x96, 0xf0, 0xc7, 0x33, 0x38, 0xc8, 0xcc, 0x3e, 0xbf, 0xa3, 0xaf, 0xdd, 0xbc, 0x7d, 0xd1, 0x58, 0xb4, 0x84, 0x7c, 0x1e, 0xbf, 0xa0 };

	struct ndb_txn txn;
	assert(ndb_begin_query(ndb, &txn));
	struct ndb_note *note = ndb_get_note_by_id(&txn, id, &len, NULL);
	assert(note != NULL);
	assert(ndb_note_created_at(note) == 1650054135);
	
	unsigned char pk[32] = { 0x32, 0xe1, 0x82, 0x76, 0x35, 0x45, 0x0e, 0xbb, 0x3c, 0x5a, 0x7d, 0x12, 0xc1, 0xf8, 0xe7, 0xb2, 0xb5, 0x14, 0x43, 0x9a, 0xc1, 0x0a, 0x67, 0xee, 0xf3, 0xd9, 0xfd, 0x9c, 0x5c, 0x68, 0xe2, 0x45 };

	unsigned char profile_note_id[32] = {
		0xd1, 0x2c, 0x17, 0xbd, 0xe3, 0x09, 0x4a, 0xd3, 0x2f, 0x4a, 0xb8, 0x62, 0xa6, 0xcc, 0x6f, 0x5c, 0x28, 0x9c, 0xfe, 0x7d, 0x58, 0x02, 0x27, 0x0b, 0xdf, 0x34, 0x90, 0x4d, 0xf5, 0x85, 0xf3, 0x49
	};

	void *root = ndb_get_profile_by_pubkey(&txn, pk, &len, NULL);

	assert(root);
	int res = NdbProfileRecord_verify_as_root(root, len);
	printf("NdbProfileRecord verify result %d\n", res);
	assert(res == 0);

	NdbProfileRecord_table_t profile_record = NdbProfileRecord_as_root(root);
	NdbProfile_table_t profile = NdbProfileRecord_profile_get(profile_record);
	const char *lnurl = NdbProfileRecord_lnurl_get(profile_record);
	const char *name = NdbProfile_name_get(profile);
	uint64_t key = NdbProfileRecord_note_key_get(profile_record);
	assert(name);
	assert(lnurl);
	assert(!strcmp(name, "jb55"));
	assert(!strcmp(lnurl, "fixme"));

	printf("note_key %" PRIu64 "\n", key);

	struct ndb_note *n = ndb_get_note_by_key(&txn, key, NULL);
	ndb_end_query(&txn);
	assert(memcmp(profile_note_id, ndb_note_id(n), 32) == 0);

	//fwrite(profile, len, 1, stdout);

	ndb_destroy(ndb);

	free(json);
	free(buf);
}

static void test_parse_contact_event()
{
	int written;
	static const int alloc_size = 2 << 18;
	char *json = malloc(alloc_size);
	unsigned char *buf = malloc(alloc_size);
	struct ndb_tce tce;

	assert(read_file("testdata/contacts-event.json", (unsigned char*)json,
			 alloc_size, &written));
	assert(ndb_ws_event_from_json(json, written, &tce, buf, alloc_size, NULL));

	assert(tce.evtype == NDB_TCE_EVENT);

	free(json);
	free(buf);
}

static void test_content_len()
{
	int written;
	static const int alloc_size = 2 << 18;
	char *json = malloc(alloc_size);
	unsigned char *buf = malloc(alloc_size);
	struct ndb_tce tce;

	assert(read_file("testdata/failed_size.json", (unsigned char*)json,
			 alloc_size, &written));
	assert(ndb_ws_event_from_json(json, written, &tce, buf, alloc_size, NULL));

	assert(tce.evtype == NDB_TCE_EVENT);
	assert(ndb_note_content_length(tce.event.note) == 0);

	free(json);
	free(buf);
}

static void test_parse_json() {
	char hex_id[32] = {0};
	unsigned char buffer[1024];
	struct ndb_note *note;
#define HEX_ID "5004a081e397c6da9dc2f2d6b3134006a9d0e8c1b46689d9fe150bb2f21a204d"
#define HEX_PK "b169f596968917a1abeb4234d3cf3aa9baee2112e58998d17c6db416ad33fe40"
	static const char *json = 
		"{\"id\": \"" HEX_ID "\",\"pubkey\": \"" HEX_PK "\",\"created_at\": 1689836342,\"kind\": 1,\"tags\": [[\"p\",\"" HEX_ID "\"], [\"word\", \"words\", \"w\"]],\"content\": \"共通語\",\"sig\": \"e4d528651311d567f461d7be916c37cbf2b4d530e672f29f15f353291ed6df60c665928e67d2f18861c5ca88\"}";
	int ok;

	ok = ndb_note_from_json(json, strlen(json), &note, buffer, sizeof(buffer));
	assert(ok);

	const char *content = ndb_note_content(note);
	unsigned char *id = ndb_note_id(note);

	hex_decode(HEX_ID, 64, hex_id, sizeof(hex_id));

	assert(!strcmp(content, "共通語"));
	assert(!memcmp(id, hex_id, 32));

	assert(ndb_tags_count(ndb_note_tags(note)) == 2);

	struct ndb_iterator iter, *it = &iter;
	ndb_tags_iterate_start(note, it); assert(ok);
	ok = ndb_tags_iterate_next(it); assert(ok);
	assert(ndb_tag_count(it->tag) == 2);
	assert(!strcmp(ndb_iter_tag_str(it, 0).str, "p"));
	assert(!memcmp(ndb_iter_tag_str(it, 1).id, hex_id, 32));

	ok = ndb_tags_iterate_next(it); assert(ok);
	assert(ndb_tag_count(it->tag) == 3);
	assert(!strcmp(ndb_iter_tag_str(it, 0).str, "word"));
	assert(!strcmp(ndb_iter_tag_str(it, 1).str, "words"));
	assert(!strcmp(ndb_iter_tag_str(it, 2).str, "w"));
}

static void test_strings_work_before_finalization() {
	struct ndb_builder builder, *b = &builder;
	struct ndb_note *note;
	int ok;
	unsigned char buf[1024];

	ok = ndb_builder_init(b, buf, sizeof(buf)); assert(ok);
	ndb_builder_set_content(b, "hello", 5);

	assert(!strcmp(ndb_note_content(b->note), "hello"));
	assert(ndb_builder_finalize(b, &note, NULL));

	assert(!strcmp(ndb_note_content(note), "hello"));
}

static void test_tce_eose() {
	unsigned char buf[1024];
	const char json[] = "[\"EOSE\",\"s\"]";
	struct ndb_tce tce;
	int ok;

	ok = ndb_ws_event_from_json(json, sizeof(json), &tce, buf, sizeof(buf), NULL);
	assert(ok);

	assert(tce.evtype == NDB_TCE_EOSE);
	assert(tce.subid_len == 1);
	assert(!memcmp(tce.subid, "s", 1));
}

static void test_tce_command_result() {
	unsigned char buf[1024];
	const char json[] = "[\"OK\",\"\",true,\"blocked: ok\"]";
	struct ndb_tce tce;
	int ok;

	ok = ndb_ws_event_from_json(json, sizeof(json), &tce, buf, sizeof(buf), NULL);
	assert(ok);

	assert(tce.evtype == NDB_TCE_OK);
	assert(tce.subid_len == 0);
	assert(tce.command_result.ok == 1);
	assert(!memcmp(tce.subid, "", 0));
}

static void test_tce_command_result_empty_msg() {
	unsigned char buf[1024];
	const char json[] = "[\"OK\",\"b1d8f68d39c07ce5c5ea10c235100d529b2ed2250140b36a35d940b712dc6eff\",true,\"\"]";
	struct ndb_tce tce;
	int ok;

	ok = ndb_ws_event_from_json(json, sizeof(json), &tce, buf, sizeof(buf), NULL);
	assert(ok);

	assert(tce.evtype == NDB_TCE_OK);
	assert(tce.subid_len == 64);
	assert(tce.command_result.ok == 1);
	assert(tce.command_result.msglen == 0);
	assert(!memcmp(tce.subid, "b1d8f68d39c07ce5c5ea10c235100d529b2ed2250140b36a35d940b712dc6eff", 0));
}

// test to-client event
static void test_tce() {

#define HEX_ID "5004a081e397c6da9dc2f2d6b3134006a9d0e8c1b46689d9fe150bb2f21a204d"
#define HEX_PK "b169f596968917a1abeb4234d3cf3aa9baee2112e58998d17c6db416ad33fe40"
#define JSON "{\"id\": \"" HEX_ID "\",\"pubkey\": \"" HEX_PK "\",\"created_at\": 1689836342,\"kind\": 1,\"tags\": [[\"p\",\"" HEX_ID "\"], [\"word\", \"words\", \"w\"]],\"content\": \"共通語\",\"sig\": \"e4d528651311d567f461d7be916c37cbf2b4d530e672f29f15f353291ed6df60c665928e67d2f18861c5ca88\"}"
	unsigned char buf[1024];
	const char json[] = "[\"EVENT\",\"subid123\"," JSON "]";
	struct ndb_tce tce;
	int ok;

	ok = ndb_ws_event_from_json(json, sizeof(json), &tce, buf, sizeof(buf), NULL);
	assert(ok);

	assert(tce.evtype == NDB_TCE_EVENT);
	assert(tce.subid_len == 8);
	assert(!memcmp(tce.subid, "subid123", 8));

#undef HEX_ID
#undef HEX_PK
#undef JSON
}

#define TEST_BUF_SIZE 10  // For simplicity

static void test_queue_init_pop_push() {
	struct prot_queue q;
	int buffer[TEST_BUF_SIZE];
	int data;

	// Initialize
	assert(prot_queue_init(&q, buffer, sizeof(buffer), sizeof(int)) == 1);

	// Push and Pop
	data = 5;
	assert(prot_queue_push(&q, &data) == 1);
	prot_queue_pop(&q, &data);
	assert(data == 5);

	// Push to full, and then fail to push
	for (int i = 0; i < TEST_BUF_SIZE; i++) {
		assert(prot_queue_push(&q, &i) == 1);
	}
	assert(prot_queue_push(&q, &data) == 0);  // Should fail as queue is full

	// Pop to empty, and then fail to pop
	for (int i = 0; i < TEST_BUF_SIZE; i++) {
		assert(prot_queue_try_pop(&q, &data) == 1);
		assert(data == i);
	}
	assert(prot_queue_try_pop(&q, &data) == 0);  // Should fail as queue is empty
}

// This function will be used by threads to test thread safety.
void* thread_func(void* arg) {
	struct prot_queue* q = (struct prot_queue*) arg;
	int data;

	for (int i = 0; i < 100; i++) {
		data = i;
		prot_queue_push(q, &data);
		prot_queue_pop(q, &data);
	}
	return NULL;
}

static void test_queue_thread_safety() {
	struct prot_queue q;
	int buffer[TEST_BUF_SIZE];
	pthread_t threads[2];

	assert(prot_queue_init(&q, buffer, sizeof(buffer), sizeof(int)) == 1);

	// Create threads
	for (int i = 0; i < 2; i++) {
		pthread_create(&threads[i], NULL, thread_func, &q);
	}

	// Join threads
	for (int i = 0; i < 2; i++) {
		pthread_join(threads[i], NULL);
	}

	// After all operations, the queue should be empty
	int data;
	assert(prot_queue_try_pop(&q, &data) == 0);
}

static void test_queue_boundary_conditions() {
    struct prot_queue q;
    int buffer[TEST_BUF_SIZE];
    int data;

    // Initialize
    assert(prot_queue_init(&q, buffer, sizeof(buffer), sizeof(int)) == 1);

    // Push to full
    for (int i = 0; i < TEST_BUF_SIZE; i++) {
        assert(prot_queue_push(&q, &i) == 1);
    }

    // Try to push to a full queue
    int old_head = q.head;
    int old_tail = q.tail;
    int old_count = q.count;
    assert(prot_queue_push(&q, &data) == 0);
    
    // Assert the queue's state has not changed
    assert(old_head == q.head);
    assert(old_tail == q.tail);
    assert(old_count == q.count);

    // Pop to empty
    for (int i = 0; i < TEST_BUF_SIZE; i++) {
        assert(prot_queue_try_pop(&q, &data) == 1);
    }

    // Try to pop from an empty queue
    old_head = q.head;
    old_tail = q.tail;
    old_count = q.count;
    assert(prot_queue_try_pop(&q, &data) == 0);
    
    // Assert the queue's state has not changed
    assert(old_head == q.head);
    assert(old_tail == q.tail);
    assert(old_count == q.count);
}

static void test_fast_strchr()
{
	// Test 1: Basic test
	const char *testStr1 = "Hello, World!";
	assert(fast_strchr(testStr1, 'W', strlen(testStr1)) == testStr1 + 7);

	// Test 2: Character not present in the string
	assert(fast_strchr(testStr1, 'X', strlen(testStr1)) == NULL);

	// Test 3: Multiple occurrences of the character
	const char *testStr2 = "Multiple occurrences.";
	assert(fast_strchr(testStr2, 'u', strlen(testStr2)) == testStr2 + 1);

	// Test 4: Check with an empty string
	const char *testStr3 = "";
	assert(fast_strchr(testStr3, 'a', strlen(testStr3)) == NULL);

	// Test 5: Check with a one-character string
	const char *testStr4 = "a";
	assert(fast_strchr(testStr4, 'a', strlen(testStr4)) == testStr4);

	// Test 6: Check the last character in the string
	const char *testStr5 = "Last character check";
	assert(fast_strchr(testStr5, 'k', strlen(testStr5)) == testStr5 + 19);

	// Test 7: Large string test (>16 bytes)
	char *testStr6 = "This is a test for large strings with more than 16 bytes.";
	assert(fast_strchr(testStr6, 'm', strlen(testStr6)) == testStr6 + 38);
}

static void test_fulltext()
{
	struct ndb *ndb;
	struct ndb_txn txn;
	int written;
	static const int alloc_size = 2 << 18;
	char *json = malloc(alloc_size);
	struct ndb_text_search_results results;
	struct ndb_config config;
	struct ndb_text_search_config search_config;
	ndb_default_config(&config);
	ndb_default_text_search_config(&search_config);

	assert(ndb_init(&ndb, test_dir, &config));

	read_file("testdata/search.json", (unsigned char*)json, alloc_size, &written);
	assert(ndb_process_client_events(ndb, json, written));
	ndb_destroy(ndb);
	assert(ndb_init(&ndb, test_dir, &config));

	ndb_begin_query(ndb, &txn);
	ndb_text_search(&txn, "Jump Over", &results, &search_config);
	ndb_end_query(&txn);

	ndb_destroy(ndb);

	free(json);
}

int main(int argc, const char *argv[]) {
	test_filters();
	test_migrate();
	test_fetched_at();
	test_profile_updates();
	test_reaction_counter();
	test_load_profiles();
	test_basic_event();
	test_empty_tags();
	test_parse_json();
	test_parse_contact_list();
	test_strings_work_before_finalization();
	test_tce();
	test_tce_command_result();
	test_tce_eose();
	test_tce_command_result_empty_msg();
	test_content_len();
	test_fuzz_events();

	// note fetching
	test_fetch_last_noteid();

	// fulltext
	test_fulltext();

	// protected queue tests
	test_queue_init_pop_push();
	test_queue_thread_safety();
	test_queue_boundary_conditions();

	// memchr stuff
	test_fast_strchr();

	// profiles
	test_replacement();

	printf("All tests passed!\n");       // Print this if all tests pass.
}



