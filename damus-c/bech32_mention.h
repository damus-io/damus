//
//  bech32_mention.h
//  damus
//
//  Created by Bartholomew Joyce on 2023-04-03.
//

#ifndef bech32_mention
#define bech32_mention

typedef unsigned char u8;

#define MAX_RELAYS 10

enum bech32_mention_type {
    BECH32_MENTION_NOTE = 1,
    BECH32_MENTION_NPUB = 2,
    BECH32_MENTION_NPROFILE = 3,
    BECH32_MENTION_NEVENT = 4,
    BECH32_MENTION_NRELAY = 5,
    BECH32_MENTION_NADDR = 6,
};

typedef struct bech32_mention {
    enum bech32_mention_type type;

    u8 *event_id;
    u8 *pubkey;
    char *identifier;
    char *relays[MAX_RELAYS];
    int relays_count;
    int kind;

    u8* buffer;
} bech32_mention_t;

int bech32_mention_parse(bech32_mention_t *mention, const char* str, int len);
void bech32_mention_free(bech32_mention_t *mention);

#endif /* bech32_mention */
