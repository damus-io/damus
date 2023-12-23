#include "damus.h"
#include "cursor.h"
#include "bolt11.h"
#include "bech32.h"
#include <stdlib.h>
#include <string.h>

#include "cursor.h"

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


static int parse_mention_index(struct cursor *cur, struct note_block *block) {
	int d1, d2, d3, ind;
	u8 *start = cur->p;
	
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

static int parse_hashtag(struct cursor *cur, struct note_block *block) {
	int c;
	u8 *start = cur->p;
	
	if (!parse_char(cur, '#'))
		return 0;
	
	c = peek_char(cur, 0);
	if (c == -1 || is_whitespace(c) || c == '#') {
		cur->p = start;
		return 0;
	}
	
	consume_until_boundary(cur);
	
	block->type = BLOCK_HASHTAG;
	block->block.str.start = (const char*)(start + 1);
	block->block.str.end = (const char*)cur->p;
	
	return 1;
}

static int add_block(struct note_blocks *blocks, struct note_block block)
{
	if (blocks->num_blocks + 1 >= MAX_BLOCKS)
		return 0;
	
	blocks->blocks[blocks->num_blocks++] = block;
	return 1;
}

static int add_text_block(struct note_blocks *blocks, const u8 *start, const u8 *end)
{
	struct note_block b;
	
	if (start == end)
		return 1;
	
	b.type = BLOCK_TEXT;
	b.block.str.start = (const char*)start;
	b.block.str.end = (const char*)end;
	
	return add_block(blocks, b);
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

	return consume_until_whitespace(cur, 1);
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

		if (c == '?' || c == '#' || is_whitespace(c)) {
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
		if (is_alphanumeric(c) || c == '.' || c == '-')
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

static int parse_url(struct cursor *cur, struct note_block *block) {
	u8 *start = cur->p;
	u8 *host;
	int host_len;
	struct cursor path_cur;
	
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
	block->block.str.start = (const char *)path_cur.p;

	// if we have a damus link, make it a mention
	if (host_len == 8
	&& !strncmp((const char *)host, "damus.io", 8)
	&& parse_nostr_bech32(&path_cur, &block->block.mention_bech32.bech32))
	{
		block->block.str.end = (const char *)path_cur.p;
		block->type = BLOCK_MENTION_BECH32;
		return 1;
	}

	block->type = BLOCK_URL;
	block->block.str.start = (const char *)start;
	block->block.str.end = (const char *)cur->p;
	
	return 1;
}

static int parse_invoice(struct cursor *cur, struct note_block *block) {
	u8 *start, *end;
	char *fail;
	struct bolt11 *bolt11;
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
	
	char str[end - start + 1];
	str[end - start] = 0;
	memcpy(str, start, end - start);
	
	if (!(bolt11 = bolt11_decode(NULL, str, &fail))) {
		cur->p = start;
		return 0;
	}
	
	block->type = BLOCK_INVOICE;
	
	block->block.invoice.invstr.start = (const char*)start;
	block->block.invoice.invstr.end = (const char*)end;
	block->block.invoice.bolt11 = bolt11;
	
	cur->p = end;
	
	return 1;
}


static int parse_mention_bech32(struct cursor *cur, struct note_block *block) {
	u8 *start = cur->p;
	
	parse_char(cur, '@');
	parse_str(cur, "nostr:");

	block->block.str.start = (const char *)cur->p;
	
	if (!parse_nostr_bech32(cur, &block->block.mention_bech32.bech32)) {
		cur->p = start;
		return 0;
	}
	
	block->block.str.end = (const char *)cur->p;
	
	block->type = BLOCK_MENTION_BECH32;

	return 1;
}

static int add_text_then_block(struct cursor *cur, struct note_blocks *blocks, struct note_block block, u8 **start, const u8 *pre_mention)
{
	if (!add_text_block(blocks, *start, pre_mention))
		return 0;
	
	*start = (u8*)cur->p;
	
	if (!add_block(blocks, block))
		return 0;
	
	return 1;
}

int ndb_parse_content(struct note_blocks *blocks, const char *content) {
	int cp, c;
	struct cursor cur;
	struct note_block block;
	u8 *start, *pre_mention;
	
	blocks->words = 0;
	blocks->num_blocks = 0;
	make_cursor((u8*)content, (u8*)content + strlen(content), &cur);
	
	start = cur.p;
	while (cur.p < cur.end && blocks->num_blocks < MAX_BLOCKS) {
		cp = peek_char(&cur, -1);
		c  = peek_char(&cur, 0);
		
		// new word
		if (is_whitespace(cp) && !is_whitespace(c)) {
			blocks->words++;
		}
		
		pre_mention = cur.p;
		if (cp == -1 || is_left_boundary(cp) || c == '#') {
			if (c == '#' && (parse_mention_index(&cur, &block) || parse_hashtag(&cur, &block))) {
				if (!add_text_then_block(&cur, blocks, block, &start, pre_mention))
					return 0;
				continue;
			} else if ((c == 'h' || c == 'H') && parse_url(&cur, &block)) {
				if (!add_text_then_block(&cur, blocks, block, &start, pre_mention))
					return 0;
				continue;
			} else if ((c == 'l' || c == 'L') && parse_invoice(&cur, &block)) {
				if (!add_text_then_block(&cur, blocks, block, &start, pre_mention))
					return 0;
				continue;
			} else if ((c == 'n' || c == '@') && parse_mention_bech32(&cur, &block)) {
				if (!add_text_then_block(&cur, blocks, block, &start, pre_mention))
					return 0;
				continue;
			}
		}
		
		cur.p++;
	}
	
	if (cur.p - start > 0) {
		if (!add_text_block(blocks, start, cur.p))
			return 0;
	}
	
	return 1;
}

void blocks_init(struct note_blocks *blocks) {
	blocks->blocks = malloc(sizeof(struct note_block) * MAX_BLOCKS);
	blocks->num_blocks = 0;
}

void blocks_free(struct note_blocks *blocks) {
	if (!blocks->blocks) {
		return;
	}
	
	for (int i = 0; i < blocks->num_blocks; ++i) {
		if (blocks->blocks[i].type == BLOCK_MENTION_BECH32) {
			free(blocks->blocks[i].block.mention_bech32.bech32.buffer);
			blocks->blocks[i].block.mention_bech32.bech32.buffer = NULL;
		}
	}

	free(blocks->blocks);
	blocks->num_blocks = 0;
}
