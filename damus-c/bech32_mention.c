//
//  bech32_mention.c
//  damus
//
//  Created by Bartholomew Joyce on 2023-04-03.
//

#include "bech32_mention.h"
#include "bech32.h"
#include <stdlib.h>
#include <string.h>

#define TLV_SPECIAL 0
#define TLV_RELAY 1
#define TLV_AUTHOR 2
#define TLV_KIND 3

int bech32_mention_parse(bech32_mention_t *mention, const char* str, int len) {

    char prefix[len];
    u8 words[len];
    size_t words_len;
    size_t max_input_len = len + 2;

    if (bech32_decode(prefix, words, &words_len, str, max_input_len) == BECH32_ENCODING_NONE) {
        return 0;
    }

    memset(mention, 0, sizeof(bech32_mention_t));
    mention->kind = -1;
    mention->buffer = (u8*)malloc(words_len);

    size_t data_len = 0;
    if (!bech32_convert_bits(mention->buffer, &data_len, 8, words, words_len, 5, 0)) {
        goto fail;
    }

    // Parse type
    if (strcmp(prefix, "note") == 0) {
        mention->type = BECH32_MENTION_NOTE;
    } else if (strcmp(prefix, "npub") == 0) {
        mention->type = BECH32_MENTION_NPUB;
    } else if (strcmp(prefix, "nprofile") == 0) {
        mention->type = BECH32_MENTION_NPROFILE;
    } else if (strcmp(prefix, "nevent") == 0) {
        mention->type = BECH32_MENTION_NEVENT;
    } else if (strcmp(prefix, "nrelay") == 0) {
        mention->type = BECH32_MENTION_NRELAY;
    } else if (strcmp(prefix, "naddr") == 0) {
        mention->type = BECH32_MENTION_NADDR;
    } else {
        goto fail;
    }

    // Parse notes and npubs (non-TLV)
    if (mention->type == BECH32_MENTION_NOTE || mention->type == BECH32_MENTION_NPUB) {
        if (data_len != 32) goto fail;
        if (mention->type == BECH32_MENTION_NOTE) {
            mention->event_id = mention->buffer;
        } else {
            mention->pubkey = mention->buffer;
        }
        goto ok;
    }

    // Parse TLV entities
    const int MAX_VALUES = 16;
    int values_count = 0;
    u8 Ts[MAX_VALUES];
    u8 Ls[MAX_VALUES];
    u8* Vs[MAX_VALUES];
    for (int i = 0; i < data_len - 1;) {
        if (values_count == MAX_VALUES) goto fail;

        Ts[values_count] = mention->buffer[i++];
        Ls[values_count] = mention->buffer[i++];
        if (Ls[values_count] > data_len - i) goto fail;

        Vs[values_count] = &mention->buffer[i];
        i += Ls[values_count];
        ++values_count;
    }

    // Decode and validate all TLV-type entities
    if (mention->type == BECH32_MENTION_NPROFILE) {
        for (int i = 0; i < values_count; ++i) {
            if (Ts[i] == TLV_SPECIAL) {
                if (Ls[i] != 32 || mention->pubkey) goto fail;
                mention->pubkey = Vs[i];
            } else if (Ts[i] == TLV_RELAY) {
                if (mention->relays_count == MAX_RELAYS) goto fail;
                Vs[i][Ls[i]] = 0;
                mention->relays[mention->relays_count++] = (char*)Vs[i];
            } else {
                goto fail;
            }
        }
        if (!mention->pubkey) goto fail;

    } else if (mention->type == BECH32_MENTION_NEVENT) {
        for (int i = 0; i < values_count; ++i) {
            if (Ts[i] == TLV_SPECIAL) {
                if (Ls[i] != 32 || mention->event_id) goto fail;
                mention->event_id = Vs[i];
            } else if (Ts[i] == TLV_RELAY) {
                if (mention->relays_count == MAX_RELAYS) goto fail;
                Vs[i][Ls[i]] = 0;
                mention->relays[mention->relays_count++] = (char*)Vs[i];
            } else if (Ts[i] == TLV_AUTHOR) {
                if (Ls[i] != 32 || mention->pubkey) goto fail;
                mention->pubkey = Vs[i];
            } else {
                goto fail;
            }
        }
        if (!mention->event_id) goto fail;

    } else if (mention->type == BECH32_MENTION_NRELAY) {
        if (values_count != 1 || Ts[0] != TLV_SPECIAL) goto fail;
        Vs[0][Ls[0]] = 0;
        mention->relays[mention->relays_count++] = (char*)Vs[0];

    } else { // entity.type == BECH32_MENTION_NADDR
        for (int i = 0; i < values_count; ++i) {
            if (Ts[i] == TLV_SPECIAL) {
                Vs[i][Ls[i]] = 0;
                mention->identifier = (char*)Vs[i];
            } else if (Ts[i] == TLV_RELAY) {
                if (mention->relays_count == MAX_RELAYS) goto fail;
                Vs[i][Ls[i]] = 0;
                mention->relays[mention->relays_count++] = (char*)Vs[i];
            } else if (Ts[i] == TLV_AUTHOR) {
                if (Ls[i] != 32 || mention->pubkey) goto fail;
                mention->pubkey = Vs[i];
            } else if (Ts[i] == TLV_KIND) {
                if (Ls[i] != sizeof(int) || mention->kind != -1) goto fail;
                mention->kind = *(int*)Vs[i];
            } else {
                goto fail;
            }
        }
        if (!mention->identifier || mention->kind == -1 || !mention->pubkey) goto fail;
    }

ok:
    return 1;

fail:
    free(mention->buffer);
    return 0;
}

void bech32_mention_free(bech32_mention_t *mention) {
    free(mention->buffer);
    mention->buffer = 0;
}
