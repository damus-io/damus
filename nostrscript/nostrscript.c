//
//  nostrscript.c
//  damus
//
//  Created by William Casarin on 2023-06-02.
//

#include "nostrscript.h"
#include "wasm.h"
#include "array_size.h"

// function to check if the character is in surrogate pair range
static INLINE int is_surrogate(uint16_t uc) {
    return (uc - 0xd800u) < 2048u;
}

// function to convert utf16 to utf8
static int utf16_to_utf8(u16 utf16, u8 *utf8) {
    if (utf16 < 0x80) { // 1-byte sequence
        utf8[0] = (uint8_t) utf16;
        return 1;
    }
    else if (utf16 < 0x800) { // 2-byte sequence
        utf8[0] = (uint8_t) (0xc0 | (utf16 >> 6));
        utf8[1] = (uint8_t) (0x80 | (utf16 & 0x3f));
        return 2;
    }
    else if (!is_surrogate(utf16)) { // 3-byte sequence
        utf8[0] = (uint8_t) (0xe0 | (utf16 >> 12));
        utf8[1] = (uint8_t) (0x80 | ((utf16 >> 6) & 0x3f));
        utf8[2] = (uint8_t) (0x80 | (utf16 & 0x3f));
        return 3;
    }
    else { // surrogate pair, return error
        return -1;
    }
}

static int nostr_cmd(struct wasm_interp *interp) {
    struct val *params = NULL;
    const char *val = NULL;
    int len, cmd, ival;
    
    if (!get_params(interp, &params, 3) || params == NULL)
        return interp_error(interp, "get params");

    // command
    cmd = params[0].num.i32;
    
    // value
    
    ival = params[1].num.i32;
    if (!mem_ptr_str(interp, ival, &val))
        val = 0;

    // length
    len = params[2].num.i32;

    intptr_t iptr = ival;
    return nscript_nostr_cmd(interp, cmd, val ? (void*)val : (void*)iptr, len);
}

static int print_utf16_str(u16 *chars) {
    u16 *p = chars;
    int c;
    
    while (*p) {
        if (utf16_to_utf8(*p, (u8*)&c) == -1)
            return 0;
        
        printf("%c", c);
        
        p++;
    }
    
    return 1;
}

static int nostr_log(struct wasm_interp *interp) {
    struct val *vals;
    const char *str;
    struct callframe *callframe;
    
    if (!get_params(interp, &vals, 1))
        return interp_error(interp, "nostr_log get params");
    
    if (!mem_ptr_str(interp, vals[0].num.i32, &str))
        return interp_error(interp, "nostr_log log param");
    
    if (!(callframe = top_callframes(&interp->callframes, 2)))
        return interp_error(interp, "nostr_log callframe");
    
    printf("nostr_log:%s: ", callframe->func->name);
    
    print_utf16_str((u16*)str);
    printf("\n");
    
    return 1;
}

static int nostr_set_bool(struct wasm_interp *interp) {
    struct val *params = NULL;
    const u16 *setting;
    u32 val, len;

    if (!get_params(interp, &params, 3) || params == NULL)
        return 0;

    if (!mem_ptr_str(interp, params[0].num.i32, (const char**)&setting))
        return 0;

    len = params[1].num.i32;
    val = params[2].num.i32 > 0 ? 1 : 0;

    return nscript_set_bool(interp, setting, len, val);
}

static int nostr_pool_send_to(struct wasm_interp *interp) {
    struct val *params = NULL;
    const u16 *req, *to;
    int req_len, to_len;
    
    if (!get_params(interp, &params, 4) || params == NULL)
        return 0;

    if (!mem_ptr_str(interp, params[0].num.i32, (const char**)&req))
        return 0;
    
    req_len = params[1].num.i32;
    
    if (!mem_ptr_str(interp, params[2].num.i32, (const char**)&to))
        return 0;
    
    to_len = params[3].num.i32;
    
    return nscript_pool_send_to(interp, req, req_len, to, to_len);
}

static int nscript_abort(struct wasm_interp *interp) {
    struct val *params = NULL;
    const char *msg = "", *filename;
    int line, col;
    
    if (!get_params(interp, &params, 4) || params == NULL)
        return interp_error(interp, "get params");
    
    if (params[0].ref.addr != 0 && !mem_ptr_str(interp, params[0].ref.addr, &msg))
        return interp_error(interp, "abort msg");

    if (!mem_ptr_str(interp, params[1].ref.addr, &filename))
        return interp_error(interp, "abort filename");
    
    line = params[2].num.i32;
    col = params[3].num.i32;

    printf("nscript_abort:");
    print_utf16_str((u16*)filename);
    printf(":%d:%d: ", line, col);
    print_utf16_str((u16*)msg);
    printf("\n");
    
    return 0;
}

static struct builtin nscript_builtins[] = {
    { .name = "null", .fn = 0 },
    { .name = "nostr_log", .fn = nostr_log },
    { .name = "nostr_cmd", .fn = nostr_cmd },
    { .name = "nostr_pool_send_to", .fn = nostr_pool_send_to },
    { .name = "nostr_set_bool", .fn = nostr_set_bool },
    { .name = "abort", .fn = nscript_abort },
};

int nscript_load(struct wasm_parser *p, struct wasm_interp *interp, unsigned char *wasm, unsigned long len) {
    wasm_parser_init(p, wasm, len, len * 16, nscript_builtins, ARRAY_SIZE(nscript_builtins));

    if (!parse_wasm(p)) {
        wasm_parser_free(p);
        return NSCRIPT_PARSE_ERR;
    }

    if (!wasm_interp_init(interp, &p->module)) {
        print_error_backtrace(&interp->errors);
        wasm_parser_free(p);
        return NSCRIPT_INIT_ERR;
    }

    //setup_wasi(&interp, argc, argv, env);
    //wasm_parser_free(&p);
    
    return NSCRIPT_LOADED;
}
