
static void ndb_print_text_search_key(struct ndb_text_search_key *key)
{
	fprintf(stderr,"K<'%.*s' %" PRIu64 " %" PRIu64 " note_id:%" PRIu64 ">", key->str_len, key->str,
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

static void print_hex_stream(FILE *stream, unsigned char* data, size_t size) {
	size_t i;
	for (i = 0; i < size; i++) {
		fprintf(stream, "%02x", data[i]);
	}
}


