//
//	nostr_bech32.h
//	damus
//
//	Created by William Casarin on 2023-04-09.
//

#ifndef nostr_bech32_h
#define nostr_bech32_h

#include <stdio.h>
#include "str_block.h"
#include "cursor.h"
#define MAX_RELAYS 24

struct relays {
	struct str_block relays[MAX_RELAYS];
	int num_relays;
};

enum nostr_bech32_type {
	NOSTR_BECH32_NOTE = 1,
	NOSTR_BECH32_NPUB = 2,
	NOSTR_BECH32_NPROFILE = 3,
	NOSTR_BECH32_NEVENT = 4,
	NOSTR_BECH32_NRELAY = 5,
	NOSTR_BECH32_NADDR = 6,
	NOSTR_BECH32_NSEC = 7,
};

struct bech32_note {
	const unsigned char *event_id;
};

struct bech32_npub {
	const unsigned char *pubkey;
};

struct bech32_nsec {
	const unsigned char *nsec;
};

struct bech32_nevent {
	struct relays relays;
	const unsigned char *event_id;
	const unsigned char *pubkey; // optional
};

struct bech32_nprofile {
	struct relays relays;
	const unsigned char *pubkey;
};

struct bech32_naddr {
	struct relays relays;
	struct str_block identifier;
	const unsigned char *pubkey;
};

struct bech32_nrelay {
	struct str_block relay;
};

struct nostr_bech32 {
	enum nostr_bech32_type type;
	
	union {
		struct bech32_note note;
		struct bech32_npub npub;
		struct bech32_nsec nsec;
		struct bech32_nevent nevent;
		struct bech32_nprofile nprofile;
		struct bech32_naddr naddr;
		struct bech32_nrelay nrelay;
	} data;
};


int parse_nostr_bech32_str(struct cursor *bech32);
int parse_nostr_bech32_type(const char *prefix, enum nostr_bech32_type *type);

/*
int parse_nostr_bech32_buffer(unsigned char *buf, int buflen,
			      enum nostr_bech32_type type,
			      struct nostr_bech32 *obj);

int parse_nostr_bech32(const char *bech32, size_t input_len,
		       unsigned char *outbuf, size_t outlen,
		       enum nostr_bech32_type *type);
		       */

#endif /* nostr_bech32_h */
