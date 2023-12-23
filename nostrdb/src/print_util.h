
static void ndb_print_text_search_key(struct ndb_text_search_key *key)
{
	printf("K<'%.*s' %" PRIu64 " %" PRIu64 " note_id:%" PRIu64 ">", key->str_len, key->str,
						    key->word_index,
						    key->timestamp,
						    key->note_id);
}

static void print_hex(unsigned char* data, size_t size) {
	size_t i;
	for (i = 0; i < size; i++) {
		printf("%02x", data[i]);
	}
}


static void ndb_print_text_search_result(struct ndb_txn *txn,
		struct ndb_text_search_result *r)
{
	size_t len;
	struct ndb_note *note;

	ndb_print_text_search_key(&r->key);

	if (!(note = ndb_get_note_by_key(txn, r->key.note_id, &len))) {
		printf(": note not found");
		return;
	}

	printf(" ");
	print_hex(ndb_note_id(note), 32);

	printf("\n%s\n\n---\n", ndb_note_content(note));
}

