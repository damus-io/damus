//
//	nostr_bech32.c
//	damus
//
//	Created by William Casarin on 2023-04-09.
//

#include "nostr_bech32.h"
#include <stdlib.h>
#include "cursor.h"
#include "bolt11/bech32.h"

#define MAX_TLVS 32

#define TLV_SPECIAL 0
#define TLV_RELAY 1
#define TLV_AUTHOR 2
#define TLV_KIND 3
#define TLV_KNOWN_TLVS 4

struct nostr_tlv {
	unsigned char type;
	unsigned char len;
	const unsigned char *value;
};

static int parse_nostr_tlv(struct cursor *cur, struct nostr_tlv *tlv) {
	// get the tlv tag
	if (!cursor_pull_byte(cur, &tlv->type))
		return 0;

	if (tlv->type >= TLV_KNOWN_TLVS)
		return 0;
	
	// get the length
	if (!cursor_pull_byte(cur, &tlv->len))
		return 0;
	
	// is the reported length greater then our buffer? if so fail
	if (cur->p + tlv->len > cur->end)
		return 0;
	
	tlv->value = cur->p;
	cur->p += tlv->len;
	
	return 1;
}

int parse_nostr_bech32_type(const char *prefix, enum nostr_bech32_type *type) {
	// Parse type
	if (strncmp(prefix, "note", 4) == 0) {
		*type = NOSTR_BECH32_NOTE;
		return 1;
	} else if (strncmp(prefix, "npub", 4) == 0) {
		*type = NOSTR_BECH32_NPUB;
		return 1;
	} else if (strncmp(prefix, "nsec", 4) == 0) {
		*type = NOSTR_BECH32_NSEC;
		return 1;
	} else if (strncmp(prefix, "nprofile", 8) == 0) {
		*type = NOSTR_BECH32_NPROFILE;
		return 1;
	} else if (strncmp(prefix, "nevent", 6) == 0) {
		*type = NOSTR_BECH32_NEVENT;
		return 1;
	} else if (strncmp(prefix, "nrelay", 6) == 0) {
		*type = NOSTR_BECH32_NRELAY;
		return 1;
	} else if (strncmp(prefix, "naddr", 5) == 0) {
		*type = NOSTR_BECH32_NADDR;
		return 1;
	}
	
	return 0;
}

static int parse_nostr_bech32_note(struct cursor *cur, struct bech32_note *note) {
	return pull_bytes(cur, 32, &note->event_id);
}

static int parse_nostr_bech32_npub(struct cursor *cur, struct bech32_npub *npub) {
	return pull_bytes(cur, 32, &npub->pubkey);
}

static int parse_nostr_bech32_nsec(struct cursor *cur, struct bech32_nsec *nsec) {
	return pull_bytes(cur, 32, &nsec->nsec);
}

static int add_relay(struct relays *relays, struct nostr_tlv *tlv)
{
	struct str_block *str;

	if (relays->num_relays + 1 > MAX_RELAYS)
		return 0;
	
	str = &relays->relays[relays->num_relays++];
	str->str = (const char*)tlv->value;
	str->len = tlv->len;
	
	return 1;
}

static int parse_nostr_bech32_nevent(struct cursor *cur, struct bech32_nevent *nevent) {
	struct nostr_tlv tlv;
	int i;

	nevent->event_id = NULL;
	nevent->pubkey = NULL;
	nevent->relays.num_relays = 0;

	for (i = 0; i < MAX_TLVS; i++) {
		if (!parse_nostr_tlv(cur, &tlv))
			break;

		switch (tlv.type) {
		case TLV_SPECIAL:
			if (tlv.len != 32) return 0;
			nevent->event_id = tlv.value;
			break;
		case TLV_AUTHOR:
			if (tlv.len != 32) return 0;
			nevent->pubkey = tlv.value;
			break;
		case TLV_RELAY:
			add_relay(&nevent->relays, &tlv);
			break;
		}
	}

	return nevent->event_id != NULL;
}

static int parse_nostr_bech32_naddr(struct cursor *cur, struct bech32_naddr *naddr) {
	struct nostr_tlv tlv;
	int i;

	naddr->identifier.str = NULL;
	naddr->identifier.len = 0;
	naddr->pubkey = NULL;
	naddr->relays.num_relays = 0;

	for (i = 0; i < MAX_TLVS; i++) {
		if (!parse_nostr_tlv(cur, &tlv))
			break;

		switch (tlv.type) {
		case TLV_SPECIAL:
			naddr->identifier.str = (const char*)tlv.value;
			naddr->identifier.len = tlv.len;
			break;
		case TLV_AUTHOR:
			if (tlv.len != 32) return 0;
			naddr->pubkey = tlv.value;
			break;
		case TLV_RELAY:
			add_relay(&naddr->relays, &tlv);
			break;
		}
	}

	return naddr->identifier.str != NULL;
}

static int parse_nostr_bech32_nprofile(struct cursor *cur, struct bech32_nprofile *nprofile) {
	struct nostr_tlv tlv;
	int i;

	nprofile->pubkey = NULL;
	nprofile->relays.num_relays = 0;

	for (i = 0; i < MAX_TLVS; i++) {
		if (!parse_nostr_tlv(cur, &tlv))
			break;

		switch (tlv.type) {
		case TLV_SPECIAL:
			if (tlv.len != 32) return 0;
			nprofile->pubkey = tlv.value;
			break;
		case TLV_RELAY:
			add_relay(&nprofile->relays, &tlv);
			break;
		}
	}

	return nprofile->pubkey != NULL;
}

static int parse_nostr_bech32_nrelay(struct cursor *cur, struct bech32_nrelay *nrelay) {
	struct nostr_tlv tlv;
	int i;

	nrelay->relay.str = NULL;
	nrelay->relay.len = 0;

	for (i = 0; i < MAX_TLVS; i++) {
		if (!parse_nostr_tlv(cur, &tlv))
			break;

		switch (tlv.type) {
		case TLV_SPECIAL:
			nrelay->relay.str = (const char*)tlv.value;
			nrelay->relay.len = tlv.len;
			break;
		}
	}
	
	return nrelay->relay.str != NULL;
}

int parse_nostr_bech32_buffer(struct cursor *cur,
			      enum nostr_bech32_type type,
			      struct nostr_bech32 *obj)
{
	obj->type = type;
	
	switch (obj->type) {
		case NOSTR_BECH32_NOTE:
			if (!parse_nostr_bech32_note(cur, &obj->note))
				return 0;
			break;
		case NOSTR_BECH32_NPUB:
			if (!parse_nostr_bech32_npub(cur, &obj->npub))
				return 0;
			break;
		case NOSTR_BECH32_NSEC:
			if (!parse_nostr_bech32_nsec(cur, &obj->nsec))
				return 0;
			break;
		case NOSTR_BECH32_NEVENT:
			if (!parse_nostr_bech32_nevent(cur, &obj->nevent))
				return 0;
			break;
		case NOSTR_BECH32_NADDR:
			if (!parse_nostr_bech32_naddr(cur, &obj->naddr))
				return 0;
			break;
		case NOSTR_BECH32_NPROFILE:
			if (!parse_nostr_bech32_nprofile(cur, &obj->nprofile))
				return 0;
			break;
		case NOSTR_BECH32_NRELAY:
			if (!parse_nostr_bech32_nrelay(cur, &obj->nrelay))
				return 0;
			break;
	}

	return 1;
}


int parse_nostr_bech32_str(struct cursor *bech32, enum nostr_bech32_type *type) {
	if (!parse_nostr_bech32_type((const char *)bech32->p, type))
		return 0;
	
	if (!consume_until_non_alphanumeric(bech32, 1))
		return 0;

	return 1;
}


int parse_nostr_bech32(unsigned char *buf, int buflen,
		       const char *bech32_str, size_t bech32_len,
		       struct nostr_bech32 *obj) {
	unsigned char *start;
	size_t parsed_len, u5_out_len, u8_out_len;
	enum nostr_bech32_type type;
	static const int MAX_PREFIX = 8;
	struct cursor cur, bech32;

	make_cursor(buf, buf + buflen, &cur);
	make_cursor((unsigned char*)bech32_str, (unsigned char*)bech32_str + bech32_len, &bech32);
	
	start = bech32.p;
	if (!parse_nostr_bech32_str(&bech32, &type))
		return 0;

	parsed_len = bech32.p - start;

	// some random sanity checking
	if (parsed_len < 10 || parsed_len > 10000)
		return 0;

	unsigned char u5[parsed_len];
	char prefix[MAX_PREFIX];
	
	if (bech32_decode_len(prefix, u5, &u5_out_len, (const char*)start,
			      parsed_len, MAX_PREFIX) == BECH32_ENCODING_NONE)
	{
		return 0;
	}

	if (!bech32_convert_bits(cur.p, &u8_out_len, 8, u5, u5_out_len, 5, 0))
		return 0;

	return parse_nostr_bech32_buffer(&cur, type, obj);
}

