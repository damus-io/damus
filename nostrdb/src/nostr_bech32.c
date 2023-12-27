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

struct nostr_tlvs {
	struct nostr_tlv tlvs[MAX_TLVS];
	int num_tlvs;
};

static int parse_nostr_tlv(struct cursor *cur, struct nostr_tlv *tlv) {
	// get the tlv tag
	if (!cursor_pull_byte(cur, &tlv->type))
		return 0;
	
	// unknown, fail!
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

static int parse_nostr_tlvs(struct cursor *cur, struct nostr_tlvs *tlvs) {
	int i;
	tlvs->num_tlvs = 0;
	
	for (i = 0; i < MAX_TLVS; i++) {
		if (parse_nostr_tlv(cur, &tlvs->tlvs[i])) {
			tlvs->num_tlvs++;
		} else {
			break;
		}
	}
	
	if (tlvs->num_tlvs == 0)
		return 0;
	
	return 1;
}

static int find_tlv(struct nostr_tlvs *tlvs, unsigned char type, struct nostr_tlv **tlv) {
	*tlv = NULL;
	
	for (int i = 0; i < tlvs->num_tlvs; i++) {
		if (tlvs->tlvs[i].type == type) {
			*tlv = &tlvs->tlvs[i];
			return 1;
		}
	}
	
	return 0;
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

static int tlvs_to_relays(struct nostr_tlvs *tlvs, struct relays *relays) {
	struct nostr_tlv *tlv;
	struct str_block *str;
	
	relays->num_relays = 0;
	
	for (int i = 0; i < tlvs->num_tlvs; i++) {
		tlv = &tlvs->tlvs[i];
		if (tlv->type != TLV_RELAY)
			continue;
		
		if (relays->num_relays + 1 > MAX_RELAYS)
			break;
		
		str = &relays->relays[relays->num_relays++];
		str->str = (const char*)tlv->value;
		str->len = tlv->len;
	}
	
	return 1;
}

static int parse_nostr_bech32_nevent(struct cursor *cur, struct bech32_nevent *nevent) {
	struct nostr_tlvs tlvs;
	struct nostr_tlv *tlv;
	
	if (!parse_nostr_tlvs(cur, &tlvs))
		return 0;
	
	if (!find_tlv(&tlvs, TLV_SPECIAL, &tlv))
		return 0;
	
	if (tlv->len != 32)
		return 0;
	
	nevent->event_id = tlv->value;
	
	if (find_tlv(&tlvs, TLV_AUTHOR, &tlv)) {
		nevent->pubkey = tlv->value;
	} else {
		nevent->pubkey = NULL;
	}
	
	return tlvs_to_relays(&tlvs, &nevent->relays);
}

static int parse_nostr_bech32_naddr(struct cursor *cur, struct bech32_naddr *naddr) {
	struct nostr_tlvs tlvs;
	struct nostr_tlv *tlv;
	
	if (!parse_nostr_tlvs(cur, &tlvs))
		return 0;
	
	if (!find_tlv(&tlvs, TLV_SPECIAL, &tlv))
		return 0;
	
	naddr->identifier.str = (const char*)tlv->value;
	naddr->identifier.len = tlv->len;
	
	if (!find_tlv(&tlvs, TLV_AUTHOR, &tlv))
		return 0;
	
	naddr->pubkey = tlv->value;
	
	return tlvs_to_relays(&tlvs, &naddr->relays);
}

static int parse_nostr_bech32_nprofile(struct cursor *cur, struct bech32_nprofile *nprofile) {
	struct nostr_tlvs tlvs;
	struct nostr_tlv *tlv;
	
	if (!parse_nostr_tlvs(cur, &tlvs))
		return 0;
	
	if (!find_tlv(&tlvs, TLV_SPECIAL, &tlv))
		return 0;
	
	if (tlv->len != 32)
		return 0;
	
	nprofile->pubkey = tlv->value;
	
	return tlvs_to_relays(&tlvs, &nprofile->relays);
}

static int parse_nostr_bech32_nrelay(struct cursor *cur, struct bech32_nrelay *nrelay) {
	struct nostr_tlvs tlvs;
	struct nostr_tlv *tlv;
	
	if (!parse_nostr_tlvs(cur, &tlvs))
		return 0;
	
	if (!find_tlv(&tlvs, TLV_SPECIAL, &tlv))
		return 0;
	
	nrelay->relay.str = (const char*)tlv->value;
	nrelay->relay.len = tlv->len;
	
	return 1;
}

/*
int parse_nostr_bech32_buffer(unsigned char *cur, int buflen,
			      enum nostr_bech32_type type,
			      struct nostr_bech32 *obj)
{
	obj->type = type;
	
	switch (obj->type) {
		case NOSTR_BECH32_NOTE:
			if (!parse_nostr_bech32_note(cur, &obj->data.note))
				return 0;
			break;
		case NOSTR_BECH32_NPUB:
			if (!parse_nostr_bech32_npub(cur, &obj->data.npub))
				return 0;
			break;
		case NOSTR_BECH32_NSEC:
			if (!parse_nostr_bech32_nsec(cur, &obj->data.nsec))
				return 0;
			break;
		case NOSTR_BECH32_NEVENT:
			if (!parse_nostr_bech32_nevent(cur, &obj->data.nevent))
				return 0;
			break;
		case NOSTR_BECH32_NADDR:
			if (!parse_nostr_bech32_naddr(cur, &obj->data.naddr))
				return 0;
			break;
		case NOSTR_BECH32_NPROFILE:
			if (!parse_nostr_bech32_nprofile(cur, &obj->data.nprofile))
				return 0;
			break;
		case NOSTR_BECH32_NRELAY:
			if (!parse_nostr_bech32_nrelay(cur, &obj->data.nrelay))
				return 0;
			break;
	}

	return 1;
}
*/

int parse_nostr_bech32_str(struct cursor *bech32) {
	enum nostr_bech32_type type;
	
	if (!parse_nostr_bech32_type((const char *)bech32->p, &type))
		return 0;
	
	if (!consume_until_non_alphanumeric(bech32, 1))
		return 0;

	return 1;

	/*
	*parsed_len = bech32->p - start;

	// some random sanity checking
	if (*parsed_len < 10 || *parsed_len > 10000)
		return 0;

	const char u5[*parsed_len];
	
	if (bech32_decode_len(prefix, u5, &u5_out_len, (const char*)start,
			      *parsed_len, MAX_PREFIX) == BECH32_ENCODING_NONE)
	{
		return 0;
	}

	if (!parse_nostr_bech32_type(prefix, type))
		return 0;
		*/

	return 1;
}

