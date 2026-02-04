#ifndef NDB_METADATA_H
#define NDB_METADATA_H

#include "nostrdb.h"

enum ndb_meta_clone_result {
	NDB_META_CLONE_FAILED,
	NDB_META_CLONE_EXISTING_ENTRY,
	NDB_META_CLONE_NEW_ENTRY,
};

enum ndb_meta_clone_result ndb_note_meta_clone_with_entry(
		struct ndb_note_meta **meta,
		struct ndb_note_meta_entry **entry,
		uint16_t type,
		uint64_t *payload,
		unsigned char *buf,
		size_t bufsize);

// these must be byte-aligned, they are directly accessing the serialized data
// representation
#pragma pack(push, 1)

// 16 bytes
struct ndb_note_meta_entry {
	// 4 byte entry header
	uint16_t type;

	union {
		uint16_t flags;
		uint16_t reposts;
	} aux2;

	// additional 4 bytes of aux storage for payloads that are >8 bytes
	//
	// for reactions types, this is used for counts
	// normally this would have been padding but we make use of it
	// in our manually packed structure
	union {
		uint32_t value;

		/* if this is a thread root, this counts the total replies in the thread */
		uint32_t total_reactions;
	} aux;

	// 8 byte metadata payload
	union {
		uint64_t value;

		struct {
			uint32_t offset;
			uint32_t padding;
		} offset;

		struct {
			/* number of direct replies */
			uint16_t direct_replies;
			uint16_t quotes;

			/* number of replies in this thread */
			uint32_t thread_replies;
		} counts;

		// the reaction binmoji[1] for reaction, count is stored in aux
		union ndb_reaction_str reaction_str;
	} payload;
};
STATIC_ASSERT(sizeof(struct ndb_note_meta_entry) == 16, note_meta_entry_should_be_16_bytes);

struct ndb_note_meta {
	// 4 bytes
	uint8_t version;
	uint8_t padding;
	uint16_t count;

	// 4 bytes
	uint32_t data_table_size;

	// 8 bytes
	uint64_t flags;
};
STATIC_ASSERT(sizeof(struct ndb_note_meta) == 16, note_meta_entry_should_be_16_bytes);

#pragma pack(pop)

enum ndb_note_meta_flags {
	NDB_NOTE_META_FLAG_DELETED = 0,
	NDB_NOTE_META_FLAG_SEEN    = 2,
};

#endif /* NDB_METADATA_H */
