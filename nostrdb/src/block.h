
#ifndef NDB_BLOCK_H
#define NDB_BLOCK_H

#include "invoice.h"
#include "str_block.h"
#include "cursor.h"
#include "nostr_bech32.h"
#include "nostrdb.h"
#include <inttypes.h>

#pragma pack(push, 1)

struct ndb_blocks {
	unsigned char version;
	unsigned char padding[3];

	uint32_t words;
	uint32_t num_blocks;
	uint32_t blocks_size;
	// future expansion
	uint32_t reserved[2];
	unsigned char blocks[0]; // see ndb_block definition
};

#pragma pack(pop)

struct ndb_mention_bech32_block {
	struct ndb_str_block str;
	struct nostr_bech32 bech32;
};

struct ndb_invoice_block {
	struct ndb_str_block invstr;
	struct ndb_invoice invoice;
};

struct ndb_block {
	enum ndb_block_type type;
	union {
		struct ndb_str_block str;
		struct ndb_invoice_block invoice;
		struct ndb_mention_bech32_block mention_bech32;
		uint32_t mention_index;
	} block;
};

int push_str_block(struct cursor *buf, const char *content, struct ndb_str_block *block);
int pull_str_block(struct cursor *buf, const char *content, struct ndb_str_block *block);


#endif // NDB_BLOCK_H
