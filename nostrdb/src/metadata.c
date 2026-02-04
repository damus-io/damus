
#include "nostrdb.h"
#include "binmoji.h"
#include "metadata.h"

int ndb_reaction_str_is_emoji(union ndb_reaction_str str) 
{
	return binmoji_get_user_flag(str.binmoji) == 0;
}

uint16_t ndb_note_meta_entries_count(struct ndb_note_meta *meta)
{
	return meta->count;
}

static int ndb_reaction_set_emoji(union ndb_reaction_str *str, const char *emoji)
{
	struct binmoji binmoji;
	/* TODO: parse failures? */
	binmoji_parse(emoji, &binmoji);
	str->binmoji = binmoji_encode(&binmoji);
	return 1;
}

static int ndb_reaction_set_str(union ndb_reaction_str *reaction, const char *str) 
{
	int i;
	char c;

	/* this is like memset'ing the packed string to all 0s as well */
	reaction->binmoji = 0;
	
	/* set the binmoji user flag so we can catch corrupt binmojis */
	/* this is in the LSB so it will only touch reaction->packed.flag  */
	reaction->binmoji = binmoji_set_user_flag(reaction->binmoji, 1);
	assert(reaction->packed.flag != 0);

	for (i = 0; i < 7; i++) {
		c = str[i];
		/* string is too big */
		if (i == 6 && c != '\0')
			return 0;
		reaction->packed.str[i] = c;
		if (c == '\0')
			return 1;
	}

	return 0;
}

const char *ndb_reaction_to_str(union ndb_reaction_str *str, char buf[128])
{
	struct binmoji binmoji;

	if (ndb_reaction_str_is_emoji(*str)) {
		binmoji_decode(str->binmoji, &binmoji);
		binmoji_to_string(&binmoji, buf, 128);
		return (const char *)buf;
	} else {
		return (const char *)str->packed.str;
	}
}

/* set the value of an ndb_reaction_str to an emoji or small string */
int ndb_reaction_set(union ndb_reaction_str *reaction, const char *str)
{
	struct binmoji binmoji;
	char output_emoji[136];

	/* our variant of emoji detection is to simply try to create
	 * a binmoji and parse it again. if we round-trip successfully
	 * then we know its an emoji, or at least a simple string
	 */
	binmoji_parse(str, &binmoji);
	reaction->binmoji = binmoji_encode(&binmoji);
	binmoji_to_string(&binmoji, output_emoji, sizeof(output_emoji));

	/* round trip is successful, let's just use binmojis for this encoding */
	if (!strcmp(output_emoji, str))
		return 1;

	/* no round trip? let's just set a non-emoji string */
	return ndb_reaction_set_str(reaction, str);
}

void ndb_note_meta_header_init(struct ndb_note_meta *meta)
{
	meta->version = 1;
	meta->flags = 0;
	meta->count = 0;
	meta->data_table_size = 0;
}

static inline size_t ndb_note_meta_entries_size(struct ndb_note_meta *meta)
{
	return (sizeof(struct ndb_note_meta_entry) * meta->count);
}

void *ndb_note_meta_data_table(struct ndb_note_meta *meta, size_t *size)
{
	return meta + ndb_note_meta_entries_size(meta);
}

size_t ndb_note_meta_total_size(struct ndb_note_meta *header)
{
	size_t total_size = sizeof(*header) + header->data_table_size + ndb_note_meta_entries_size(header);
	assert((total_size % 8) == 0);
	return total_size;
}

struct ndb_note_meta_entry *ndb_note_meta_add_entry(struct ndb_note_meta_builder *builder)
{
	struct ndb_note_meta *header = (struct ndb_note_meta *)builder->cursor.start;
	struct ndb_note_meta_entry *entry = NULL;

	assert(builder->cursor.p != builder->cursor.start);

	if (!(entry = cursor_malloc(&builder->cursor, sizeof(*entry))))
		return NULL;

	/* increase count entry count */
	header->count++;

	return entry;
}

void ndb_note_meta_builder_resized(struct ndb_note_meta_builder *builder, unsigned char *buf, size_t bufsize)
{
	make_cursor(buf, buf + bufsize, &builder->cursor);
}

int ndb_note_meta_builder_init(struct ndb_note_meta_builder *builder, unsigned char *buf, size_t bufsize)
{
	ndb_note_meta_builder_resized(builder, buf, bufsize);

	/* allocate some space for the header */
	if (!cursor_malloc(&builder->cursor, sizeof(struct ndb_note_meta)))
		return 0;

	ndb_note_meta_header_init((struct ndb_note_meta*)builder->cursor.start);

	return 1;
}

/* note flags are stored in the header entry */
uint64_t *ndb_note_meta_flags(struct ndb_note_meta *meta)
{
	return &meta->flags;
}

/* note flags are stored in the header entry */
void ndb_note_meta_set_flags(struct ndb_note_meta *meta, uint32_t flags)
{
	meta->flags = flags;
}

static int compare_entries(const void *a, const void *b)
{
	struct ndb_note_meta_entry *entry_a, *entry_b;
	uint64_t binmoji_a, binmoji_b;
	int res;

	entry_a = (struct ndb_note_meta_entry *)a;
	entry_b = (struct ndb_note_meta_entry *)b;

	res = entry_a->type - entry_b->type;

	if (res == 0 && entry_a->type == NDB_NOTE_META_REACTION) {
		/* we sort by reaction string for stability */
		binmoji_a = entry_a->payload.reaction_str.binmoji;
		binmoji_b = entry_b->payload.reaction_str.binmoji;

		if (binmoji_a < binmoji_b) {
			return -1;
		} else if (binmoji_a > binmoji_b) {
			return 1;
		} else {
			return 0;
		}
	} else {
		return res;
	}
}

struct ndb_note_meta_entry *ndb_note_meta_entries(struct ndb_note_meta *meta)
{
	/* entries start at the end of the header record */
	return (struct ndb_note_meta_entry *)((unsigned char*)meta + sizeof(*meta));
}

struct ndb_note_meta_entry *ndb_note_meta_entry_at(struct ndb_note_meta *meta, int i)
{
	if (i >= ndb_note_meta_entries_count(meta))
		return NULL;

	return &ndb_note_meta_entries(meta)[i];
}
void ndb_note_meta_build(struct ndb_note_meta_builder *builder, struct ndb_note_meta **meta)
{
	/* sort entries */
	struct ndb_note_meta_entry *entries;
	struct ndb_note_meta *header = (struct ndb_note_meta*)builder->cursor.start;

	/* not initialized */
	assert(builder->cursor.start != builder->cursor.p);

	if (header->count > 1) {
		entries = ndb_note_meta_entries(header);
		/*assert(entries);*/

		/* ensure entries are always sorted so bsearch is possible for large metadata
		 * entries. probably won't need that for awhile though */

		/* this also ensures our counts entry is near the front, which will be a very
		 * hot and common entry to hit */
		qsort(entries, header->count, sizeof(struct ndb_note_meta_entry), compare_entries);
	}

	*meta = header;
	return;
}

uint16_t *ndb_note_meta_entry_type(struct ndb_note_meta_entry *entry)
{
	return &entry->type;
}

/* find a metadata entry, optionally matching a payload */
static struct ndb_note_meta_entry *ndb_note_meta_find_entry_impl(struct ndb_note_meta *meta, uint16_t type, uint64_t *payload, int sorted)
{
	struct ndb_note_meta_entry *entries, *entry;
	int i;

	if (meta->count == 0)
		return NULL;

	entries = ndb_note_meta_entries(meta);
	assert(((intptr_t)entries - (intptr_t)meta) == 16);

	/* TODO(jb55): do bsearch for large sorted entries */

	for (i = 0; i < meta->count; i++) {
		entry = &entries[i];
		assert(((uintptr_t)entry % 8) == 0);
		/*
		assert(entry->type < 100);
		printf("finding %d/%d q:%d q:%"PRIx64" entry_type:%d entry:%"PRIx64"\n",
			i+1, (int)meta->count, type, payload ? *payload : 0, entry->type, entry->payload.value);
			*/
		if (entry->type != type)
			continue;
		if (payload && (*payload != entry->payload.value))
			continue;
		return entry;
	}

	return NULL;
}

struct ndb_note_meta_entry *ndb_note_meta_find_entry(struct ndb_note_meta *meta, uint16_t type, uint64_t *payload)
{
	int sorted = 1;
	return ndb_note_meta_find_entry_impl(meta, type, payload, sorted);
}

struct ndb_note_meta_entry *ndb_note_meta_builder_find_entry(
		struct ndb_note_meta_builder *builder,
		uint16_t type,
		uint64_t *payload)
{
	/* meta building in progress is not necessarily sorted */
	int sorted = 0;
	return ndb_note_meta_find_entry_impl((struct ndb_note_meta *)builder->cursor.start, type, payload, sorted);
}

void ndb_note_meta_reaction_set(struct ndb_note_meta_entry *entry, uint32_t count, union ndb_reaction_str str)
{
	entry->type = NDB_NOTE_META_REACTION;
	entry->aux2.flags = 0;
	entry->aux.value = count;
	entry->payload.reaction_str = str;
}

/* sets the quote repost count for this note */
void ndb_note_meta_counts_set(struct ndb_note_meta_entry *entry,
		uint32_t total_reactions,
		uint16_t quotes,
		uint16_t direct_replies,
		uint32_t thread_replies,
		uint16_t reposts)
{
	entry->type = NDB_NOTE_META_COUNTS;
	entry->aux.total_reactions = total_reactions;
	entry->aux2.reposts = reposts;
	entry->payload.counts.quotes = quotes;
	entry->payload.counts.direct_replies = direct_replies;
	entry->payload.counts.thread_replies = thread_replies;
}

/* clones a metadata, either adding a new entry of a specific type, or returing
 * a reference to it
 *
 * [in/out] meta:  pointer to an existing meta entry, can but overwritten to
 * [out]    entry: pointer to the added entry
 *
 * */
enum ndb_meta_clone_result ndb_note_meta_clone_with_entry(
		struct ndb_note_meta **meta,
		struct ndb_note_meta_entry **entry,
		uint16_t type,
		uint64_t *payload,
		unsigned char *buf,
		size_t bufsize)
{
	size_t size, offset;
	struct ndb_note_meta_builder builder;

	if (*meta == NULL) {
		ndb_note_meta_builder_init(&builder, buf, bufsize);
		*entry = ndb_note_meta_add_entry(&builder);
		*meta = (struct ndb_note_meta*)buf;

		assert(*entry);

		ndb_note_meta_build(&builder, meta);
		return NDB_META_CLONE_NEW_ENTRY;
	} else if ((size = ndb_note_meta_total_size(*meta)) > bufsize) {
		ndb_debug("buf size too small (%ld < %ld) for metadata entry\n", bufsize, size);
		goto fail;
	} else if ((*entry = ndb_note_meta_find_entry(*meta, type, payload))) {
		offset = (unsigned char *)(*entry) - (unsigned char *)(*meta);

		/* we have an existing entry. simply memcpy and return the new entry position */
		assert(offset < size);
		assert((offset % 16) == 0);
		assert(((uintptr_t)buf % 8) == 0);

		memcpy(buf, *meta, size);
		*meta = (struct ndb_note_meta*)buf;
		*entry = (struct ndb_note_meta_entry*)(((unsigned char *)(*meta)) + offset);
		return NDB_META_CLONE_EXISTING_ENTRY;
	} else if (size + sizeof(*entry) > bufsize) {
		/* if we don't have an existing entry, make sure we have room to add one */

		ndb_debug("note metadata is too big (%d > %d) to clone with entry\n",
			  (int)(size + sizeof(*entry)), (int)bufsize);
		/* no room. this is bad, if this happens we should fix it */
		goto fail;
	} else {
		/* we need to add a new entry */
		ndb_note_meta_builder_init(&builder, buf, bufsize);

		memcpy(buf, *meta, size);
		builder.cursor.p = buf + size;

		*entry = ndb_note_meta_add_entry(&builder);
		assert(*entry);
		(*entry)->type = type;
		(*entry)->payload.value = payload? *payload : 0;

		*meta = (struct ndb_note_meta*)buf;

		assert(*entry);
		assert(*meta);

		ndb_note_meta_build(&builder, meta);

		/* we re-find here since it could have been sorted */
		*entry = ndb_note_meta_find_entry(*meta, type, payload);
		assert(*entry);
		assert(*ndb_note_meta_entry_type(*entry) == type);

		return NDB_META_CLONE_NEW_ENTRY;
	}

	assert(!"should be impossible to get here");
fail:
	*entry = NULL;
	*meta = NULL;
	return 0;
}

uint32_t *ndb_note_meta_reaction_count(struct ndb_note_meta_entry *entry)
{
	return &entry->aux.value;
}

uint16_t *ndb_note_meta_counts_direct_replies(struct ndb_note_meta_entry *entry)
{
	return &entry->payload.counts.direct_replies;
}

uint32_t *ndb_note_meta_counts_total_reactions(struct ndb_note_meta_entry *entry)
{
	return &entry->aux.total_reactions;
}

uint32_t *ndb_note_meta_counts_thread_replies(struct ndb_note_meta_entry *entry)
{
	return &entry->payload.counts.thread_replies;
}

uint16_t *ndb_note_meta_counts_quotes(struct ndb_note_meta_entry *entry)
{
	return &entry->payload.counts.quotes;
}

uint16_t *ndb_note_meta_counts_reposts(struct ndb_note_meta_entry *entry)
{
	return &entry->aux2.reposts;
}

void ndb_note_meta_reaction_set_count(struct ndb_note_meta_entry *entry, uint32_t count)
{
	entry->aux.value = count;
}

union ndb_reaction_str *ndb_note_meta_reaction_str(struct ndb_note_meta_entry *entry)
{
	return &entry->payload.reaction_str;
}

void print_note_meta(struct ndb_note_meta *meta)
{
	int count, i;
	struct ndb_note_meta_entry *entries, *entry;
	char strbuf[128];

	count = ndb_note_meta_entries_count(meta);
	entries = ndb_note_meta_entries(meta);

	for (i = 0; i < count; i++) {
		entry = &entries[i];
		switch (entry->type) {
		case NDB_NOTE_META_REACTION:
			ndb_reaction_to_str(ndb_note_meta_reaction_str(entry), strbuf);
			printf("%s%d ", strbuf, *ndb_note_meta_reaction_count(entry));
			break;
		case NDB_NOTE_META_COUNTS:
			printf("reposts %d\tquotes %d\treplies %d\tall_replies %d\treactions %d\t",
					*ndb_note_meta_counts_reposts(entry),
					*ndb_note_meta_counts_quotes(entry),
					*ndb_note_meta_counts_direct_replies(entry),
					*ndb_note_meta_counts_thread_replies(entry),
					*ndb_note_meta_counts_total_reactions(entry));
			break;
		}
	}

	printf("\n");
}
