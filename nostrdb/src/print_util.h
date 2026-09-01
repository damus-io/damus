#include "hex.h"
#include "lmdb.h"
#include "nostrdb.h"
#include <stdio.h>

static void print_hex(unsigned char* data, size_t size) {
	size_t i;
	for (i = 0; i < size; i++) {
		printf("%02x", data[i]);
	}
}

static void ndb_print_text_search_key(int bytes_size, struct ndb_text_search_key *key)
{
	printf("K<'%.*s' %" PRIu64 " %" PRIu64 " note_id:%" PRIu64 " bytes:%d>", (int)key->str_len, key->str,
						    key->word_index,
						    key->timestamp,
						    key->note_id,
						    bytes_size
						    );

}

static void print_tag_kv(struct ndb_txn *txn, MDB_val *k, MDB_val *v)
{
	char hex_id[65], c;
	struct ndb_note *note;
	uint64_t ts;

	ts = *(uint64_t*)((uint8_t*)k->mv_data+(k->mv_size-8));

	c = ((const char*)k->mv_data)[0];

	// TODO: p tags, etc
	if ((c == 'e' || c == 'p' || c == 'q') && k->mv_size == (1 + 32 + 8)) {
		printf("note_tags '%c", c);
		print_hex((uint8_t*)k->mv_data+1, 32);
		printf("' %" PRIu64, ts);
	} else {
		printf("note_tags '%.*s' %" PRIu64, (int)k->mv_size-8,
		       (const char *)k->mv_data, ts);
	}

	ts = *(uint64_t*)v->mv_data;

	note = ndb_get_note_by_key(txn, ts, NULL);
	assert(note);
	hex_encode(ndb_note_id(note), 32, hex_id);
	printf(" note_key:%" PRIu64 " id:%s\n", ts, hex_id);
}

static void print_hex_stream(FILE *stream, unsigned char* data, size_t size) {
	size_t i;
	for (i = 0; i < size; i++) {
		fprintf(stream, "%02x", data[i]);
	}
}


