//
//  block.h
//  damus
//
//  Created by William Casarin on 2023-04-09.
//

#ifndef block_h
#define block_h

#include "nostr_bech32.h"
#include "str_block.h"

#define MAX_BLOCKS 1024

enum block_type {
    BLOCK_HASHTAG = 1,
    BLOCK_TEXT = 2,
    BLOCK_MENTION_INDEX = 3,
    BLOCK_MENTION_BECH32 = 4,
    BLOCK_URL = 5,
    BLOCK_INVOICE = 6,
};


typedef struct invoice_block {
    struct str_block invstr;
    union {
        struct bolt11 *bolt11;
    };
} invoice_block_t;

typedef struct mention_bech32_block {
    struct str_block str;
    struct nostr_bech32 bech32;
} mention_bech32_block_t;

typedef struct note_block {
    enum block_type type;
    union {
        struct str_block str;
        struct invoice_block invoice;
        struct mention_bech32_block mention_bech32;
        int mention_index;
    } block;
} block_t;

typedef struct note_blocks {
    int words;
    int num_blocks;
    struct note_block *blocks;
} blocks_t;

void blocks_init(struct note_blocks *blocks);
void blocks_free(struct note_blocks *blocks);

#endif /* block_h */
