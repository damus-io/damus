
#ifndef NDB_STR_BLOCK_H
#define NDB_STR_BLOCK_H

#include <inttypes.h>

struct ndb_str_block {
	const char *str;
	uint32_t len;
};

#endif
