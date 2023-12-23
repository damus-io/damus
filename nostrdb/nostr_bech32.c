//
//  nostr_bech32.c
//  damus
//
//  Created by William Casarin on 2023-04-09.
//

#include "nostr_bech32.h"
#include <stdlib.h>
#include "cursor.h"
#include "bech32.h"

#define MAX_TLVS 16

#define TLV_SPECIAL 0
#define TLV_RELAY 1
#define TLV_AUTHOR 2
#define TLV_KIND 3
#define TLV_KNOWN_TLVS 4

struct nostr_tlv {
    u8 type;
    u8 len;
    const u8 *value;
};

struct nostr_tlvs {
    struct nostr_tlv tlvs[MAX_TLVS];
    int num_tlvs;
};

static int parse_nostr_tlv(struct cursor *cur, struct nostr_tlv *tlv) {
    // get the tlv tag
    if (!pull_byte(cur, &tlv->type))
        return 0;
    
    // unknown, fail!
    if (tlv->type >= TLV_KNOWN_TLVS)
        return 0;
    
    // get the length
    if (!pull_byte(cur, &tlv->len))
        return 0;
    
    // is the reported length greater then our buffer? if so fail
    if (cur->p + tlv->len > cur->end)
        return 0;
    
    tlv->value = cur->p;
    cur->p += tlv->len;
    
    return 1;
}

static int parse_nostr_tlvs(struct cursor *cur, struct nostr_tlvs *tlvs) {
    int i;
    tlvs->num_tlvs = 0;
    
    for (i = 0; i < MAX_TLVS; i++) {
        if (parse_nostr_tlv(cur, &tlvs->tlvs[i])) {
            tlvs->num_tlvs++;
        } else {
            break;
        }
    }
    
    if (tlvs->num_tlvs == 0)
        return 0;
    
    return 1;
}

static int find_tlv(struct nostr_tlvs *tlvs, u8 type, struct nostr_tlv **tlv) {
    *tlv = NULL;
    
    for (int i = 0; i < tlvs->num_tlvs; i++) {
        if (tlvs->tlvs[i].type == type) {
            *tlv = &tlvs->tlvs[i];
            return 1;
        }
    }
    
    return 0;
}

static int parse_nostr_bech32_type(const char *prefix, enum nostr_bech32_type *type) {
    // Parse type
    if (strcmp(prefix, "note") == 0) {
        *type = NOSTR_BECH32_NOTE;
        return 1;
    } else if (strcmp(prefix, "npub") == 0) {
        *type = NOSTR_BECH32_NPUB;
        return 1;
    } else if (strcmp(prefix, "nsec") == 0) {
        *type = NOSTR_BECH32_NSEC;
        return 1;
    } else if (strcmp(prefix, "nprofile") == 0) {
        *type = NOSTR_BECH32_NPROFILE;
        return 1;
    } else if (strcmp(prefix, "nevent") == 0) {
        *type = NOSTR_BECH32_NEVENT;
        return 1;
    } else if (strcmp(prefix, "nrelay") == 0) {
        *type = NOSTR_BECH32_NRELAY;
        return 1;
    } else if (strcmp(prefix, "naddr") == 0) {
        *type = NOSTR_BECH32_NADDR;
        return 1;
    }
    
    return 0;
}

static int parse_nostr_bech32_note(struct cursor *cur, struct bech32_note *note) {
    return pull_bytes(cur, 32, &note->event_id);
}

static int parse_nostr_bech32_npub(struct cursor *cur, struct bech32_npub *npub) {
    return pull_bytes(cur, 32, &npub->pubkey);
}

static int parse_nostr_bech32_nsec(struct cursor *cur, struct bech32_nsec *nsec) {
    return pull_bytes(cur, 32, &nsec->nsec);
}

static int tlvs_to_relays(struct nostr_tlvs *tlvs, struct relays *relays) {
    struct nostr_tlv *tlv;
    struct str_block *str;
    
    relays->num_relays = 0;
    
    for (int i = 0; i < tlvs->num_tlvs; i++) {
        tlv = &tlvs->tlvs[i];
        if (tlv->type != TLV_RELAY)
            continue;
        
        if (relays->num_relays + 1 > MAX_RELAYS)
            break;
        
        str = &relays->relays[relays->num_relays++];
        str->start = (const char*)tlv->value;
        str->end = (const char*)(tlv->value + tlv->len);
    }
    
    return 1;
}

static int parse_nostr_bech32_nevent(struct cursor *cur, struct bech32_nevent *nevent) {
    struct nostr_tlvs tlvs;
    struct nostr_tlv *tlv;
    
    if (!parse_nostr_tlvs(cur, &tlvs))
        return 0;
    
    if (!find_tlv(&tlvs, TLV_SPECIAL, &tlv))
        return 0;
    
    if (tlv->len != 32)
        return 0;
    
    nevent->event_id = tlv->value;
    
    if (find_tlv(&tlvs, TLV_AUTHOR, &tlv)) {
        nevent->pubkey = tlv->value;
    } else {
        nevent->pubkey = NULL;
    }
    
    return tlvs_to_relays(&tlvs, &nevent->relays);
}

static int parse_nostr_bech32_naddr(struct cursor *cur, struct bech32_naddr *naddr) {
    struct nostr_tlvs tlvs;
    struct nostr_tlv *tlv;
    
    if (!parse_nostr_tlvs(cur, &tlvs))
        return 0;
    
    if (!find_tlv(&tlvs, TLV_SPECIAL, &tlv))
        return 0;
    
    naddr->identifier.start = (const char*)tlv->value;
    naddr->identifier.end = (const char*)tlv->value + tlv->len;
    
    if (!find_tlv(&tlvs, TLV_AUTHOR, &tlv))
        return 0;
    
    naddr->pubkey = tlv->value;
    
    return tlvs_to_relays(&tlvs, &naddr->relays);
}

static int parse_nostr_bech32_nprofile(struct cursor *cur, struct bech32_nprofile *nprofile) {
    struct nostr_tlvs tlvs;
    struct nostr_tlv *tlv;
    
    if (!parse_nostr_tlvs(cur, &tlvs))
        return 0;
    
    if (!find_tlv(&tlvs, TLV_SPECIAL, &tlv))
        return 0;
    
    if (tlv->len != 32)
        return 0;
    
    nprofile->pubkey = tlv->value;
    
    return tlvs_to_relays(&tlvs, &nprofile->relays);
}

static int parse_nostr_bech32_nrelay(struct cursor *cur, struct bech32_nrelay *nrelay) {
    struct nostr_tlvs tlvs;
    struct nostr_tlv *tlv;
    
    if (!parse_nostr_tlvs(cur, &tlvs))
        return 0;
    
    if (!find_tlv(&tlvs, TLV_SPECIAL, &tlv))
        return 0;
    
    nrelay->relay.start = (const char*)tlv->value;
    nrelay->relay.end = (const char*)tlv->value + tlv->len;
    
    return 1;
}

int parse_nostr_bech32(struct cursor *cur, struct nostr_bech32 *obj) {
    u8 *start, *end;
    
    start = cur->p;
    
    if (!consume_until_non_alphanumeric(cur, 1)) {
        cur->p = start;
        return 0;
    }
    
    end = cur->p;
    
    size_t data_len;
    size_t input_len = end - start;
    if (input_len < 10 || input_len > 10000) {
        return 0;
    }
    
    obj->buffer = malloc(input_len * 2);
    if (!obj->buffer)
        return 0;
    
    u8 data[input_len];
    char prefix[input_len];
    
    if (bech32_decode_len(prefix, data, &data_len, (const char*)start, input_len) == BECH32_ENCODING_NONE) {
        cur->p = start;
        return 0;
    }
    
    obj->buflen = 0;
    if (!bech32_convert_bits(obj->buffer, &obj->buflen, 8, data, data_len, 5, 0)) {
        goto fail;
    }
    
    if (!parse_nostr_bech32_type(prefix, &obj->type)) {
        goto fail;
    }
    
    struct cursor bcur;
    make_cursor(obj->buffer, obj->buffer + obj->buflen, &bcur);
    
    switch (obj->type) {
        case NOSTR_BECH32_NOTE:
            if (!parse_nostr_bech32_note(&bcur, &obj->data.note))
                goto fail;
            break;
        case NOSTR_BECH32_NPUB:
            if (!parse_nostr_bech32_npub(&bcur, &obj->data.npub))
                goto fail;
            break;
        case NOSTR_BECH32_NSEC:
            if (!parse_nostr_bech32_nsec(&bcur, &obj->data.nsec))
                goto fail;
            break;
        case NOSTR_BECH32_NEVENT:
            if (!parse_nostr_bech32_nevent(&bcur, &obj->data.nevent))
                goto fail;
            break;
        case NOSTR_BECH32_NADDR:
            if (!parse_nostr_bech32_naddr(&bcur, &obj->data.naddr))
                goto fail;
            break;
        case NOSTR_BECH32_NPROFILE:
            if (!parse_nostr_bech32_nprofile(&bcur, &obj->data.nprofile))
                goto fail;
            break;
        case NOSTR_BECH32_NRELAY:
            if (!parse_nostr_bech32_nrelay(&bcur, &obj->data.nrelay))
                goto fail;
            break;
    }
    
    return 1;

fail:
    free(obj->buffer);
    cur->p = start;
    return 0;
}
