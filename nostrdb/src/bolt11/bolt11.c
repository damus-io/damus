//
//  bolt11.c
//  damus
//
//  Created by William Casarin on 2022-10-18.
//

#include "bolt11.h"

//#include "address.h"
//#include "script.h"
#include "bech32.h"
#include "ccan/utf8/utf8.h"
#include "ccan/compiler//compiler.h"
#include "ccan/endian/endian.h"
#include "ccan/list/list.h"
#include "ccan/tal/str/str.h"
#include "ccan/tal/tal.h"
#include "node_id.h"
#include "bech32_util.h"
#include "bolt11.h"
#include "amount.h"
#include "ccan/array_size/array_size.h"
#include "ccan/structeq/structeq.h"

//#include "features.h"
#include <errno.h>
#include <inttypes.h>
#include <assert.h>

#define MSAT_PER_SAT ((u64)1000)
#define SAT_PER_BTC ((u64)100000000)
#define MSAT_PER_BTC (MSAT_PER_SAT * SAT_PER_BTC)

struct multiplier {
    const char letter;
    /* We can't represent p postfix to msat, so we multiply this by 10 */
    u64 m10;
};

/* BOLT #11:
 *
 * The following `multiplier` letters are defined:
 *
 * * `m` (milli): multiply by 0.001
 * * `u` (micro): multiply by 0.000001
 * * `n` (nano): multiply by 0.000000001
 * * `p` (pico): multiply by 0.000000000001
 */
static struct multiplier multipliers[] = {
    { 'm', 10 * MSAT_PER_BTC / 1000 },
    { 'u', 10 * MSAT_PER_BTC / 1000000 },
    { 'n', 10 * MSAT_PER_BTC / 1000000000 },
    { 'p', 10 * MSAT_PER_BTC / 1000000000000ULL }
};

/* If pad is false, we discard any bits which don't fit in the last byte.
 * Otherwise we add an extra byte */
static bool pull_bits(struct hash_u5 *hu5,
              u5 **data, size_t *data_len, void *dst, size_t nbits,
              bool pad)
{
    size_t n5 = nbits / 5;
    size_t len = 0;

    if (nbits % 5)
        n5++;

    if (*data_len < n5)
        return false;
    if (!bech32_convert_bits(dst, &len, 8, *data, n5, 5, pad))
        return false;
    if (hu5)
        hash_u5(hu5, *data, n5);
    *data += n5;
    *data_len -= n5;

    return true;
}

/* For pulling fields where we should have checked it will succeed already. */
#ifndef NDEBUG
#define pull_bits_certain(hu5, data, data_len, dst, nbits, pad)         \
    assert(pull_bits((hu5), (data), (data_len), (dst), (nbits), (pad)))
#else
#define pull_bits_certain pull_bits
#endif

/* Helper for pulling a variable-length big-endian int. */
static bool pull_uint(struct hash_u5 *hu5,
              u5 **data, size_t *data_len,
              u64 *val, size_t databits)
{
    be64 be_val;

    /* Too big. */
    if (databits > sizeof(be_val) * CHAR_BIT)
        return false;
    if (!pull_bits(hu5, data, data_len, &be_val, databits, true))
        return false;
    *val = be64_to_cpu(be_val) >> (sizeof(be_val) * CHAR_BIT - databits);
    return true;
}

static size_t num_u8(size_t num_u5)
{
    return (num_u5 * 5 + 4) / 8;
}

/* Frees bolt11, returns NULL. */
static struct bolt11 *decode_fail(struct bolt11 *b11, char **fail,
                  const char *fmt, ...)
    PRINTF_FMT(3,4);

static struct bolt11 *decode_fail(struct bolt11 *b11, char **fail,
                  const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    *fail = tal_vfmt(tal_parent(b11), fmt, ap);
    va_end(ap);
    return tal_free(b11);
}

/*
 * These handle specific fields in the payment request; returning the problem
 * if any, or NULL.
 */
static char *unknown_field(struct bolt11 *b11,
               struct hash_u5 *hu5,
               u5 **data, size_t *data_len,
               u5 type, size_t length)
{
    struct bolt11_field *extra = tal(b11, struct bolt11_field);
    u8 u8data[num_u8(length)];

    extra->tag = type;
    extra->data = tal_dup_arr(extra, u5, *data, length, 0);
    list_add_tail(&b11->extra_fields, &extra->list);

    pull_bits_certain(hu5, data, data_len, u8data, length * 5, true);
    return NULL;
}

/* BOLT #11:
 *
 * `p` (1): `data_length` 52.  256-bit SHA256 payment_hash.  Preimage of this
 * provides proof of payment
 */
static void decode_p(struct bolt11 *b11,
             struct hash_u5 *hu5,
             u5 **data, size_t *data_len,
             size_t data_length, bool *have_p)
{
    /* BOLT #11:
     *
     * A payer... SHOULD use the first `p` field that it did NOT
     * skip as the payment hash.
     */
    if (*have_p) {
        unknown_field(b11, hu5, data, data_len, 'p', data_length);
        return;
    }

    /* BOLT #11:
     *
     * A reader... MUST skip over unknown fields, OR an `f` field
     * with unknown `version`, OR `p`, `h`, `s` or `n` fields that do
     * NOT have `data_length`s of 52, 52, 52 or 53, respectively.
    */
    if (data_length != 52) {
        unknown_field(b11, hu5, data, data_len, 'p', data_length);
        return;
    }

    pull_bits_certain(hu5, data, data_len, &b11->payment_hash, 256, false);
    *have_p = true;
}

/* Check for valid UTF-8 */
static bool utf8_check(const void *vbuf, size_t buflen)
{
	const u8 *buf = vbuf;
	struct utf8_state utf8_state = UTF8_STATE_INIT;
	bool need_more = false;

	for (size_t i = 0; i < buflen; i++) {
		if (!utf8_decode(&utf8_state, buf[i])) {
			need_more = true;
			continue;
		}
		need_more = false;
		if (errno != 0)
			return false;
	}
	return !need_more;
}

static char *utf8_str(const tal_t *ctx, const u8 *buf TAKES, size_t buflen)
{
    char *ret;

    if (!utf8_check(buf, buflen)) {
        if (taken(buf))
            tal_free(buf);
        return NULL;
    }

    /* Add one for nul term */
    ret = tal_dup_arr(ctx, char, (const char *)buf, buflen, 1);
    ret[buflen] = '\0';
    return ret;
}


/* BOLT #11:
 *
 * `d` (13): `data_length` variable.  Short description of purpose of payment
 * (UTF-8), e.g. '1 cup of coffee' or 'ナンセンス 1杯'
 */
static char *decode_d(struct bolt11 *b11,
              struct hash_u5 *hu5,
              u5 **data, size_t *data_len,
              size_t data_length, bool *have_d)
{
    u8 *desc;
    if (*have_d)
        return unknown_field(b11, hu5, data, data_len, 'd', data_length);

    desc = tal_arr(NULL, u8, data_length * 5 / 8);
    pull_bits_certain(hu5, data, data_len, desc, data_length*5, false);

    *have_d = true;
    b11->description = utf8_str(b11, take(desc), tal_bytelen(desc));
    if (b11->description)
        return NULL;

    return tal_fmt(b11, "d: invalid utf8");
}

/* BOLT #11:
 *
 * `h` (23): `data_length` 52.  256-bit description of purpose of payment
 * (SHA256).  This is used to commit to an associated description that is over
 * 639 bytes, but the transport mechanism for the description in that case is
 * transport specific and not defined here.
 */
static void decode_h(struct bolt11 *b11,
             struct hash_u5 *hu5,
             u5 **data, size_t *data_len,
             size_t data_length, bool *have_h)
{
    if (*have_h) {
        unknown_field(b11, hu5, data, data_len, 'h', data_length);
        return;
    }

    /* BOLT #11:
     *
     * A reader... MUST skip over unknown fields, OR an `f` field
     * with unknown `version`, OR `p`, `h`, `s` or `n` fields that do
     * NOT have `data_length`s of 52, 52, 52 or 53, respectively. */
    if (data_length != 52) {
        unknown_field(b11, hu5, data, data_len, 'h', data_length);
        return;
    }

    b11->description_hash = tal(b11, struct sha256);
    pull_bits_certain(hu5, data, data_len, b11->description_hash, 256,
              false);
    *have_h = true;
}

/* BOLT #11:
 *
 * `x` (6): `data_length` variable.  `expiry` time in seconds
 * (big-endian). Default is 3600 (1 hour) if not specified.
 */
#define DEFAULT_X 3600
static char *decode_x(struct bolt11 *b11,
              struct hash_u5 *hu5,
              u5 **data, size_t *data_len,
              size_t data_length, bool *have_x)
{
    if (*have_x)
        return unknown_field(b11, hu5, data, data_len, 'x',
                     data_length);

    /* FIXME: Put upper limit in bolt 11 */
    if (!pull_uint(hu5, data, data_len, &b11->expiry, data_length * 5))
        return tal_fmt(b11, "x: length %zu chars is excessive",
                   *data_len);

    *have_x = true;
    return NULL;
}

/* BOLT #11:
 *
 * `c` (24): `data_length` variable.  `min_final_cltv_expiry` to use for the
 * last HTLC in the route. Default is 18 if not specified.
 */
static char *decode_c(struct bolt11 *b11,
              struct hash_u5 *hu5,
              u5 **data, size_t *data_len,
              size_t data_length, bool *have_c)
{
    u64 c;
    if (*have_c)
        return unknown_field(b11, hu5, data, data_len, 'c',
                     data_length);

    /* FIXME: Put upper limit in bolt 11 */
    if (!pull_uint(hu5, data, data_len, &c, data_length * 5))
        return tal_fmt(b11, "c: length %zu chars is excessive",
                   *data_len);
    b11->min_final_cltv_expiry = (u32)c;
    /* Can overflow, since c is 64 bits but value must be < 32 bits */
    if (b11->min_final_cltv_expiry != c)
        return tal_fmt(b11, "c: %"PRIu64" is too large", c);

    *have_c = true;
    return NULL;
}

static char *decode_n(struct bolt11 *b11,
              struct hash_u5 *hu5,
              u5 **data, size_t *data_len,
              size_t data_length, bool *have_n)
{
    if (*have_n)
        return unknown_field(b11, hu5, data, data_len, 'n',
                     data_length);

    /* BOLT #11:
     *
     * A reader... MUST skip over unknown fields, OR an `f` field
     * with unknown `version`, OR `p`, `h`, `s` or `n` fields that do
     * NOT have `data_length`s of 52, 52, 52 or 53, respectively. */
    if (data_length != 53)
        return unknown_field(b11, hu5, data, data_len, 'n',
                     data_length);

    pull_bits_certain(hu5, data, data_len, &b11->receiver_id.k,
              data_length * 5, false);
    /*
    if (!node_id_valid(&b11->receiver_id))
        return tal_fmt(b11, "n: invalid pubkey %s",
                   node_id_to_hexstr(b11, &b11->receiver_id));
     */

    *have_n = true;
    return NULL;
}

/* BOLT #11:
 *
 * `m` (27): `data_length` variable. Additional metadata to attach to
 * the payment. Note that the size of this field is limited by the
 * maximum hop payload size. Long metadata fields reduce the maximum
 * route length.
 */
static char *decode_m(struct bolt11 *b11,
              struct hash_u5 *hu5,
              u5 **data, size_t *data_len,
              size_t data_length,
              bool *have_m)
{
    size_t mlen = (data_length * 5) / 8;

    if (*have_m)
        return unknown_field(b11, hu5, data, data_len, 'm',
                     data_length);

    b11->metadata = tal_arr(b11, u8, mlen);
    pull_bits_certain(hu5, data, data_len, b11->metadata,
              data_length * 5, false);

    *have_m = true;
    return NULL;
}

struct bolt11 *new_bolt11(const tal_t *ctx)
{
    struct bolt11 *b11 = tal(ctx, struct bolt11);

    list_head_init(&b11->extra_fields);
    b11->description = NULL;
    b11->description_hash = NULL;
    b11->fallbacks = NULL;
    b11->msat = NULL;
    b11->expiry = DEFAULT_X;
    b11->features = tal_arr(b11, u8, 0);
    /* BOLT #11:
     *   - if the `c` field (`min_final_cltv_expiry`) is not provided:
     *     - MUST use an expiry delta of at least 18 when making the payment
     */
    b11->min_final_cltv_expiry = 18;
    //b11->payment_secret = NULL;
    b11->metadata = NULL;

    //if (msat)
        //b11->msat = tal_dup(b11, struct amount_msat, msat);
    return b11;
}

/* Define sha256_eq. */
//STRUCTEQ_DEF(sha256, 0, u);

/* Extracts signature but does not check it. */
struct bolt11 *bolt11_decode_nosig(const tal_t *ctx, const char *str, u5 **sig, char **fail)
{
    char *hrp, *amountstr, *prefix;
    u5 *data;
    size_t data_len;
    struct bolt11 *b11 = new_bolt11(ctx);
    struct hash_u5 hu5;
    bool have_p = false, have_d = false, have_h = false, have_n = false,
        have_x = false, have_c = false, have_m = false;

    /* BOLT #11:
     *
     * If a URI scheme is desired, the current recommendation is to either
     * use 'lightning:' as a prefix before the BOLT-11 encoding
     */
    if (strstarts(str, "lightning:") || strstarts(str, "LIGHTNING:"))
        str += strlen("lightning:");

    if (strlen(str) < 8)
        return decode_fail(b11, fail, "Bad bech32 string");

    hrp = tal_arr(b11, char, strlen(str) - 6);
    data = tal_arr(b11, u5, strlen(str) - 8);

    if (bech32_decode(hrp, data, &data_len, str, (size_t)-1)
        != BECH32_ENCODING_BECH32)
        return decode_fail(b11, fail, "Bad bech32 string");

    /* For signature checking at the end. */
    hash_u5_init(&hu5, hrp);

    /* BOLT #11:
     *
     * The human-readable part of a Lightning invoice consists of two sections:
     * 1. `prefix`: `ln` + BIP-0173 currency prefix (e.g. `lnbc` for Bitcoin mainnet,
     *    `lntb` for Bitcoin testnet, `lntbs` for Bitcoin signet, and `lnbcrt` for Bitcoin regtest)
     * 1. `amount`: optional number in that currency, followed by an optional
     *    `multiplier` letter. The unit encoded here is the 'social' convention of a payment unit -- in the case of Bitcoin the unit is 'bitcoin' NOT satoshis.
    */
    prefix = tal_strndup(b11, hrp, strcspn(hrp, "0123456789"));

    /* BOLT #11:
     *
     * A reader...if it does NOT understand the `prefix`... MUST fail the payment.
     */
    if (!strstarts(prefix, "ln"))
        return decode_fail(b11, fail,
                   "Prefix '%s' does not start with ln", prefix);

    /* BOLT #11:
     *
     *   - if the `amount` is empty:
     * */
    amountstr = tal_strdup(b11, hrp + strlen(prefix));
    if (streq(amountstr, "")) {
        /* BOLT #11:
         *
         * - SHOULD indicate to the payer that amount is unspecified.
         */
        b11->msat = NULL;
    } else {
        u64 m10 = 10 * MSAT_PER_BTC; /* Pico satoshis in a Bitcoin */
        u64 amount;
        char *end;

        /* Gather and trim multiplier */
        end = amountstr + strlen(amountstr)-1;
        for (size_t i = 0; i < ARRAY_SIZE(multipliers); i++) {
            if (*end == multipliers[i].letter) {
                m10 = multipliers[i].m10;
                *end = '\0';
                break;
            }
        }

        /* BOLT #11:
         *
         * if `amount` contains a non-digit OR is followed by
         * anything except a `multiplier` (see table above)... MUST fail the
         * payment.
         **/
        amount = strtoull(amountstr, &end, 10);
        if (amount == ULLONG_MAX && errno == ERANGE)
            return decode_fail(b11, fail,
                       "Invalid amount '%s'", amountstr);
        if (!*amountstr || *end)
            return decode_fail(b11, fail,
                       "Invalid amount postfix '%s'", end);

        /* BOLT #11:
         *
         * if the `multiplier` is present...  MUST multiply
         * `amount` by the `multiplier` value to derive the
         * amount required for payment.
        */
        b11->msat = tal(b11, struct amount_msat);
        /* BOLT #11:
         *
         * - if multiplier is `p` and the last decimal of `amount` is
         *   not 0:
         *    - MUST fail the payment.
         */
        if (amount * m10 % 10 != 0)
            return decode_fail(b11, fail,
                       "Invalid sub-millisatoshi amount"
                       " '%sp'", amountstr);

        *b11->msat = amount_msat(amount * m10 / 10);
    }

    /* BOLT #11:
     *
     * The data part of a Lightning invoice consists of multiple sections:
     *
     * 1. `timestamp`: seconds-since-1970 (35 bits, big-endian)
     * 1. zero or more tagged parts
     * 1. `signature`: Bitcoin-style signature of above (520 bits)
     */
    if (!pull_uint(&hu5, &data, &data_len, &b11->timestamp, 35))
        return decode_fail(b11, fail, "Can't get 35-bit timestamp");

    while (data_len > 520 / 5) {
        const char *problem = NULL;
        u64 type, data_length;

        /* BOLT #11:
         *
         * Each Tagged Field is of the form:
         *
         * 1. `type` (5 bits)
         * 1. `data_length` (10 bits, big-endian)
         * 1. `data` (`data_length` x 5 bits)
         */
        if (!pull_uint(&hu5, &data, &data_len, &type, 5)
            || !pull_uint(&hu5, &data, &data_len, &data_length, 10))
            return decode_fail(b11, fail,
                       "Can't get tag and length");

        /* Can't exceed total data remaining. */
        if (data_length > data_len)
            return decode_fail(b11, fail, "%c: truncated",
                       bech32_charset[type]);

        switch (bech32_charset[type]) {
        case 'p':
            decode_p(b11, &hu5, &data, &data_len, data_length,
                 &have_p);
            break;

        case 'd':
            problem = decode_d(b11, &hu5, &data, &data_len,
                       data_length, &have_d);
            break;

        case 'h':
            decode_h(b11, &hu5, &data, &data_len, data_length,
                 &have_h);
            break;

        case 'n':
            problem = decode_n(b11, &hu5, &data,
                       &data_len, data_length,
                       &have_n);
            break;

        case 'x':
            problem = decode_x(b11, &hu5, &data,
                       &data_len, data_length,
                       &have_x);
            break;

        case 'c':
            problem = decode_c(b11, &hu5, &data,
                       &data_len, data_length,
                       &have_c);
            break;

                /*
        case 'f':
            problem = decode_f(b11, &hu5, &data,
                       &data_len, data_length);
            break;
        case 'r':
            problem = decode_r(b11, &hu5, &data, &data_len,
                       data_length);
            break;
        case '9':
            problem = decode_9(b11, our_features, &hu5,
                       &data, &data_len,
                       data_length);
            break;
        case 's':
            problem = decode_s(b11, &hu5, &data, &data_len,
                       data_length, &have_s);
            break;
                 */
        case 'm':
            problem = decode_m(b11, &hu5, &data, &data_len,
                       data_length, &have_m);
            break;
        default:
            unknown_field(b11, &hu5, &data, &data_len,
                      bech32_charset[type], data_length);
        }
        if (problem)
            return decode_fail(b11, fail, "%s", problem);
    }

    if (!have_p)
        return decode_fail(b11, fail, "No valid 'p' field found");

    *sig = tal_dup_arr(ctx, u5, data, data_len, 0);
    return b11;
}

/* Decodes and checks signature; returns NULL on error. */
struct bolt11 *bolt11_decode(const tal_t *ctx, const char *str, char **fail)
{
    u5 *sigdata;
    size_t data_len;
    u8 sig_and_recid[65];
    //secp256k1_ecdsa_recoverable_signature sig;
    struct bolt11 *b11;

    b11 = bolt11_decode_nosig(ctx, str, &sigdata, fail);
    if (!b11)
        return NULL;

    /* BOLT #11:
     *
     * A writer...MUST set `signature` to a valid 512-bit
     * secp256k1 signature of the SHA2 256-bit hash of the
     * human-readable part, represented as UTF-8 bytes,
     * concatenated with the data part (excluding the signature)
     * with 0 bits appended to pad the data to the next byte
     * boundary, with a trailing byte containing the recovery ID
     * (0, 1, 2, or 3).
     */
    data_len = tal_count(sigdata);
    if (!pull_bits(NULL, &sigdata, &data_len, sig_and_recid, 520, false))
        return decode_fail(b11, fail, "signature truncated");

    assert(data_len == 0);

    /*
    if (!secp256k1_ecdsa_recoverable_signature_parse_compact
        (secp256k1_ctx, &sig, sig_and_recid, sig_and_recid[64]))
        return decode_fail(b11, fail, "signature invalid");

    secp256k1_ecdsa_recoverable_signature_convert(secp256k1_ctx,
                              &b11->sig, &sig);
     */

    /* BOLT #11:
     *
     * A reader...  MUST check that the `signature` is valid (see
     * the `n` tagged field specified below). ... A reader...
     * MUST use the `n` field to validate the signature instead of
     * performing signature recovery.
     */
    /*
    if (!have_n) {
        struct pubkey k;
        if (!secp256k1_ecdsa_recover(secp256k1_ctx,
                         &k.pubkey,
                         &sig,
                         (const u8 *)&hash))
            return decode_fail(b11, fail,
                       "signature recovery failed");
        node_id_from_pubkey(&b11->receiver_id, &k);
    } else {
        struct pubkey k;
        if (!pubkey_from_node_id(&k, &b11->receiver_id))
            abort();
        if (!secp256k1_ecdsa_verify(secp256k1_ctx, &b11->sig,
                        (const u8 *)&hash,
                        &k.pubkey))
            return decode_fail(b11, fail, "invalid signature");
    }
     */

    return b11;
}
