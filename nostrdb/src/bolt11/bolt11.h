#ifndef LIGHTNING_COMMON_BOLT11_H
#define LIGHTNING_COMMON_BOLT11_H
/* Borrowed from CLN's common/bolt11.[ch] implementation as of v24.08rc1 */

#include "ccan/short_types/short_types.h"
#include "hash_u5.h"
#include "amount.h"
#include "ccan/list/list.h"
#include "amount.h"
#include "node_id.h"

/* We only have 10 bits for the field length, meaning < 640 bytes */
#define BOLT11_FIELD_BYTE_LIMIT ((1 << 10) * 5 / 8)

/* BOLT #11:
 * * `c` (24): `data_length` variable.
 *    `min_final_cltv_expiry` to use for the last HTLC in the route.
 *    Default is 18 if not specified.
 */
#define DEFAULT_FINAL_CLTV_DELTA 18

struct feature_set;

struct bolt11_field {
    struct list_node list;

    char tag;
    u5 *data;
};

struct bolt11 {
    u64 timestamp;
    struct amount_msat *msat; /* NULL if not specified. */

    /* description_hash valid if and only if description is NULL. */
    const char *description;
    struct sha256 *description_hash;

    /* How many seconds to pay from @timestamp above. */
    u64 expiry;
};

/* Does not check signature, nor extract node.  */
struct bolt11 *bolt11_decode_minimal(const tal_t *ctx, const char *str, char **fail);

#endif /* LIGHTNING_COMMON_BOLT11_H */
