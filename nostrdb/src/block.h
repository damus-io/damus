
#ifndef NDB_BLOCK_H
#define NDB_BLOCK_H

#include "invoice.h"
#include "str_block.h"
#include "cursor.h"
#include "nostr_bech32.h"
#include "nostrdb.h"
#include <inttypes.h>

#define NDB_BLOCK_FLAG_OWNED 1

#pragma pack(push, 1)

struct ndb_blocks {
	unsigned char version;
	unsigned char flags;
	unsigned char padding[2];

	uint32_t words;
	uint32_t num_blocks;
	uint32_t blocks_size;
	// future expansion
	uint32_t total_size;
	uint32_t reserved;
	unsigned char blocks[0]; // see ndb_block definition
};

#pragma pack(pop)

int push_str_block(struct cursor *buf, const char *content, struct ndb_str_block *block);
int pull_str_block(struct cursor *buf, const char *content, struct ndb_str_block *block);


#endif // NDB_BLOCK_H
