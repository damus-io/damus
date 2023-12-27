
#ifndef NDB_BLOCK_H
#define NDB_BLOCK_H

#include "invoice.h"
#include "str_block.h"
#include "nostr_bech32.h"
#include <inttypes.h>

#pragma pack(push, 1)

struct ndb_note_blocks {
	unsigned char version;
	unsigned char padding[3];

	uint32_t words;
	uint32_t num_blocks;
	uint32_t blocks_size;
	// future expansion
	uint32_t reserved[4];
	unsigned char blocks[0]; // see ndb_block definition
};

#pragma pack(pop)

enum block_type {
    BLOCK_HASHTAG        = 1,
    BLOCK_TEXT           = 2,
    BLOCK_MENTION_INDEX  = 3,
    BLOCK_MENTION_BECH32 = 4,
    BLOCK_URL            = 5,
    BLOCK_INVOICE        = 6,
};


struct ndb_mention_bech32_block {
	struct str_block str;
	struct nostr_bech32 bech32;
};

struct ndb_invoice_block {
	struct str_block invstr;
	struct ndb_invoice invoice;
};

struct note_block {
	enum block_type type;
	union {
		struct str_block str;
		struct ndb_invoice_block invoice;
		struct ndb_mention_bech32_block mention_bech32;
		uint32_t mention_index;
	} block;
};


#endif // NDB_BLOCK_H
