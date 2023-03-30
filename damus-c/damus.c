//
//  damus.c
//  damus
//
//  Created by William Casarin on 2022-10-17.
//

#include "damus.h"
#include "bolt11.h"
#include "bech32.h"
#include <stdlib.h>
#include <string.h>

#define TLV_SPECIAL 0
#define TLV_RELAY 1
#define TLV_AUTHOR 2
#define TLV_KIND 3

struct cursor {
    const u8 *p;
    const u8 *start;
    const u8 *end;
};

static inline int is_whitespace(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '\f' || c == '\r';
}

static inline int is_boundary(char c) {
    return !isalnum(c);
}

static inline int is_invalid_url_ending(char c) {
    return c == '!' || c == '?' || c == ')' || c == '.' || c == ',' || c == ';';
}

static void make_cursor(struct cursor *c, const u8 *content, size_t len)
{
    c->start = content;
    c->end = content + len;
    c->p = content;
}

static int consume_until_boundary(struct cursor *cur) {
    char c;
    
    while (cur->p < cur->end) {
        c = *cur->p;
        
        if (is_boundary(c))
            return 1;
        
        cur->p++;
    }
    
    return 1;
}

static int consume_until_whitespace(struct cursor *cur, int or_end) {
    char c;
    bool consumedAtLeastOne = false;
    
    while (cur->p < cur->end) {
        c = *cur->p;
        
        if (is_whitespace(c))
            return consumedAtLeastOne;
        
        cur->p++;
        consumedAtLeastOne = true;
    }
    
    return or_end;
}

static int parse_char(struct cursor *cur, char c) {
    if (cur->p >= cur->end)
        return 0;
        
    if (*cur->p == c) {
        cur->p++;
        return 1;
    }
    
    return 0;
}

static inline int peek_char(struct cursor *cur, int ind) {
    if ((cur->p + ind < cur->start) || (cur->p + ind >= cur->end))
        return -1;
    
    return *(cur->p + ind);
}

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

static int parse_str(struct cursor *cur, const char *str) {
    int i;
    char c, cs;
    unsigned long len;
    
    len = strlen(str);
    
    if (cur->p + len >= cur->end)
        return 0;
    
    for (i = 0; i < len; i++) {
        c = tolower(cur->p[i]);
        cs = tolower(str[i]);
        
        if (c != cs)
            return 0;
    }
    
    cur->p += len;
    
    return 1;
}

static int parse_mention_index(struct cursor *cur, struct block *block) {
    int d1, d2, d3, ind;
    const u8 *start = cur->p;
    
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

static int parse_hashtag(struct cursor *cur, struct block *block) {
    int c;
    const u8 *start = cur->p;
    
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

static int add_block(struct blocks *blocks, struct block block)
{
    if (blocks->num_blocks + 1 >= MAX_BLOCKS)
        return 0;
    
    blocks->blocks[blocks->num_blocks++] = block;
    return 1;
}

static int add_text_block(struct blocks *blocks, const u8 *start, const u8 *end)
{
    struct block b;
    
    if (start == end)
        return 1;
    
    b.type = BLOCK_TEXT;
    b.block.str.start = (const char*)start;
    b.block.str.end = (const char*)end;
    
    return add_block(blocks, b);
}

static int parse_url(struct cursor *cur, struct block *block) {
    const u8 *start = cur->p;
    
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
    
    if (!consume_until_whitespace(cur, 1)) {
        cur->p = start;
        return 0;
    }
    
    // strip any unwanted characters
    while(is_invalid_url_ending(peek_char(cur, -1))) cur->p--;
    
    block->type = BLOCK_URL;
    block->block.str.start = (const char *)start;
    block->block.str.end = (const char *)cur->p;
    
    return 1;
}

static int parse_invoice(struct cursor *cur, struct block *block) {
    const u8 *start, *end;
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

static int parse_mention_bech32(struct cursor *cur, struct block *block) {
    const u8 *start, *start_entity, *end;

    start = cur->p;
    if (!parse_str(cur, "nostr:"))
        return 0;

    start_entity = cur->p;
    if (!consume_until_whitespace(cur, 1)) {
        cur->p = start;
        return 0;
    }

    end = cur->p;

    char str[end - start_entity + 1];
    str[end - start_entity] = 0;
    memcpy(str, start_entity, end - start_entity);

    char prefix[end - start_entity];
    u8 data[end - start_entity];
    size_t data_len;
    size_t max_input_len = end - start_entity + 2;

    if (bech32_decode(prefix, data, &data_len, str, max_input_len) == BECH32_ENCODING_NONE) {
        cur->p = start;
        return 0;
    }

    struct mention_bech32_block mention = { 0 };
    mention.kind = -1;
    mention.buffer = (u8*)malloc(data_len);
    mention.str.start = (const char*)start;
    mention.str.end = (const char*)end;

    size_t len = 0;
    if (!bech32_convert_bits(mention.buffer, &len, 8, data, data_len, 5, 0)) {
        goto fail;
    }

    // Parse type
    if (strcmp(prefix, "note") == 0) {
        mention.type = NOSTR_BECH32_NOTE;
    } else if (strcmp(prefix, "npub") == 0) {
        mention.type = NOSTR_BECH32_NPUB;
    } else if (strcmp(prefix, "nprofile") == 0) {
        mention.type = NOSTR_BECH32_NPROFILE;
    } else if (strcmp(prefix, "nevent") == 0) {
        mention.type = NOSTR_BECH32_NEVENT;
    } else if (strcmp(prefix, "nrelay") == 0) {
        mention.type = NOSTR_BECH32_NRELAY;
    } else if (strcmp(prefix, "naddr") == 0) {
        mention.type = NOSTR_BECH32_NADDR;
    } else {
        goto fail;
    }

    // Parse notes and npubs (non-TLV)
    if (mention.type == NOSTR_BECH32_NOTE || mention.type == NOSTR_BECH32_NPUB) {
        if (len != 32) goto fail;
        if (mention.type == NOSTR_BECH32_NOTE) {
            mention.event_id = mention.buffer;
        } else {
            mention.pubkey = mention.buffer;
        }
        goto ok;
    }

    // Parse TLV entities
    const int MAX_VALUES = 16;
    int values_count = 0;
    u8 Ts[MAX_VALUES];
    u8 Ls[MAX_VALUES];
    u8* Vs[MAX_VALUES];
    for (int i = 0; i < len - 1;) {
        if (values_count == MAX_VALUES) goto fail;

        Ts[values_count] = mention.buffer[i++];
        Ls[values_count] = mention.buffer[i++];
        if (Ls[values_count] > len - i) goto fail;

        Vs[values_count] = &mention.buffer[i];
        i += Ls[values_count];
        ++values_count;
    }

    // Decode and validate all TLV-type entities
    if (mention.type == NOSTR_BECH32_NPROFILE) {
        for (int i = 0; i < values_count; ++i) {
            if (Ts[i] == TLV_SPECIAL) {
                if (Ls[i] != 32 || mention.pubkey) goto fail;
                mention.pubkey = Vs[i];
            } else if (Ts[i] == TLV_RELAY) {
                if (mention.relays_count == MAX_RELAYS) goto fail;
                Vs[i][Ls[i]] = 0;
                mention.relays[mention.relays_count++] = (char*)Vs[i];
            } else {
                goto fail;
            }
        }
        if (!mention.pubkey) goto fail;

    } else if (mention.type == NOSTR_BECH32_NEVENT) {
        for (int i = 0; i < values_count; ++i) {
            if (Ts[i] == TLV_SPECIAL) {
                if (Ls[i] != 32 || mention.event_id) goto fail;
                mention.event_id = Vs[i];
            } else if (Ts[i] == TLV_RELAY) {
                if (mention.relays_count == MAX_RELAYS) goto fail;
                Vs[i][Ls[i]] = 0;
                mention.relays[mention.relays_count++] = (char*)Vs[i];
            } else if (Ts[i] == TLV_AUTHOR) {
                if (Ls[i] != 32 || mention.pubkey) goto fail;
                mention.pubkey = Vs[i];
            } else {
                goto fail;
            }
        }
        if (!mention.event_id) goto fail;

    } else if (mention.type == NOSTR_BECH32_NRELAY) {
        if (values_count != 1 || Ts[0] != TLV_SPECIAL) goto fail;
        Vs[0][Ls[0]] = 0;
        mention.relays[mention.relays_count++] = (char*)Vs[0];

    } else { // entity.type == NOSTR_BECH32_NADDR
        for (int i = 0; i < values_count; ++i) {
            if (Ts[i] == TLV_SPECIAL) {
                Vs[i][Ls[i]] = 0;
                mention.identifier = (char*)Vs[i];
            } else if (Ts[i] == TLV_RELAY) {
                if (mention.relays_count == MAX_RELAYS) goto fail;
                Vs[i][Ls[i]] = 0;
                mention.relays[mention.relays_count++] = (char*)Vs[i];
            } else if (Ts[i] == TLV_AUTHOR) {
                if (Ls[i] != 32 || mention.pubkey) goto fail;
                mention.pubkey = Vs[i];
            } else if (Ts[i] == TLV_KIND) {
                if (Ls[i] != sizeof(int) || mention.kind != -1) goto fail;
                mention.kind = *(int*)Vs[i];
            } else {
                goto fail;
            }
        }
        if (!mention.identifier || mention.kind == -1 || !mention.pubkey) goto fail;
    }

ok:
    block->type = BLOCK_MENTION_BECH32;
    block->block.mention_bech32 = mention;
    return 1;

fail:
    free(mention.buffer);
    cur->p = start;
    return 0;
}

static int add_text_then_block(struct cursor *cur, struct blocks *blocks, struct block block, const u8 **start, const u8 *pre_mention)
{
    if (!add_text_block(blocks, *start, pre_mention))
        return 0;
    
    *start = (u8*)cur->p;
    
    if (!add_block(blocks, block))
        return 0;
    
    return 1;
}

int damus_parse_content(struct blocks *blocks, const char *content) {
    int cp, c;
    struct cursor cur;
    struct block block;
    const u8 *start, *pre_mention;
    
    blocks->num_blocks = 0;
    make_cursor(&cur, (const u8*)content, strlen(content));
    
    start = cur.p;
    while (cur.p < cur.end && blocks->num_blocks < MAX_BLOCKS) {
        cp = peek_char(&cur, -1);
        c  = peek_char(&cur, 0);
        
        pre_mention = cur.p;
        if (cp == -1 || is_whitespace(cp)) {
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
            } else if (c == 'n' && parse_mention_bech32(&cur, &block)) {
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

void blocks_init(struct blocks *blocks) {
    blocks->blocks = malloc(sizeof(struct block) * MAX_BLOCKS);
    blocks->num_blocks = 0;
}

void blocks_free(struct blocks *blocks) {
    if (!blocks->blocks) {
        return;
    }

    for (int i = 0; i < blocks->num_blocks; ++i) {
        if (blocks->blocks[i].type == BLOCK_MENTION_BECH32) {
            free(blocks->blocks[i].block.mention_bech32.buffer);
            blocks->blocks[i].block.mention_bech32.buffer = NULL;
        }
    }

    free(blocks->blocks);
    blocks->num_blocks = 0;
}
