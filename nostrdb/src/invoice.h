
#ifndef NDB_INVOICE_H
#define NDB_INVOICE_H

#include <inttypes.h>
#include "cursor.h"
#include "nostrdb.h"

struct bolt11;

// ENCODING
int ndb_encode_invoice(struct cursor *cur, struct bolt11 *invoice);
int ndb_decode_invoice(struct cursor *cur, struct ndb_invoice *invoice);

#endif /* NDB_INVOICE_H */
