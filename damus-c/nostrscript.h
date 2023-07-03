//
//  nostrscript.h
//  damus
//
//  Created by William Casarin on 2023-06-02.
//

#ifndef nostrscript_h
#define nostrscript_h

#define NSCRIPT_LOADED 1
#define NSCRIPT_PARSE_ERR 2
#define NSCRIPT_INIT_ERR 3

#include <stdio.h>
#include "wasm.h"

int nscript_load(struct wasm_parser *p, struct wasm_interp *interp, unsigned char *wasm, unsigned long len);
int nscript_nostr_cmd(struct wasm_interp *interp, int, void*, int);
int nscript_pool_send_to(struct wasm_interp *interp, const u16*, int, const u16 *, int);
int nscript_set_bool(struct wasm_interp *interp, const u16*, int, int);


#endif /* nostrscript_h */
