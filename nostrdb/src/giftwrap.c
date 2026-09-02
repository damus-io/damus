

/* unwrap a giftwrap note */

/* inputs:
 *   
 *    the giftwrap note
 *    recvkey: the keypair of the person receiving the note
 *
 */
int ndb_giftwrap_unwrap(struct ndb_note *note, struct ndb_keypair *pair,
			unsigned char *buf, size_t bufsize)
{
	const char *contents;
	uint32_t content_len;

	contents = ndb_note_content(note);
	content_len = ndb_note_content_length(note);

	return ndb_giftwrap_unwrap_contents(
			content,
			content_len,
			recv_key,
			buf, bufsize);
}

int ndb_giftwrap_unwrap_contents(const char *content, uint32_t content_len,
				 struct ndb_keypair *pair,
				 unsigned char *buf,
				 size_t bufsize)
{
	/* the giftwrap contains a pubkey of the person retrieving
	 * the wrap. We ignore this and just use the passed in recv_key
	 * in case we want some covert use-cases.
	 *
	 * decryption can still fail if this is a user error, so we will
	 * return an error when that happens
	 */

	nip44_decrypt(key->seckey, content, content_len, buf, buf_len);
}
