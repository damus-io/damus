
#ifndef NDB_UTIL_H
#define NDB_UTIL_H

static inline void* memdup(const void* src, size_t size) {
	void* dest = malloc(size);
	if (dest == NULL) {
		return NULL;  // Memory allocation failed
	}
	memcpy(dest, src, size);
	return dest;
}

static inline char *strdupn(const char *src, size_t size) {
	char* dest = malloc(size+1);
	if (dest == NULL) {
		return NULL;  // Memory allocation failed
	}
	memcpy(dest, src, size);
	dest[size] = '\0';
	return dest;
}
#endif // NDB_UTIL_H

