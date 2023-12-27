
#ifndef NDB_INVOICE_H
#define NDB_INVOICE_H

#include <inttypes.h>
#include "cursor.h"

struct bolt11;

struct ndb_invoice {
	unsigned char version;
	uint64_t amount;
	uint64_t timestamp;
	uint64_t expiry;
	char *description;
	unsigned char *description_hash;
};

// ENCODING
int ndb_encode_invoice(struct cursor *cur, struct bolt11 *invoice);
int ndb_decode_invoice(struct cursor *cur, struct ndb_invoice *invoice);

#endif /* NDB_INVOICE_H */
