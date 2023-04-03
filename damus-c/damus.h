//
//  damus.h
//  damus
//
//  Created by William Casarin on 2022-10-17.
//

#ifndef damus_h
#define damus_h

#include <stdio.h>
#include "bech32_mention.h"

#define MAX_BLOCKS 1024

enum block_type {
    BLOCK_HASHTAG = 1,
    BLOCK_TEXT = 2,
    BLOCK_MENTION_INDEX = 3,
    BLOCK_MENTION_BECH32 = 4,
    BLOCK_URL = 5,
    BLOCK_INVOICE = 6,
};

typedef struct str_block {
    const char *start;
    const char *end;
} str_block_t;

typedef struct invoice_block {
    struct str_block invstr;
    union {
        struct bolt11 *bolt11;
    };
} invoice_block_t;

typedef struct mention_bech32_block {
    struct str_block str;
    bech32_mention_t mention;
} mention_bech32_block_t;

typedef struct block {
    enum block_type type;
    union {
        struct str_block str;
        struct invoice_block invoice;
        struct mention_bech32_block mention_bech32;
        int mention_index;
    } block;
} block_t;

typedef struct blocks {
    int num_blocks;
    struct block *blocks;
} blocks_t;

void blocks_init(struct blocks *blocks);
void blocks_free(struct blocks *blocks);
int damus_parse_content(struct blocks *blocks, const char *content);

#endif /* damus_h */
