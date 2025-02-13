

#include "nostrdb.h"
#include "block.h"
#include <stdlib.h>

struct ndb_block_iterator {
	const char *content;
	struct ndb_blocks *blocks;
	struct ndb_block block;
	struct cursor cur;
};

int push_str_block(struct cursor *buf, const char *content, struct ndb_str_block *block) {
	return cursor_push_varint(buf, block->str - content) &&
	       cursor_push_varint(buf, block->len);
}

int pull_str_block(struct cursor *buf, const char *content, struct ndb_str_block *block) {
	uint32_t start;
	if (!cursor_pull_varint_u32(buf, &start))
		return 0;

	block->str = content + start;

	return cursor_pull_varint_u32(buf, &block->len);
}

static int pull_nostr_bech32_type(struct cursor *cur, enum nostr_bech32_type *type)
{
	uint64_t inttype;
	if (!cursor_pull_varint(cur, &inttype))
		return 0;

	if (inttype <= 0 || inttype > NOSTR_BECH32_KNOWN_TYPES)
		return 0;

	*type = inttype;
	return 1;
}


static int pull_bech32_mention(const char *content, struct cursor *cur, struct ndb_mention_bech32_block *block) {
	uint16_t size;
	unsigned char *start;
	struct cursor bech32;

	if (!pull_str_block(cur, content, &block->str))
		return 0;

	if (!cursor_pull_u16(cur, &size))
		return 0;

	if (!pull_nostr_bech32_type(cur, &block->bech32.type))
		return 0;

	make_cursor(cur->p, cur->p + size, &bech32);

	start = cur->p;

	if (!parse_nostr_bech32_buffer(&bech32, block->bech32.type, &block->bech32))
		return 0;

	//assert(bech32.p == start + size);
	cur->p = start + size;
	return 1;
}

static int pull_invoice(const char *content, struct cursor *cur,
			struct ndb_invoice_block *block)
{
	if (!pull_str_block(cur, content, &block->invstr))
		return 0;

	return ndb_decode_invoice(cur, &block->invoice);
}

static int pull_block_type(struct cursor *cur, enum ndb_block_type *type)
{
	uint32_t itype;
	*type = 0;
	if (!cursor_pull_varint_u32(cur, &itype))
		return 0;

	if (itype <= 0 || itype > NDB_NUM_BLOCK_TYPES)
		return 0;

	*type = itype;
	return 1;
}

static int pull_block(const char *content, struct cursor *cur, struct ndb_block *block)
{
	unsigned char *start = cur->p;

	if (!pull_block_type(cur, &block->type))
		return 0;

	switch (block->type) {
	case BLOCK_HASHTAG:
	case BLOCK_TEXT:
	case BLOCK_URL:
		if (!pull_str_block(cur, content, &block->block.str))
			goto fail;
		break;

	case BLOCK_MENTION_INDEX:
		if (!cursor_pull_varint_u32(cur, &block->block.mention_index))
			goto fail;
		break;

	case BLOCK_MENTION_BECH32:
		if (!pull_bech32_mention(content, cur, &block->block.mention_bech32))
			goto fail;
		break;

	case BLOCK_INVOICE:
		// we only push invoice strs here
		if (!pull_invoice(content, cur, &block->block.invoice))
			goto fail;
		break;
	}

	return 1;
fail:
	cur->p = start;
	return 0;
}


enum ndb_block_type ndb_get_block_type(struct ndb_block *block) {
	return block->type;
}

// BLOCK ITERATORS
struct ndb_block_iterator *ndb_blocks_iterate_start(const char *content, struct ndb_blocks *blocks) {
	struct ndb_block_iterator *iter = malloc(sizeof(*iter));
	if (!iter)
		return NULL;

	iter->blocks = blocks;
	iter->content = content;

	make_cursor((unsigned char *)blocks->blocks,
		    blocks->blocks + blocks->blocks_size, &iter->cur);

	return iter;
}

void ndb_blocks_iterate_free(struct ndb_block_iterator *iter)
{
	if (iter)
		free(iter);
}

struct ndb_block *ndb_blocks_iterate_next(struct ndb_block_iterator *iter)
{
	while (iter->cur.p < iter->cur.end) {
		if (!pull_block(iter->content, &iter->cur, &iter->block)) {
			return NULL;
		} else {
			return &iter->block;
		}
	}

	return NULL;
}

// STR BLOCKS
struct ndb_str_block *ndb_block_str(struct ndb_block *block)
{
	switch (block->type) {
	case BLOCK_HASHTAG:
	case BLOCK_TEXT:
	case BLOCK_URL:
		return &block->block.str;
	case BLOCK_MENTION_INDEX:
		return NULL;
	case BLOCK_MENTION_BECH32:
		return &block->block.mention_bech32.str;
	case BLOCK_INVOICE:
		return &block->block.invoice.invstr;
	}

	return NULL;
}

const char *ndb_str_block_ptr(struct ndb_str_block *str_block) {
	return str_block->str;
}

uint32_t ndb_str_block_len(struct ndb_str_block *str_block) {
	return str_block->len;
}

struct nostr_bech32 *ndb_bech32_block(struct ndb_block *block) {
	return &block->block.mention_bech32.bech32;
}
