#include "config.h"
#include <assert.h>
#include "array_size.h"
#include "mem.h"
#include "hex.h"
#include "talstr.h"
#include "node_id.h"

/* Convert from pubkey to compressed pubkey. */
/*
void node_id_from_pubkey(struct node_id *id, const struct pubkey *key)
{
    size_t outlen = ARRAY_SIZE(id->k);
    if (!secp256k1_ec_pubkey_serialize(secp256k1_ctx, id->k, &outlen,
                       &key->pubkey,
                       SECP256K1_EC_COMPRESSED))
        abort();
}

WARN_UNUSED_RESULT
bool pubkey_from_node_id(struct pubkey *key, const struct node_id *id)
{
    return secp256k1_ec_pubkey_parse(secp256k1_ctx, &key->pubkey,
                     memcheck(id->k, sizeof(id->k)),
                     sizeof(id->k));
}

WARN_UNUSED_RESULT
bool point32_from_node_id(struct point32 *key, const struct node_id *id)
{
    struct pubkey k;
    if (!pubkey_from_node_id(&k, id))
        return false;
    return secp256k1_xonly_pubkey_from_pubkey(secp256k1_ctx, &key->pubkey,
                          NULL, &k.pubkey) == 1;
}
*/

char *tal_hexstr(const tal_t *ctx, const void *data, size_t len)
{
    char *str = tal_arr(ctx, char, hex_str_size(len));
    hex_encode(data, len, str, hex_str_size(len));
    return str;
}


/* Convert to hex string of SEC1 encoding */
char *node_id_to_hexstr(const tal_t *ctx, const struct node_id *id)
{
    return tal_hexstr(ctx, id->k, sizeof(id->k));
}

/* Convert from hex string of SEC1 encoding */

bool node_id_from_hexstr(const char *str, size_t slen, struct node_id *id)
{
    return hex_decode(str, slen, id->k, sizeof(id->k));
    /*    && node_id_valid(id);*/
}

int node_id_cmp(const struct node_id *a, const struct node_id *b)
{
    return memcmp(a->k, b->k, sizeof(a->k));
}
