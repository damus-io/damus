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
 * Otherwise we add an extra byte.  Returns error string or NULL on success. */
static const char *pull_bits(struct hash_u5 *hu5,
			     const u5 **data, size_t *data_len,
			     void *dst, size_t nbits,
			     bool pad)
{
    size_t n5 = nbits / 5;
    size_t len = 0;

    if (nbits % 5)
        n5++;

    if (*data_len < n5)
        return "truncated";
    if (!bech32_convert_bits(dst, &len, 8, *data, n5, 5, pad))
        return "non-zero trailing bits";
    if (hu5)
        hash_u5(hu5, *data, n5);
    *data += n5;
    *data_len -= n5;

    return NULL;
}

/* Helper for pulling a variable-length big-endian int. */
static const char *pull_uint(struct hash_u5 *hu5,
                             const u5 **data, size_t *data_len,
                             u64 *val, size_t databits)
{
    be64 be_val;
    const char *err;

    /* Too big. */
    if (databits > sizeof(be_val) * CHAR_BIT)
        return "integer too large";
    err = pull_bits(hu5, data, data_len, &be_val, databits, true);
    if (err)
        return err;
    if (databits == 0)
        *val = 0;
    else
        *val = be64_to_cpu(be_val) >>
            (sizeof(be_val) * CHAR_BIT - databits);
    return NULL;
}

static void *pull_all(const tal_t *ctx,
		      struct hash_u5 *hu5,
		      const u5 **data, size_t *data_len,
		      bool pad,
		      const char **err)
{
    void *ret;
    size_t retlen;

    if (pad)
        retlen = (*data_len * 5 + 7) / 8;
    else
        retlen = (*data_len * 5) / 8;

    ret = tal_arr(ctx, u8, retlen);
    *err = pull_bits(hu5, data, data_len, ret, *data_len * 5, pad);
    if (*err)
        return tal_free(ret);
    return ret;
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
    if (fail)
        *fail = tal_vfmt(tal_parent(b11), fmt, ap);
    va_end(ap);
    return tal_free(b11);
}

/*
 * These handle specific fields in the payment request; returning the problem
 * if any, or NULL.
 */
static const char *unknown_field(struct bolt11 *b11,
				 struct hash_u5 *hu5,
				 const u5 **data, size_t *field_len,
				 u5 type)
{
    const char *err;

    tal_free(pull_all(NULL, hu5, data, field_len, true, &err));
    return err;
}

/* If field isn't expected length (in *bech32*!), call unknown_field.
 * Otherwise copy into dst without padding, set have_flag if non-NULL. */
static const char *pull_expected_length(struct bolt11 *b11,
					struct hash_u5 *hu5,
					const u5 **data, size_t *field_len,
					size_t expected_length,
					u5 type,
					bool *have_flag,
					void *dst)
{
    if (*field_len != expected_length)
        return unknown_field(b11, hu5, data, field_len, type);

    if (have_flag)
        *have_flag = true;
    return pull_bits(hu5, data, field_len, dst, *field_len * 5, false);
}

/* BOLT #11:
 *
 * `p` (1): `data_length` 52.  256-bit SHA256 payment_hash.  Preimage of this
 * provides proof of payment
 */
static const char *decode_p(struct bolt11 *b11,
			    const struct feature_set *our_features,
			    struct hash_u5 *hu5,
			    const u5 **data, size_t *field_len,
			    bool *have_p)
{
    struct sha256 payment_hash;
    /* BOLT #11:
     *
     * A payer... SHOULD use the first `p` field that it did NOT
     * skip as the payment hash.
     */
    assert(!*have_p);

    /* BOLT #11:
     *
     * A reader... MUST skip over unknown fields, OR an `f` field
     * with unknown `version`, OR `p`, `h`, `s` or `n` fields that do
     * NOT have `data_length`s of 52, 52, 52 or 53, respectively.
     */
    return pull_expected_length(b11, hu5, data, field_len, 52, 'p',
                                have_p, &payment_hash);
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
static const char *decode_d(struct bolt11 *b11,
			    const struct feature_set *our_features,
			    struct hash_u5 *hu5,
			    const u5 **data, size_t *field_len,
			    bool *have_d)
{
    u8 *desc;
    const char *err;

    assert(!*have_d);
    desc = pull_all(NULL, hu5, data, field_len, false, &err);
    if (!desc)
        return err;

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
static const char *decode_h(struct bolt11 *b11,
			    const struct feature_set *our_features,
			    struct hash_u5 *hu5,
			    const u5 **data, size_t *field_len,
			    bool *have_h)
{
    const char *err;
    struct sha256 hash;

    assert(!*have_h);
    /* BOLT #11:
     *
     * A reader... MUST skip over unknown fields, OR an `f` field
     * with unknown `version`, OR `p`, `h`, `s` or `n` fields that do
     * NOT have `data_length`s of 52, 52, 52 or 53, respectively. */
    err = pull_expected_length(b11, hu5, data, field_len, 52, 'h',
                               have_h, &hash);

    /* If that gave us the hash, store it */
    if (*have_h)
        b11->description_hash = tal_dup(b11, struct sha256, &hash);
    return err;
}

/* BOLT #11:
 *
 * `x` (6): `data_length` variable.  `expiry` time in seconds
 * (big-endian). Default is 3600 (1 hour) if not specified.
 */
#define DEFAULT_X 3600
static const char *decode_x(struct bolt11 *b11,
			    const struct feature_set *our_features,
			    struct hash_u5 *hu5,
			    const u5 **data, size_t *field_len,
			    bool *have_x)
{
    const char *err;

    assert(!*have_x);

    /* FIXME: Put upper limit in bolt 11 */
    err = pull_uint(hu5, data, field_len, &b11->expiry, *field_len * 5);
    if (err)
        return tal_fmt(b11, "x: %s", err);

    *have_x = true;
    return NULL;
}

static struct bolt11 *new_bolt11(const tal_t *ctx,
                                 const struct amount_msat *msat TAKES)
{
    struct bolt11 *b11 = tal(ctx, struct bolt11);

    b11->description = NULL;
    b11->description_hash = NULL;
    b11->msat = NULL;
    b11->expiry = DEFAULT_X;

    if (msat)
        b11->msat = tal_dup(b11, struct amount_msat, msat);
    return b11;
}

struct decoder {
    /* What BOLT11 letter this is */
    const char letter;
    /* If false, then any dups get treated as "unknown" fields */
    bool allow_duplicates;
    /* Routine to decode: returns NULL if it decodes ok, and
     * sets *have_field = true if it is not an unknown form.
     * Otherwise returns error string (literal or tal off b11). */
    const char *(*decode)(struct bolt11 *b11,
                          const struct feature_set *our_features,
                          struct hash_u5 *hu5,
                          const u5 **data, size_t *field_len,
                          bool *have_field);
};

static const struct decoder decoders[] = {
    /* BOLT #11:
     *
     * A payer... SHOULD use the first `p` field that it did NOT
     * skip as the payment hash.
     */
    { 'p', false, decode_p },
    { 'd', false, decode_d },
    { 'h', false, decode_h },
    { 'x', false, decode_x },
};

static const struct decoder *find_decoder(char c)
{
    for (size_t i = 0; i < ARRAY_SIZE(decoders); i++) {
        if (decoders[i].letter == c)
            return decoders + i;
    }
    return NULL;
}

static bool bech32_decode_alloc(const tal_t *ctx,
				const char **hrp_ret,
				const u5 **data_ret,
				size_t *data_len,
				const char *str)
{
    char *hrp = tal_arr(ctx, char, strlen(str) - 6);
    u5 *data = tal_arr(ctx, u5, strlen(str) - 8);

    if (bech32_decode(hrp, data, data_len, str, (size_t)-1)
        != BECH32_ENCODING_BECH32) {
        tal_free(hrp);
        tal_free(data);
        return false;
    }

    /* We needed temporaries because these are const */
    *hrp_ret = hrp;
    *data_ret = data;
    return true;
}

static bool has_lightning_prefix(const char *invstring)
{
    /* BOLT #11:
     *
     * If a URI scheme is desired, the current recommendation is to either
     * use 'lightning:' as a prefix before the BOLT-11 encoding */
    return (strstarts(invstring, "lightning:") ||
            strstarts(invstring, "LIGHTNING:"));
}

static char *str_lowering(const void *ctx, const char *string TAKES)
{
	char *ret;

	ret = tal_strdup(ctx, string);
	for (char *p = ret; *p; p++) *p = tolower(*p);
	return ret;
}

static const char *to_canonical_invstr(const tal_t *ctx,
				const char *invstring)
{
    if (has_lightning_prefix(invstring))
        invstring += strlen("lightning:");
    return str_lowering(ctx, invstring);
}

/* Extracts signature but does not check it. */
static struct bolt11 *bolt11_decode_nosig(const tal_t *ctx, const char *str,
                                          const struct feature_set *our_features,
                                          struct sha256 *hash,
                                          const u5 **sig,
                                          bool *have_n,
                                          char **fail)
{
    const char *hrp, *prefix;
    char *amountstr;
    const u5 *data;
    size_t data_len;
    struct bolt11 *b11 = new_bolt11(ctx, NULL);
    struct hash_u5 hu5;
    const char *err;
    /* We don't need all of these, but in theory we could have 32 types */
    bool have_field[32];

    memset(have_field, 0, sizeof(have_field));

    if (strlen(str) < 8)
        return decode_fail(b11, fail, "Bad bech32 string");

    if (!bech32_decode_alloc(b11, &hrp, &data, &data_len, str))
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
    err = pull_uint(&hu5, &data, &data_len, &b11->timestamp, 35);
    if (err)
        return decode_fail(b11, fail,
                           "Can't get 35-bit timestamp: %s", err);

    while (data_len > 520 / 5) {
        const char *problem = NULL;
        u64 type, field_len64;
        size_t field_len;
        const struct decoder *decoder;

        /* BOLT #11:
         *
         * Each Tagged Field is of the form:
         *
         * 1. `type` (5 bits)
         * 1. `data_length` (10 bits, big-endian)
         * 1. `data` (`data_length` x 5 bits)
         */
        err = pull_uint(&hu5, &data, &data_len, &type, 5);
        if (err)
            return decode_fail(b11, fail,
                               "Can't get tag: %s", err);
        err = pull_uint(&hu5, &data, &data_len, &field_len64, 10);
        if (err)
            return decode_fail(b11, fail,
                               "Can't get length: %s", err);

        /* Can't exceed total data remaining. */
        if (field_len64 > data_len)
            return decode_fail(b11, fail, "%c: truncated",
                               bech32_charset[type]);

        /* These are different types on 32 bit!  But since data_len is
         * also size_t, above check ensures this will fit. */
        field_len = field_len64;
        assert(field_len == field_len64);

        /* Do this now: the decode function fixes up the data ptr */
        data_len -= field_len;

        decoder = find_decoder(bech32_charset[type]);
        if (!decoder || (have_field[type] && !decoder->allow_duplicates)) {
            problem = unknown_field(b11, &hu5, &data, &field_len,
                                    bech32_charset[type]);
        } else {
            problem = decoder->decode(b11, our_features, &hu5,
                                      &data, &field_len, &have_field[type]);
        }
        if (problem)
            return decode_fail(b11, fail, "%s", problem);
        if (field_len)
            return decode_fail(b11, fail, "%c: extra %zu bytes",
                               bech32_charset[type], field_len);
    }

    if (!have_field[bech32_charset_rev['p']])
        return decode_fail(b11, fail, "No valid 'p' field found");

    /* BOLT #11:
     * A writer:
     *...
     * - MUST include either exactly one `d` or exactly one `h` field.
     */
    /* FIXME: It doesn't actually say the reader must check though! */
    if (!have_field[bech32_charset_rev['d']]
        && !have_field[bech32_charset_rev['h']])
        return decode_fail(b11, fail,
                           "must have either 'd' or 'h' field");

    hash_u5_done(&hu5, hash);
    *sig = tal_dup_arr(ctx, u5, data, data_len, 0);

    *have_n = have_field[bech32_charset_rev['n']];
    return b11;
}

struct bolt11 *bolt11_decode_minimal(const tal_t *ctx, const char *str,
                                     char **fail)
{
    const u5 *sigdata;
    struct sha256 hash;
    bool have_n;

    str = to_canonical_invstr(ctx, str);
    return bolt11_decode_nosig(ctx, str, NULL, &hash, &sigdata, &have_n,
                               fail);
}
