#include "cursor.h"
#include "nostr_bech32.h"
#include "block.h"
#include "nostrdb.h"
#include "invoice.h"
#include "bolt11/bolt11.h"
#include "bolt11/bech32.h"
#include <stdlib.h>
#include <string.h>

#include "cursor.h"

struct ndb_content_parser {
	int bech32_strs;
	struct cursor buffer;
	struct cursor content;
	struct ndb_blocks *blocks;
};

static int parse_digit(struct cursor *cur, int *digit) {
	int c;
	if ((c = peek_char(cur, 0)) == -1)
		return 0;
	
	c -= '0';
	
	if (c >= 0 && c <= 9) {
		*digit = c;
		cur->p++;
		return 1;
	}
	return 0;
}


static int parse_mention_index(struct cursor *cur, struct ndb_block *block) {
	int d1, d2, d3, ind;
	unsigned char *start = cur->p;
	
	if (!parse_str(cur, "#["))
		return 0;
	
	if (!parse_digit(cur, &d1)) {
		cur->p = start;
		return 0;
	}
	
	ind = d1;
	
	if (parse_digit(cur, &d2))
		ind = (d1 * 10) + d2;
	
	if (parse_digit(cur, &d3))
		ind = (d1 * 100) + (d2 * 10) + d3;
	
	if (!parse_char(cur, ']')) {
		cur->p = start;
		return 0;
	}
	
	block->type = BLOCK_MENTION_INDEX;
	block->block.mention_index = ind;
	
	return 1;
}

static int parse_hashtag(struct cursor *cur, struct ndb_block *block) {
	int c;
	unsigned char *start = cur->p;
	
	if (!parse_char(cur, '#'))
		return 0;
	
	c = peek_char(cur, 0);
	if (c == -1 || is_whitespace(c) || c == '#') {
		cur->p = start;
		return 0;
	}
	
	consume_until_boundary(cur);
	
	block->type = BLOCK_HASHTAG;
	block->block.str.str = (const char*)(start + 1);
	block->block.str.len = cur->p - (start + 1);
	
	return 1;
}

//
// decode and push a bech32 mention into our blocks output buffer.
//
// bech32 blocks are stored as:
//
//     nostr_bech32_type  : varint
//     bech32_buffer_size : u16
//     bech32_data        : [u8]
//
// The TLV form is compact already, so we just use it directly
//
// This allows us to not duplicate all of the TLV encoding and decoding code
// for our on-disk nostrdb format.
//
static int push_bech32_mention(struct ndb_content_parser *p, struct ndb_str_block *bech32)
{
	// we decode the raw bech32 directly into the output buffer
	struct cursor u8, u5;
	unsigned char *start;
	uint16_t *u8_size;
	enum nostr_bech32_type type;
	size_t u5_out_len, u8_out_len;
	static const int MAX_PREFIX = 8;
	char prefix[9] = {0};

	start = p->buffer.p;

	if (!parse_nostr_bech32_type(bech32->str, &type))
		goto fail;

	// make sure to push the str block!
	if (!push_str_block(&p->buffer, (const char*)p->content.start, bech32))
		goto fail;

	if (!cursor_push_varint(&p->buffer, type))
		goto fail;

	// save a spot for the raw bech32 buffer size
	u8_size = (uint16_t*)p->buffer.p;
	if (!cursor_skip(&p->buffer, 2))
		goto fail;

	if (!cursor_malloc_slice(&p->buffer, &u8, bech32->len))
		goto fail;

	if (!cursor_malloc_slice(&p->buffer, &u5, bech32->len))
		goto fail;
	
	if (bech32_decode_len(prefix, u5.p, &u5_out_len, bech32->str,
			      bech32->len, MAX_PREFIX) == BECH32_ENCODING_NONE) {
		goto fail;
	}

	u5.p += u5_out_len;

	if (!bech32_convert_bits(u8.p, &u8_out_len, 8, u5.start, u5.p - u5.start, 5, 0))
		goto fail;

	u8.p += u8_out_len;

	// move the out cursor to the end of the 8-bit buffer
	p->buffer.p = u8.p;

	if (u8_out_len > UINT16_MAX)
		goto fail;

	// mark the size of the bech32 buffer
	*u8_size = (uint16_t)u8_out_len;

	return 1;

fail:
	p->buffer.p = start;
	return 0;
}

static int push_invoice_str(struct ndb_content_parser *p, struct ndb_str_block *str)
{
	unsigned char *start;
	struct bolt11 *bolt11;
	char *fail;

	if (!(bolt11 = bolt11_decode(NULL, str->str, &fail)))
		return 0;

	start = p->buffer.p;

	// push the text block just incase we don't care for the invoice
	if (!push_str_block(&p->buffer, (const char*)p->content.start, str))
		return 0;

	// push decoded invoice data for quick access
	if (!ndb_encode_invoice(&p->buffer, bolt11)) {
		p->buffer.p = start;
		tal_free(bolt11);
		return 0;
	}

	tal_free(bolt11);
	return 1;
}

int push_block(struct ndb_content_parser *p, struct ndb_block *block);
static int add_text_block(struct ndb_content_parser *p, const char *start, const char *end)
{
	struct ndb_block b;
	
	if (start == end)
		return 1;
	
	b.type = BLOCK_TEXT;
	b.block.str.str = start;
	b.block.str.len = end - start;
	
	return push_block(p, &b);
}


int push_block(struct ndb_content_parser *p, struct ndb_block *block)
{
	unsigned char *start = p->buffer.p;

	// push the tag
	if (!cursor_push_varint(&p->buffer, block->type))
		return 0;

	switch (block->type) {
	case BLOCK_HASHTAG:
	case BLOCK_TEXT:
	case BLOCK_URL:
		if (!push_str_block(&p->buffer, (const char*)p->content.start,
			       &block->block.str))
			goto fail;
		break;

	case BLOCK_MENTION_INDEX:
		if (!cursor_push_varint(&p->buffer, block->block.mention_index))
			goto fail;
		break;
	case BLOCK_MENTION_BECH32:
		// we only push bech32 strs here
		if (!push_bech32_mention(p, &block->block.str)) {
			// if we fail for some reason, try pushing just a text block
			p->buffer.p = start;
			if (!add_text_block(p, block->block.str.str,
					       block->block.str.str +
					       block->block.str.len)) {
				goto fail;
			}
		}
		break;

	case BLOCK_INVOICE:
		// we only push invoice strs here
		if (!push_invoice_str(p, &block->block.str)) {
			// if we fail for some reason, try pushing just a text block
			p->buffer.p = start;
			if (!add_text_block(p, block->block.str.str,
					    block->block.str.str + block->block.str.len)) {
				goto fail;
			}
		}
		break;
	}

	p->blocks->num_blocks++;

	return 1;

fail:
	p->buffer.p = start;
	return 0;
}



static inline int next_char_is_whitespace(unsigned char *cur, unsigned char *end) {
	unsigned char *next = cur + 1;

	if (next > end)
		return 0;

	if (next == end)
		return 1;

	return is_whitespace(*next);
}

static inline int char_disallowed_at_end_url(char c)
{
	return c == '.' || c == ',';
 
}

static int is_final_url_char(unsigned char *cur, unsigned char *end) 
{
	if (is_whitespace(*cur))
		return 1;

	if (next_char_is_whitespace(cur, end)) {
		// next char is whitespace so this char could be the final char in the url
		return char_disallowed_at_end_url(*cur);
	}

	// next char isn't whitespace so it can't be a final char
	return 0;
}

static int consume_until_end_url(struct cursor *cur, int or_end) {
	unsigned char *start = cur->p;

	while (cur->p < cur->end) {
		if (is_final_url_char(cur->p, cur->end))
			return cur->p != start;

		cur->p++;
	}

	return or_end;
}

static int consume_url_fragment(struct cursor *cur)
{
	int c;

	if ((c = peek_char(cur, 0)) < 0)
		return 1;

	if (c != '#' && c != '?') {
		return 1;
	}

	cur->p++;

	return consume_until_end_url(cur, 1);
}

static int consume_url_path(struct cursor *cur)
{
	int c;

	if ((c = peek_char(cur, 0)) < 0)
		return 1;

	if (c != '/') {
		return 1;
	}

	while (cur->p < cur->end) {
		c = *cur->p;

		if (c == '?' || c == '#' || is_final_url_char(cur->p, cur->end)) {
			return 1;
		}

		cur->p++;
	}

	return 1;
}

static int consume_url_host(struct cursor *cur)
{
	char c;
	int count = 0;

	while (cur->p < cur->end) {
		c = *cur->p;
		// TODO: handle IDNs
		if ((is_alphanumeric(c) || c == '.' || c == '-') && !is_final_url_char(cur->p, cur->end))
		{
			count++;
			cur->p++;
			continue;
		}

		return count != 0;
	}


	// this means the end of the URL hostname is the end of the buffer and we finished
	return count != 0;
}

static int parse_url(struct cursor *cur, struct ndb_block *block) {
	unsigned char *start = cur->p;
	unsigned char *host;
	unsigned char tmp[4096];
	int host_len;
	struct cursor path_cur, tmp_cur;
	enum nostr_bech32_type type;
	make_cursor(tmp, tmp + sizeof(tmp), &tmp_cur);
	
	if (!parse_str(cur, "http"))
		return 0;
	
	if (parse_char(cur, 's') || parse_char(cur, 'S')) {
		if (!parse_str(cur, "://")) {
			cur->p = start;
			return 0;
		}
	} else {
		if (!parse_str(cur, "://")) {
			cur->p = start;
			return 0;
		}
	}

	// make sure to save the hostname. We will use this to detect damus.io links
	host = cur->p;

	if (!consume_url_host(cur)) {
		cur->p = start;
		return 0;
	}

	// get the length of the host string
	host_len = (int)(cur->p - host);

	// save the current parse state so that we can continue from here when
	// parsing the bech32 in the damus.io link if we have it
	copy_cursor(cur, &path_cur);

	// skip leading /
	cursor_skip(&path_cur, 1);

	if (!consume_url_path(cur)) {
		cur->p = start;
		return 0;
	}

	if (!consume_url_fragment(cur)) {
		cur->p = start;
		return 0;
	}

	// smart parens
	if (start - 1 >= 0 &&
		start < cur->end &&
		*(start - 1) == '(' &&
		(cur->p - 1) < cur->end &&
		*(cur->p - 1) == ')')
	{
		cur->p--;
	}

	// save the bech32 string pos in case we hit a damus.io link
	block->block.str.str = (const char *)path_cur.p;

	// if we have a damus link, make it a mention
	if (host_len == 8
	&& !strncmp((const char *)host, "damus.io", 8)
	&& parse_nostr_bech32_str(&path_cur, &type))
	{
		block->block.str.len = path_cur.p - path_cur.start;
		block->type = BLOCK_MENTION_BECH32;
		return 1;
	}

	block->type = BLOCK_URL;
	block->block.str.str = (const char *)start;
	block->block.str.len = cur->p - start;
	
	return 1;
}

static int parse_invoice(struct cursor *cur, struct ndb_block *block) {
	unsigned char *start, *end;

	// optional
	parse_str(cur, "lightning:");
	
	start = cur->p;
	
	if (!parse_str(cur, "lnbc"))
		return 0;
	
	if (!consume_until_whitespace(cur, 1)) {
		cur->p = start;
		return 0;
	}
	
	end = cur->p;
	
	block->type = BLOCK_INVOICE;
	
	block->block.str.str = (const char*)start;
	block->block.str.len = end - start;
	
	cur->p = end;
	
	return 1;
}


static int parse_mention_bech32(struct cursor *cur, struct ndb_block *block) {
	unsigned char *start = cur->p;
	enum nostr_bech32_type type;
	
	parse_char(cur, '@');
	parse_str(cur, "nostr:");

	block->block.str.str = (const char *)cur->p;
	
	if (!parse_nostr_bech32_str(cur, &type)) {
		cur->p = start;
		return 0;
	}
	
	block->block.str.len = cur->p - start;
	block->type = BLOCK_MENTION_BECH32;

	return 1;
}

static int add_text_then_block(struct ndb_content_parser *p,
			       struct ndb_block *block,
			       unsigned char **start,
			       const unsigned char *pre_mention)
{
	if (!add_text_block(p, (const char *)*start, (const char*)pre_mention))
		return 0;
	
	*start = (unsigned char*)p->content.p;
	
	return push_block(p, block);
}

int ndb_parse_content(unsigned char *buf, int buf_size,
		      const char *content, int content_len,
		      struct ndb_blocks **blocks_p)
{
	int cp, c;
	struct ndb_content_parser parser;
	struct ndb_block block;

	unsigned char *start, *pre_mention;
	
	make_cursor(buf, buf + buf_size, &parser.buffer);

	// allocate some space for the blocks header
	*blocks_p = parser.blocks = (struct ndb_blocks *)buf;
	parser.buffer.p += sizeof(struct ndb_blocks);

	make_cursor((unsigned char *)content,
		    (unsigned char*)content + content_len, &parser.content);

	parser.blocks->words = 0;
	parser.blocks->num_blocks = 0;
	parser.blocks->blocks_size = 0;

	start = parser.content.p;
	while (parser.content.p < parser.content.end) {
		cp = peek_char(&parser.content, -1);
		c  = peek_char(&parser.content, 0);
		
		// new word
		if (is_whitespace(cp) && !is_whitespace(c))
			parser.blocks->words++;
		
		pre_mention = parser.content.p;
		if (cp == -1 || is_left_boundary(cp) || c == '#') {
			if (c == '#' && (parse_mention_index(&parser.content, &block) || parse_hashtag(&parser.content, &block))) {
				if (!add_text_then_block(&parser, &block, &start, pre_mention))
					return 0;
				continue;
			} else if ((c == 'h' || c == 'H') && parse_url(&parser.content, &block)) {
				if (!add_text_then_block(&parser, &block, &start, pre_mention))
					return 0;
				continue;
			} else if ((c == 'l' || c == 'L') && parse_invoice(&parser.content, &block)) {
				if (!add_text_then_block(&parser, &block, &start, pre_mention))
					return 0;
				continue;
			} else if ((c == 'n' || c == '@') && parse_mention_bech32(&parser.content, &block)) {
				if (!add_text_then_block(&parser, &block, &start, pre_mention))
					return 0;
				continue;
			}
		}
		
		parser.content.p++;
	}
	
	if (parser.content.p - start > 0) {
		if (!add_text_block(&parser, (const char*)start, (const char *)parser.content.p))
			return 0;
	}

	// pad to 8-byte alignment
	if (!cursor_align(&parser.buffer, 8))
		return 0;
	assert((parser.buffer.p - parser.buffer.start) % 8 == 0);

	parser.blocks->blocks_size = parser.buffer.p - parser.buffer.start;
	
	return 1;
}

