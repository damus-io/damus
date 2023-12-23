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
typedef unsigned char u8;
#define MAX_RELAYS 10

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
	const u8 *event_id;
};

struct bech32_npub {
	const u8 *pubkey;
};

struct bech32_nsec {
	const u8 *nsec;
};

struct bech32_nevent {
	struct relays relays;
	const u8 *event_id;
	const u8 *pubkey; // optional
};

struct bech32_nprofile {
	struct relays relays;
	const u8 *pubkey;
};

struct bech32_naddr {
	struct relays relays;
	struct str_block identifier;
	const u8 *pubkey;
};

struct bech32_nrelay {
	struct str_block relay;
};

typedef struct nostr_bech32 {
	enum nostr_bech32_type type;
	u8 *buffer; // holds strings and tlv stuff
	size_t buflen;
	
	union {
		struct bech32_note note;
		struct bech32_npub npub;
		struct bech32_nsec nsec;
		struct bech32_nevent nevent;
		struct bech32_nprofile nprofile;
		struct bech32_naddr naddr;
		struct bech32_nrelay nrelay;
	} data;
} nostr_bech32_t;


int parse_nostr_bech32(struct cursor *cur, struct nostr_bech32 *obj);

#endif /* nostr_bech32_h */
