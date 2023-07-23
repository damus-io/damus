
#include "nostrdb.h"
#include "jsmn.h"
#include "hex.h"
#include "cursor.h"
#include <stdlib.h>
#include <limits.h>

struct ndb_json_parser {
	const char *json;
	int json_len;
	struct ndb_builder builder;
	jsmn_parser json_parser;
	jsmntok_t *toks, *toks_end;
	int num_tokens;
};

static inline int cursor_push_tag(struct cursor *cur, struct ndb_tag *tag)
{
	return cursor_push_u16(cur, tag->count);
}

int ndb_builder_new(struct ndb_builder *builder, unsigned char *buf,
		    int bufsize)
{
	struct ndb_note *note;
	struct cursor mem;
	int half, size, str_indices_size;

	// come on bruh
	if (bufsize < sizeof(struct ndb_note) * 2)
		return 0;

	str_indices_size = bufsize / 32;
	size = bufsize - str_indices_size;
	half = size / 2;

	//debug("size %d half %d str_indices %d\n", size, half, str_indices_size);

	// make a safe cursor of our available memory
	make_cursor(buf, buf + bufsize, &mem);

	note = builder->note = (struct ndb_note *)buf;

	// take slices of the memory into subcursors
	if (!(cursor_slice(&mem, &builder->note_cur, half) &&
	      cursor_slice(&mem, &builder->strings, half) &&
	      cursor_slice(&mem, &builder->str_indices, str_indices_size))) {
		return 0;
	}

	memset(note, 0, sizeof(*note));
	builder->note_cur.p += sizeof(*note);

	note->version = 1;

	return 1;
}



static inline int ndb_json_parser_init(struct ndb_json_parser *p,
				       const char *json, int json_len,
				       unsigned char *buf, int bufsize)
{
	int half = bufsize / 2;

	unsigned char *tok_start = buf + half;
	unsigned char *tok_end = buf + bufsize;

	p->toks = (jsmntok_t*)tok_start;
	p->toks_end = (jsmntok_t*)tok_end;
	p->num_tokens = 0;
	p->json = json;
	p->json_len = json_len;

	// ndb_builder gets the first half of the buffer, and jsmn gets the
	// second half. I like this way of alloating memory (without actually
	// dynamically allocating memory). You get one big chunk upfront and
	// then submodules can recursively subdivide it. Maybe you could do
	// something even more clever like golden-ratio style subdivision where
	// the more important stuff gets a larger chunk and then it spirals
	// downward into smaller chunks. Thanks for coming to my TED talk.

	if (!ndb_builder_new(&p->builder, buf, half))
		return 0;

	jsmn_init(&p->json_parser);

	return 1;
}

static inline int ndb_json_parser_parse(struct ndb_json_parser *p)
{
	int cap = ((unsigned char *)p->toks_end - (unsigned char*)p->toks)/sizeof(*p->toks);
	p->num_tokens =
		jsmn_parse(&p->json_parser, p->json, p->json_len, p->toks, cap);

	return p->num_tokens;
}

int ndb_builder_finalize(struct ndb_builder *builder, struct ndb_note **note)
{
	int strings_len = builder->strings.p - builder->strings.start;
	unsigned char *end = builder->note_cur.p + strings_len;
	int total_size = end - builder->note_cur.start;

	// move the strings buffer next to the end of our ndb_note
	memmove(builder->note_cur.p, builder->strings.start, strings_len);

	// set the strings location
	builder->note->strings = builder->note_cur.p - builder->note_cur.start;

	// record the total size
	//builder->note->size = total_size;

	*note = builder->note;

	return total_size;
}

struct ndb_note * ndb_builder_note(struct ndb_builder *builder)
{
	return builder->note;
}

/// find an existing string via str_indices. these indices only exist in the
/// builder phase just for this purpose.
static inline int ndb_builder_find_str(struct ndb_builder *builder,
				       const char *str, int len,
				       union ndb_packed_str *pstr)
{
	// find existing matching string to avoid duplicate strings
	int indices = cursor_count(&builder->str_indices, sizeof(uint32_t));
	for (int i = 0; i < indices; i++) {
		uint32_t index = ((uint32_t*)builder->str_indices.start)[i];
		const char *some_str = (const char*)builder->strings.start + index;

		if (!memcmp(some_str, str, len)) {
			// found an existing matching str, use that index
			*pstr = ndb_offset_str(index);
			return 1;
		}
	}

	return 0;
}

static int ndb_builder_push_str(struct ndb_builder *builder, const char *str,
				int len, union ndb_packed_str *pstr)
{
	uint32_t loc;

	// no string found, push a new one
	loc = builder->strings.p - builder->strings.start;
	if (!(cursor_push(&builder->strings, (unsigned char*)str, len) &&
	      cursor_push_byte(&builder->strings, '\0'))) {
		return 0;
	}

	*pstr = ndb_offset_str(loc);

	// record in builder indices. ignore return value, if we can't cache it
	// then whatever
	cursor_push_u32(&builder->str_indices, loc);

	return 1;
}

static int ndb_builder_push_packed_id(struct ndb_builder *builder,
				      unsigned char *id,
				      union ndb_packed_str *pstr)
{
	// Don't both find id duplicates. very rarely are they duplicated
	// and it slows things down quite a bit. If we really care about this
	// We can switch to a hash table.
	//if (ndb_builder_find_str(builder, (const char*)id, 32, pstr)) {
	//	pstr->packed.flag = NDB_PACKED_ID;
	//	return 1;
	//}

	if (ndb_builder_push_str(builder, (const char*)id, 32, pstr)) {
		pstr->packed.flag = NDB_PACKED_ID;
		return 1;
	}

	return 0;
}


/// Check for small strings to pack
static inline int ndb_builder_try_compact_str(struct ndb_builder *builder,
					      const char *str, int len,
					      union ndb_packed_str *pstr,
					      int pack_ids)
{
	unsigned char id_buf[32];

	if (len == 0) {
		*pstr = ndb_char_to_packed_str(0);
		return 1;
	} else if (len == 1) {
		*pstr = ndb_char_to_packed_str(str[0]);
		return 1;
	} else if (len == 2) {
		*pstr = ndb_chars_to_packed_str(str[0], str[1]);
		return 1;
	} else if (pack_ids && len == 64 && hex_decode(str, 64, id_buf, 32)) {
		return ndb_builder_push_packed_id(builder, id_buf, pstr);
	}

	return 0;
}


static int ndb_builder_push_unpacked_str(struct ndb_builder *builder,
					 const char *str, int len,
					 union ndb_packed_str *pstr)
{
	if (ndb_builder_find_str(builder, str, len, pstr))
		return 1;

	return ndb_builder_push_str(builder, str, len, pstr);
}

int ndb_builder_make_str(struct ndb_builder *builder, const char *str, int len,
			 union ndb_packed_str *pstr, int pack_ids)
{
	if (ndb_builder_try_compact_str(builder, str, len, pstr, pack_ids))
		return 1;

	return ndb_builder_push_unpacked_str(builder, str, len, pstr);
}

int ndb_builder_set_content(struct ndb_builder *builder, const char *content,
			    int len)
{
	int pack_ids = 0;
	builder->note->content_length = len;
	return ndb_builder_make_str(builder, content, len,
				    &builder->note->content, pack_ids);
}


static inline int jsoneq(const char *json, jsmntok_t *tok, int tok_len,
			 const char *s)
{
	if (tok->type == JSMN_STRING && (int)strlen(s) == tok_len &&
	    memcmp(json + tok->start, s, tok_len) == 0) {
		return 1;
	}
	return 0;
}

static inline int toksize(jsmntok_t *tok)
{
	return tok->end - tok->start;
}

static int ndb_builder_finalize_tag(struct ndb_builder *builder,
				    union ndb_packed_str offset)
{
	if (!cursor_push_u32(&builder->note_cur, offset.offset))
		return 0;
	builder->current_tag->count++;
	return 1;
}

/// Unescape and push json strings
static int ndb_builder_make_json_str(struct ndb_builder *builder,
				     const char *str, int len,
				     union ndb_packed_str *pstr,
				     int *written, int pack_ids)
{
	// let's not care about de-duping these. we should just unescape
	// in-place directly into the strings table. 

	const char *p, *end, *start;
	unsigned char *builder_start;

	// always try compact strings first
	if (ndb_builder_try_compact_str(builder, str, len, pstr, pack_ids))
		return 1;

	end = str + len;
	start = str; // Initialize start to the beginning of the string

	*pstr = ndb_offset_str(builder->strings.p - builder->strings.start);
	builder_start = builder->strings.p;

	for (p = str; p < end; p++) {
		if (*p == '\\' && p+1 < end) {
			// Push the chunk of unescaped characters before this escape sequence
			if (start < p && !cursor_push(&builder->strings,
						(unsigned char *)start,
						p - start)) {
				return 0;
			}

			switch (*(p+1)) {
			case 't':
				if (!cursor_push_byte(&builder->strings, '\t'))
					return 0;
				break;
			case 'n':
				if (!cursor_push_byte(&builder->strings, '\n'))
					return 0;
				break;
			case 'r':
				if (!cursor_push_byte(&builder->strings, '\r'))
					return 0;
				break;
			case 'b':
				if (!cursor_push_byte(&builder->strings, '\b'))
					return 0;
				break;
			case 'f':
				if (!cursor_push_byte(&builder->strings, '\f'))
					return 0;
				break;
			case '\\':
				if (!cursor_push_byte(&builder->strings, '\\'))
					return 0;
				break;
			case '"':
				if (!cursor_push_byte(&builder->strings, '"'))
					return 0;
				break;
			case 'u':
				// these aren't handled yet
				return 0;
			default:
				if (!cursor_push_byte(&builder->strings, *p) ||
				    !cursor_push_byte(&builder->strings, *(p+1)))
					return 0;
				break;
			}

			p++; // Skip the character following the backslash
			start = p + 1; // Update the start pointer to the next character
		}
	}

	// Handle the last chunk after the last escape sequence (or if there are no escape sequences at all)
	if (start < p && !cursor_push(&builder->strings, (unsigned char *)start,
				      p - start)) {
		return 0;
	}

	if (written)
		*written = builder->strings.p - builder_start;

	// TODO: dedupe these!?
	return cursor_push_byte(&builder->strings, '\0');
}

static int ndb_builder_push_json_tag(struct ndb_builder *builder,
				     const char *str, int len)
{
	union ndb_packed_str pstr;
	int pack_ids = 1;
	if (!ndb_builder_make_json_str(builder, str, len, &pstr, NULL, pack_ids))
		return 0;
	return ndb_builder_finalize_tag(builder, pstr);
}

// Push a json array into an ndb tag ["p", "abcd..."] -> struct ndb_tag
static int ndb_builder_tag_from_json_array(struct ndb_json_parser *p,
					   jsmntok_t *array)
{
	jsmntok_t *str_tok;
	const char *str;

	if (array->size == 0)
		return 0;

	if (!ndb_builder_new_tag(&p->builder))
		return 0;

	for (int i = 0; i < array->size; i++) {
		str_tok = &array[i+1];
		str = p->json + str_tok->start;

		if (!ndb_builder_push_json_tag(&p->builder, str,
					       toksize(str_tok))) {
			return 0;
		}
	}

	return 1;
}

// Push json tags into ndb data
//   [["t", "hashtag"], ["p", "abcde..."]] -> struct ndb_tags
static inline int ndb_builder_process_json_tags(struct ndb_json_parser *p,
						jsmntok_t *array)
{
	jsmntok_t *tag = array;

	if (array->size == 0)
		return 1;

	for (int i = 0; i < array->size; i++) {
		if (!ndb_builder_tag_from_json_array(p, &tag[i+1]))
			return 0;
		tag += tag[i+1].size;
	}

	return 1;
}

static int parse_unsigned_int(const char *start, int len, unsigned int *num)
{
	unsigned int number = 0;
	const char *p = start, *end = start + len;
	int digits = 0;

	while (p < end) {
		char c = *p;

		if (c < '0' || c > '9')
			break;

		// Check for overflow
		char digit = c - '0';
		if (number > (UINT_MAX - digit) / 10)
			return 0; // Overflow detected

		number = number * 10 + digit;

		p++;
		digits++;
	}

	if (digits == 0)
		return 0;

	*num = number;
	return 1;
}


int ndb_note_from_json(const char *json, int len, struct ndb_note **note,
		       unsigned char *buf, int bufsize)
{
	jsmntok_t *tok = NULL;
	unsigned char hexbuf[64];

	int i, tok_len, res;
	const char *start;
	struct ndb_json_parser parser;

	ndb_json_parser_init(&parser, json, len, buf, bufsize);
	res = ndb_json_parser_parse(&parser);
	if (res < 0)
		return res;

	if (parser.num_tokens < 1 || parser.toks[0].type != JSMN_OBJECT)
		return 0;

	for (i = 1; i < parser.num_tokens; i++) {
		tok = &parser.toks[i];
		start = json + tok->start;
		tok_len = toksize(tok);

		//printf("toplevel %.*s %d\n", tok_len, json + tok->start, tok->type);
		if (tok_len == 0 || i + 1 >= parser.num_tokens)
			continue;

		if (start[0] == 'p' && jsoneq(json, tok, tok_len, "pubkey")) {
			// pubkey
			tok = &parser.toks[i+1];
			hex_decode(json + tok->start, toksize(tok), hexbuf, sizeof(hexbuf));
			ndb_builder_set_pubkey(&parser.builder, hexbuf);
		} else if (tok_len == 2 && start[0] == 'i' && start[1] == 'd') {
			// id
			tok = &parser.toks[i+1];
			hex_decode(json + tok->start, toksize(tok), hexbuf, sizeof(hexbuf));
			// TODO: validate id
			ndb_builder_set_id(&parser.builder, hexbuf);
		} else if (tok_len == 3 && start[0] == 's' && start[1] == 'i' && start[2] == 'g') {
			// sig
			tok = &parser.toks[i+1];
			hex_decode(json + tok->start, toksize(tok), hexbuf, sizeof(hexbuf));
			ndb_builder_set_signature(&parser.builder, hexbuf);
		} else if (start[0] == 'k' && jsoneq(json, tok, tok_len, "kind")) {
			// kind
			tok = &parser.toks[i+1];
			start = json + tok->start;
			if (tok->type != JSMN_PRIMITIVE || tok_len <= 0)
				return 0;
			if (!parse_unsigned_int(start, toksize(tok),
						&parser.builder.note->kind))
					return 0;
		} else if (start[0] == 'c') {
			if (jsoneq(json, tok, tok_len, "created_at")) {
				// created_at
				tok = &parser.toks[i+1];
				start = json + tok->start;
				if (tok->type != JSMN_PRIMITIVE || tok_len <= 0)
					return 0;
				if (!parse_unsigned_int(start, toksize(tok),
							&parser.builder.note->created_at))
					return 0;
			} else if (jsoneq(json, tok, tok_len, "content")) {
				// content
				tok = &parser.toks[i+1];
				union ndb_packed_str pstr;
				tok_len = toksize(tok);
				int written, pack_ids = 0;
				if (!ndb_builder_make_json_str(&parser.builder,
							json + tok->start,
							tok_len, &pstr,
							&written, pack_ids)) {
					return 0;
				}
				parser.builder.note->content_length = written;
				parser.builder.note->content = pstr;
			}
		} else if (start[0] == 't' && jsoneq(json, tok, tok_len, "tags")) {
			tok = &parser.toks[i+1];
			ndb_builder_process_json_tags(&parser, tok);
			i += tok->size;
		}
	}

	return ndb_builder_finalize(&parser.builder, note);
}

void ndb_builder_set_pubkey(struct ndb_builder *builder, unsigned char *pubkey)
{
	memcpy(builder->note->pubkey, pubkey, 32);
}

void ndb_builder_set_id(struct ndb_builder *builder, unsigned char *id)
{
	memcpy(builder->note->id, id, 32);
}

void ndb_builder_set_signature(struct ndb_builder *builder,
			       unsigned char *signature)
{
	memcpy(builder->note->signature, signature, 64);
}

void ndb_builder_set_kind(struct ndb_builder *builder, uint32_t kind)
{
	builder->note->kind = kind;
}

int ndb_builder_new_tag(struct ndb_builder *builder)
{
	builder->note->tags.count++;
	struct ndb_tag tag = {0};
	builder->current_tag = (struct ndb_tag *)builder->note_cur.p;
	return cursor_push_tag(&builder->note_cur, &tag);
}

/// Push an element to the current tag
/// 
/// Basic idea is to call ndb_builder_new_tag
inline int ndb_builder_push_tag_str(struct ndb_builder *builder,
				    const char *str, int len)
{
	union ndb_packed_str pstr;
	int pack_ids = 1;
	if (!ndb_builder_make_str(builder, str, len, &pstr, pack_ids))
		return 0;
	return ndb_builder_finalize_tag(builder, pstr);
}
