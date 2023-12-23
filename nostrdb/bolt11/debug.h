
#ifndef PROTOVERSE_DEBUG_H
#define PROTOVERSE_DEBUG_H

#include <stdio.h>

#define unusual(...) fprintf(stderr, "UNUSUAL: " __VA_ARGS__)

#ifdef DEBUG
#define debug(...) printf(__VA_ARGS__)
#else
#define debug(...)
#endif

#endif /* PROTOVERSE_DEBUG_H */
