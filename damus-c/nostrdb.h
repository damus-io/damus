#ifndef NOSTRDB_H
#define NOSTRDB_H

#include <inttypes.h>
#include "cursor.h"

// these must be byte-aligned, they are directly accessing the serialized data
// representation
#pragma pack(push, 1)

union packed_str {
	uint32_t offset;

	struct {
		char str[3];
		// we assume little endian everywhere. sorry not sorry.
		unsigned char flag;
	} packed;

	unsigned char bytes[4];
};

struct ndb_tag {
	uint16_t count;
	union packed_str strs[0];
};

struct ndb_tags {
	uint16_t count;
	struct ndb_tag tag[0];
};

// v1
struct ndb_note {
	unsigned char version;    // v=1
	unsigned char padding[3]; // keep things aligned
	unsigned char id[32];
	unsigned char pubkey[32];
	unsigned char signature[64];

	uint32_t created_at;
	uint32_t kind;
	union packed_str content;
	uint32_t strings;
	uint32_t json;

	// nothing can come after tags since it contains variadic data
	struct ndb_tags tags;
};

#pragma pack(pop)

struct ndb_builder {
	struct cursor note_cur;
	struct cursor strings;
	struct cursor str_indices;
	struct ndb_note *note;
	struct ndb_tag *current_tag;
};

struct ndb_iterator {
	struct ndb_note *note;
	struct ndb_tag *tag;

	// current outer index
	int index;
};

// HI BUILDER
int ndb_note_from_json(const char *json, int len, struct ndb_note **, unsigned char *buf, int buflen);
int ndb_builder_new(struct ndb_builder *builder, unsigned char *buf, int bufsize);
int ndb_builder_finalize(struct ndb_builder *builder, struct ndb_note **note);
int ndb_builder_set_content(struct ndb_builder *builder, const char *content, int len);
void ndb_builder_set_signature(struct ndb_builder *builder, unsigned char *signature);
void ndb_builder_set_pubkey(struct ndb_builder *builder, unsigned char *pubkey);
void ndb_builder_set_id(struct ndb_builder *builder, unsigned char *id);
void ndb_builder_set_kind(struct ndb_builder *builder, uint32_t kind);
int ndb_builder_new_tag(struct ndb_builder *builder);
int ndb_builder_push_tag_str(struct ndb_builder *builder, const char *str, int len);
// BYE BUILDER

static inline int ndb_str_is_packed(union packed_str str)
{
	return (str.offset >> 31) & 0x1;
}

static inline const char * ndb_note_str(struct ndb_note *note,
					union packed_str *str)
{
	if (ndb_str_is_packed(*str))
		return str->packed.str;

	return ((const char *)note) + note->strings + str->offset;
}

static inline const char * ndb_tag_str(struct ndb_note *note,
				       struct ndb_tag *tag, int ind)
{
	return ndb_note_str(note, &tag->strs[ind]);
}

static inline int ndb_tag_matches_char(struct ndb_note *note,
				       struct ndb_tag *tag, int ind, char c)
{
	const char *str = ndb_tag_str(note, tag, ind);
	if (str[0] == '\0')
		return 0;
	else if (str[0] == c)
		return 1;
	return 0;
}

static inline const char * ndb_iter_tag_str(struct ndb_iterator *iter,
					    int ind)
{
	return ndb_tag_str(iter->note, iter->tag, ind);
}

static inline unsigned char * ndb_note_id(struct ndb_note *note)
{
	return note->id;
}

static inline unsigned char * ndb_note_pubkey(struct ndb_note *note)
{
	return note->pubkey;
}

static inline unsigned char * ndb_note_signature(struct ndb_note *note)
{
	return note->signature;
}

static inline uint32_t ndb_note_created_at(struct ndb_note *note)
{
	return note->created_at;
}

static inline const char * ndb_note_content(struct ndb_note *note)
{
	return ndb_note_str(note, &note->content);
}

static inline struct ndb_note * ndb_note_from_bytes(unsigned char *bytes)
{
	struct ndb_note *note = (struct ndb_note *)bytes;
	if (note->version != 1)
		return 0;
	return note;
}

static inline union packed_str ndb_offset_str(uint32_t offset)
{
	// ensure accidents like -1 don't corrupt our packed_str
	union packed_str str;
	str.offset = offset & 0x7FFFFFFF;
	return str;
}

static inline union packed_str ndb_char_to_packed_str(char c)
{
	union packed_str str;
	str.packed.flag = 0xFF;
	str.packed.str[0] = c;
	str.packed.str[1] = '\0';
	return str;
}

static inline union packed_str ndb_chars_to_packed_str(char c1, char c2)
{
	union packed_str str;
	str.packed.flag = 0xFF;
	str.packed.str[0] = c1;
	str.packed.str[1] = c2;
	str.packed.str[2] = '\0';
	return str;
}

static inline const char * ndb_note_tag_index(struct ndb_note *note,
					      struct ndb_tag *tag, int index)
{
	if (index >= tag->count) {
		return 0;
	}

	return ndb_note_str(note, &tag->strs[index]);
}

static inline int ndb_tags_iterate_start(struct ndb_note *note,
					 struct ndb_iterator *iter)
{
	iter->note = note;
	iter->tag = note->tags.tag;
	iter->index = 0;

	return note->tags.count != 0 && iter->tag->count != 0;
}

static inline int ndb_tags_iterate_next(struct ndb_iterator *iter)
{
	struct ndb_tags *tags = &iter->note->tags;

	if (++iter->index < tags->count) {
		uint32_t tag_data_size = iter->tag->count * sizeof(iter->tag->strs[0]);
		iter->tag = (struct ndb_tag *)(iter->tag->strs[0].bytes + tag_data_size);
		return 1;
	}

	return 0;
}

#endif
