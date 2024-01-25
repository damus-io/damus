
#ifndef PROTOVERSE_VARINT_H
#define PROTOVERSE_VARINT_H

#define VARINT_MAX_LEN 9

#include <stddef.h>
#include <stdint.h>

size_t varint_put(unsigned char buf[VARINT_MAX_LEN], uint64_t v);
size_t varint_size(uint64_t v);
size_t varint_get(const unsigned char *p, size_t max, int64_t *val);

#endif /* PROTOVERSE_VARINT_H */
