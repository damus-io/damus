
#include "cursor.h"
#include "invoice.h"
#include "nostrdb.h"
#include "bolt11/bolt11.h"
#include "bolt11/amount.h"

int ndb_encode_invoice(struct cursor *cur, struct bolt11 *invoice) {
	if (!invoice->description && !invoice->description_hash)
		return 0;

	if (!cursor_push_byte(cur, 1))
		return 0;

	if (!cursor_push_varint(cur, invoice->msat == NULL ? 0 : invoice->msat->millisatoshis))
		return 0;

	if (!cursor_push_varint(cur, invoice->timestamp))
		return 0;

	if (!cursor_push_varint(cur, invoice->expiry))
		return 0;

	if (invoice->description) {
		if (!cursor_push_byte(cur, 1))
			return 0;
		if (!cursor_push_c_str(cur, invoice->description))
			return 0;
	} else {
		if (!cursor_push_byte(cur, 2))
			return 0;
		if (!cursor_push(cur, invoice->description_hash->u.u8, 32))
			return 0;
	}

	return 1;
}

int ndb_decode_invoice(struct cursor *cur, struct ndb_invoice *invoice)
{
	unsigned char desc_type;
	if (!cursor_pull_byte(cur, &invoice->version))
		return 0;

	if (!cursor_pull_varint(cur, &invoice->amount))
		return 0;

	if (!cursor_pull_varint(cur, &invoice->timestamp))
		return 0;

	if (!cursor_pull_varint(cur, &invoice->expiry))
		return 0;

	if (!cursor_pull_byte(cur, &desc_type))
		return 0;

	if (desc_type == 1) {
		if (!cursor_pull_c_str(cur, (const char**)&invoice->description))
			return 0;
	} else if (desc_type == 2) {
		invoice->description_hash = cur->p;
		if (!cursor_skip(cur, 32))
			return 0;
	} else {
		return 0;
	}

	return 1;
}
