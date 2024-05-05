
#ifndef PROTOVERSE_WASM_H
#define PROTOVERSE_WASM_H

static const unsigned char WASM_MAGIC[] = {0,'a','s','m'};

#define WASM_VERSION 0x01
#define MAX_U32_LEB128_BYTES 5
#define MAX_U64_LEB128_BYTES 10
#define MAX_CUSTOM_SECTIONS 32
#define MAX_BUILTINS 64
#define BUILTIN_SUSPEND 42

#define FUNC_TYPE_TAG 0x60


#include "cursor.h"
#include "error.h"

#ifdef NOINLINE
  #define INLINE __attribute__((noinline))
#else
  #define INLINE inline
#endif


#define interp_error(p, fmt, ...) note_error(&((p)->errors), interp_codeptr(p), fmt, ##__VA_ARGS__)
#define parse_err(p, fmt, ...) note_error(&((p)->errs), &(p)->cur, fmt, ##__VA_ARGS__)

#include "short_types.h"

enum valtype {
	val_i32 = 0x7F,
	val_i64 = 0x7E,
	val_f32 = 0x7D,
	val_f64 = 0x7C,
	val_ref_null = 0xD0,
	val_ref_func = 0x70, 
	val_ref_extern = 0x6F,
};

enum const_instr {
	ci_const_i32   = 0x41,
	ci_const_i64   = 0x42,
	ci_const_f32   = 0x43,
	ci_const_f64   = 0x44,
	ci_ref_null    = 0xD0,
	ci_ref_func    = 0xD2,
	ci_global_get  = 0x23,
	ci_end         = 0x0B,
};

enum limit_type {
	limit_min = 0x00,
	limit_min_max = 0x01,
};

struct limits {
	u32 min;
	u32 max;
	enum limit_type type;
};

enum section_tag {
	section_custom,
	section_type,
	section_import,
	section_function,
	section_table,
	section_memory,
	section_global,
	section_export,
	section_start,
	section_element,
	section_code,
	section_data,
	section_data_count,
	section_name,
	num_sections,
};

enum name_subsection_tag {
	name_subsection_module,
	name_subsection_funcs,
	name_subsection_locals,
	num_name_subsections,
};

enum reftype {
	funcref   = 0x70,
	externref = 0x6F,
};

struct resulttype {
	unsigned char *valtypes; /* enum valtype */
	u32 num_valtypes;
};

struct functype {
	struct resulttype params;
	struct resulttype result;
};

struct table {
	enum reftype reftype;
	struct limits limits;
};

struct tablesec {
	struct table *tables;
	u32 num_tables;
};

enum elem_mode {
	elem_mode_passive,
	elem_mode_active,
	elem_mode_declarative,
};

struct expr {
	u8 *code;
	u32 code_len;
};

struct refval {
	u32 addr;
};

struct table_inst {
	struct refval *refs;
	enum reftype reftype;
	u32 num_refs;
};

struct numval {
	union {
		int i32;
		u32 u32;
		int64_t i64;
		uint64_t u64;
		float f32;
		double f64;
	};
};

struct val {
	enum valtype type;
	union {
		struct numval num;
		struct refval ref;
	};
};

struct elem_inst {
	struct val val;
	u16 elem;
	u16 init;
};

struct elem {
	struct expr offset;
	u32 tableidx;
	struct expr *inits;
	u32 num_inits;
	enum elem_mode mode;
	enum reftype reftype;
	struct val val;
};

struct customsec {
	const char *name;
	unsigned char *data;
	u32 data_len;
};

struct elemsec {
	struct elem *elements;
	u32 num_elements;
};

struct memsec {
	struct limits *mems; /* memtype */
	u32 num_mems;
};

struct funcsec {
	u32 *type_indices;
	u32 num_indices;
};

enum mut {
	mut_const,
	mut_var,
};

struct globaltype {
	enum valtype valtype;
	enum mut mut;
};

struct globalsec {
	struct global *globals;
	u32 num_globals;
};

struct typesec {
	struct functype *functypes;
	u32 num_functypes;
};

enum import_type {
	import_func,
	import_table,
	import_mem,
	import_global,
};

struct importdesc {
	enum import_type type;
	union {
		u32 typeidx;
		struct limits tabletype;
		struct limits memtype;
		struct globaltype globaltype;
	};
};

struct import {
	const char *module_name;
	const char *name;
	struct importdesc desc;
	int resolved_builtin;
};

struct importsec {
	struct import *imports;
	u32 num_imports;
};

struct global {
	struct globaltype type;
	struct expr init;
	struct val val;
};

struct local_def {
	u32 num_types;
	enum valtype type;
};

/* "code" */
struct wasm_func {
	struct expr code;
	struct local_def *local_defs;
	u32 num_local_defs;
};

enum func_type {
	func_type_wasm,
	func_type_builtin,
};

struct func {
	union {
		struct wasm_func *wasm_func;
		struct builtin *builtin;
	};
	u32 num_locals;
	struct functype *functype;
	enum func_type type;
	const char *name;
	u32 idx;
};

struct codesec {
	struct wasm_func *funcs;
	u32 num_funcs;
};

enum exportdesc {
	export_func,
	export_table,
	export_mem,
	export_global,
};

struct wexport {
	const char *name;
	u32 index;
	enum exportdesc desc;
};

struct exportsec {
	struct wexport *exports;
	u32 num_exports;
};

struct nameassoc {
	u32 index;
	const char *name;
};

struct namemap {
	struct nameassoc *names;
	u32 num_names;
};

struct namesec {
	const char *module_name;
	struct namemap func_names;
	int parsed;
};

struct wsection {
	enum section_tag tag;
};

enum bulk_tag {
	i_memory_copy = 10,
	i_memory_fill = 11,
	i_table_init  = 12,
	i_elem_drop   = 13,
	i_table_copy  = 14,
	i_table_grow  = 15,
	i_table_size  = 16,
	i_table_fill  = 17,
};

enum instr_tag {
	/* control instructions */
	i_unreachable   = 0x00,
	i_nop           = 0x01,
	i_block         = 0x02,
	i_loop          = 0x03,
	i_if            = 0x04,
	i_else          = 0x05,
	i_end           = 0x0B,
	i_br            = 0x0C,
	i_br_if         = 0x0D,
	i_br_table      = 0x0E,
	i_return        = 0x0F,
	i_call          = 0x10,
	i_call_indirect = 0x11,

	/* parametric instructions */
	i_drop          = 0x1A,
	i_select        = 0x1B,
	i_selects       = 0x1C,

	/* variable instructions */
	i_local_get     = 0x20,
	i_local_set     = 0x21,
	i_local_tee     = 0x22,
	i_global_get    = 0x23,
	i_global_set    = 0x24,
	i_table_get     = 0x25,
	i_table_set     = 0x26,

	/* memory instructions */
	i_i32_load      = 0x28,
	i_i64_load      = 0x29,
	i_f32_load      = 0x2A,
	i_f64_load      = 0x2B,
	i_i32_load8_s   = 0x2C,
	i_i32_load8_u   = 0x2D,
	i_i32_load16_s  = 0x2E,
	i_i32_load16_u  = 0x2F,
	i_i64_load8_s   = 0x30,
	i_i64_load8_u   = 0x31,
	i_i64_load16_s  = 0x32,
	i_i64_load16_u  = 0x33,
	i_i64_load32_s  = 0x34,
	i_i64_load32_u  = 0x35,
	i_i32_store     = 0x36,
	i_i64_store     = 0x37,
	i_f32_store     = 0x38,
	i_f64_store     = 0x39,
	i_i32_store8    = 0x3A,
	i_i32_store16   = 0x3B,
	i_i64_store8    = 0x3C,
	i_i64_store16   = 0x3D,
	i_i64_store32   = 0x3E,
	i_memory_size   = 0x3F,
	i_memory_grow   = 0x40,

	/* numeric instructions */
	i_i32_const     = 0x41,
	i_i64_const     = 0x42,
	i_f32_const     = 0x43,
	i_f64_const     = 0x44,

	i_i32_eqz       = 0x45,
	i_i32_eq        = 0x46,
	i_i32_ne        = 0x47,
	i_i32_lt_s      = 0x48,
	i_i32_lt_u      = 0x49,
	i_i32_gt_s      = 0x4A,
	i_i32_gt_u      = 0x4B,
	i_i32_le_s      = 0x4C,
	i_i32_le_u      = 0x4D,
	i_i32_ge_s      = 0x4E,
	i_i32_ge_u      = 0x4F,

	i_i64_eqz       = 0x50,
	i_i64_eq        = 0x51,
	i_i64_ne        = 0x52,
	i_i64_lt_s      = 0x53,
	i_i64_lt_u      = 0x54,
	i_i64_gt_s      = 0x55,
	i_i64_gt_u      = 0x56,
	i_i64_le_s      = 0x57,
	i_i64_le_u      = 0x58,
	i_i64_ge_s      = 0x59,
	i_i64_ge_u      = 0x5A,

	i_f32_eq        = 0x5B,
	i_f32_ne        = 0x5C,
	i_f32_lt        = 0x5D,
	i_f32_gt        = 0x5E,
	i_f32_le        = 0x5F,
	i_f32_ge        = 0x60,

	i_f64_eq        = 0x61,
	i_f64_ne        = 0x62,
	i_f64_lt        = 0x63,
	i_f64_gt        = 0x64,
	i_f64_le        = 0x65,
	i_f64_ge        = 0x66,

	i_i32_clz       = 0x67,
	i_i32_ctz       = 0x68,
	i_i32_popcnt    = 0x69,

	i_i32_add       = 0x6A,
	i_i32_sub       = 0x6B,
	i_i32_mul       = 0x6C,
	i_i32_div_s     = 0x6D,
	i_i32_div_u     = 0x6E,
	i_i32_rem_s     = 0x6F,
	i_i32_rem_u     = 0x70,
	i_i32_and       = 0x71,
	i_i32_or        = 0x72,
	i_i32_xor       = 0x73,
	i_i32_shl       = 0x74,
	i_i32_shr_s     = 0x75,
	i_i32_shr_u     = 0x76,
	i_i32_rotl      = 0x77,
	i_i32_rotr      = 0x78,

	i_i64_clz       = 0x79,
	i_i64_ctz       = 0x7A,
	i_i64_popcnt    = 0x7B,
	i_i64_add       = 0x7C,
	i_i64_sub       = 0x7D,
	i_i64_mul       = 0x7E,
	i_i64_div_s     = 0x7F,
	i_i64_div_u     = 0x80,
	i_i64_rem_s     = 0x81,
	i_i64_rem_u     = 0x82,
	i_i64_and       = 0x83,
	i_i64_or        = 0x84,
	i_i64_xor       = 0x85,
	i_i64_shl       = 0x86,
	i_i64_shr_s     = 0x87,
	i_i64_shr_u     = 0x88,
	i_i64_rotl      = 0x89,
	i_i64_rotr      = 0x8A,

	i_f32_abs = 0x8b,
	i_f32_neg = 0x8c,
	i_f32_ceil = 0x8d,
	i_f32_floor = 0x8e,
	i_f32_trunc = 0x8f,
	i_f32_nearest = 0x90,
	i_f32_sqrt = 0x91,
	i_f32_add = 0x92,
	i_f32_sub = 0x93,
	i_f32_mul = 0x94,
	i_f32_div = 0x95,
	i_f32_min = 0x96,
	i_f32_max = 0x97,
	i_f32_copysign = 0x98,

	i_f64_abs = 0x99,
	i_f64_neg = 0x9a,
	i_f64_ceil = 0x9b,
	i_f64_floor = 0x9c,
	i_f64_trunc = 0x9d,
	i_f64_nearest = 0x9e,
	i_f64_sqrt = 0x9f,
	i_f64_add = 0xa0,
	i_f64_sub = 0xa1,
	i_f64_mul = 0xa2,
	i_f64_div = 0xa3,
	i_f64_min = 0xa4,
	i_f64_max = 0xa5,
	i_f64_copysign = 0xa6,

	i_i32_wrap_i64 = 0xa7,
	i_i32_trunc_f32_s = 0xa8,
	i_i32_trunc_f32_u = 0xa9,
	i_i32_trunc_f64_s = 0xaa,
	i_i32_trunc_f64_u = 0xab,
	i_i64_extend_i32_s = 0xac,
	i_i64_extend_i32_u = 0xad,
	i_i64_trunc_f32_s = 0xae,
	i_i64_trunc_f32_u = 0xaf,
	i_i64_trunc_f64_s = 0xb0,
	i_i64_trunc_f64_u = 0xb1,
	i_f32_convert_i32_s = 0xb2,
	i_f32_convert_i32_u = 0xb3,
	i_f32_convert_i64_s = 0xb4,
	i_f32_convert_i64_u = 0xb5,
	i_f32_demote_f64 = 0xb6,
	i_f64_convert_i32_s = 0xb7,
	i_f64_convert_i32_u = 0xb8,
	i_f64_convert_i64_s = 0xb9,
	i_f64_convert_i64_u = 0xba,
	i_f64_promote_f32 = 0xbb,

	i_i32_reinterpret_f32 = 0xbc,
	i_i64_reinterpret_f64 = 0xbd,
	i_f32_reinterpret_i32 = 0xbe,
	i_f64_reinterpret_i64 = 0xbf,

	i_i32_extend8_s = 0xc0,
	i_i32_extend16_s = 0xc1,
	i_i64_extend8_s = 0xc2,
	i_i64_extend16_s = 0xc3,
	i_i64_extend32_s = 0xc4,

	i_ref_null    = 0xD0,
	i_ref_is_null = 0xD1,
	i_ref_func    = 0xD2,

	i_bulk_op     = 0xFC,
	/* TODO: more instrs */

};

enum blocktype_tag {
	blocktype_empty,
	blocktype_valtype,
	blocktype_index,
};

struct blocktype {
	enum blocktype_tag tag;
	union {
		enum valtype valtype;
		int type_index;
	};
};

struct instrs {
	unsigned char *data;
	u32 len;
};

struct block {
	struct blocktype type;
	struct expr instrs;
};

struct memarg {
	u32 offset;
	u32 align;
};

struct br_table {
	u32 num_label_indices;
	u32 label_indices[512];
	u32 default_label;
};

struct call_indirect {
	u32 tableidx;
	u32 typeidx;
};

struct table_init {
	u32 tableidx;
	u32 elemidx;
};

struct table_copy {
	u32 from;
	u32 to;
};

struct bulk_op {
	enum bulk_tag tag;
	union {
		struct table_init table_init;
		struct table_copy table_copy;
		u32 idx;
	};
};

struct select_instr {
	u8 *valtypes;
	u32 num_valtypes;
};

struct instr {
	enum instr_tag tag;
	int pos;
	union {
		struct br_table br_table;
		struct bulk_op bulk_op;
		struct call_indirect call_indirect;
		struct memarg memarg;
		struct select_instr select;
		struct block block;
		struct expr else_block;
		double f64;
		float f32;
		int i32;
		u32 u32;
		int64_t i64;
		u64 u64;
		unsigned char memidx;
		enum reftype reftype;
	};
};

enum datamode {
	datamode_active,
	datamode_passive,
};

struct wdata_active {
	u32 mem_index;
	struct expr offset_expr;
};

struct wdata {
	struct wdata_active active;
	u8 *bytes;
	u32 bytes_len;
	enum datamode mode;
};

struct datasec {
	struct wdata *datas;
	u32 num_datas;
};

struct startsec {
	u32 start_fn;
};

struct module {
	unsigned int parsed;
	unsigned int custom_sections;

	struct func *funcs;
    
	u32 num_funcs;

	struct customsec custom_section[MAX_CUSTOM_SECTIONS];
	struct typesec type_section;
	struct funcsec func_section;
	struct importsec import_section;
	struct exportsec export_section;
	struct codesec code_section;
	struct tablesec table_section;
	struct memsec memory_section;
	struct globalsec global_section;
	struct startsec start_section;
	struct elemsec element_section;
	struct datasec data_section;
	struct namesec name_section;
};

// make sure the struct is packed so that 
struct label {
	u32 instr_pos; // resolved status is stored in HOB of pos
	u32 jump;
};

struct callframe {
	struct cursor code;
	struct val *locals;
	struct func *func;
	u16 prev_stack_items;
};

struct resolver {
	u16 label;
	u8 end_tag;
	u8 start_tag;
};

struct global_inst {
	struct val val;
};

struct module_inst {
	struct table_inst *tables;
	struct global_inst *globals;
	struct elem_inst *elements;

	u32 num_tables;
	u32 num_globals;
	u32 num_elements;

	int start_fn;
	unsigned char *globals_init;
};

struct wasi {
	int argc;
	const char **argv;

	int environc;
	const char **environ;
};

struct wasm_interp;

struct builtin {
    const char *name;
    int (*fn)(struct wasm_interp *);
    int (*prepare_args)(struct wasm_interp *);
};

struct wasm_interp {
	struct module *module;
	struct module_inst module_inst;
	struct wasi wasi;
    void *context;
    
    struct builtin builtins[MAX_BUILTINS];
    int num_builtins;
    
	int prev_resolvers, quitting;

	struct errors errors; /* struct error */
	size_t ops;

	struct cursor callframes; /* struct callframe */
	struct cursor stack; /* struct val */
	struct cursor mem; /* u8/mixed */

	struct cursor memory; /* memory pages (65536 blocks) */

	struct cursor locals; /* struct val */
	struct cursor labels; /* struct labels */
	struct cursor num_labels;

	// resolve stack for the current function. every time a control
	// instruction is encountered, the label index is pushed. When an
	// instruction is popped, we can resolve the label
	struct cursor resolver_stack; /* struct resolver */
	struct cursor resolver_offsets; /* int */
};

struct wasm_parser {
	struct module module;
    struct builtin *builtins;
    u32 num_builtins;
	struct cursor cur;
	struct cursor mem;
	struct errors errs;
};


int run_wasm(unsigned char *wasm, unsigned long len, int argc, const char **argv, char **env, int *retval);
int parse_wasm(struct wasm_parser *p);
int wasm_interp_init(struct wasm_interp *interp, struct module *module);
void wasm_parser_free(struct wasm_parser *parser);
void wasm_parser_init(struct wasm_parser *p, u8 *wasm, size_t wasm_len, size_t arena_size, struct builtin *, int num_builtins);
void wasm_interp_free(struct wasm_interp *interp);
int interp_wasm_module(struct wasm_interp *interp, int *retval);
int interp_wasm_module_resume(struct wasm_interp *interp, int *retval);
void print_error_backtrace(struct errors *errors);
void setup_wasi(struct wasm_interp *interp, int argc, const char **argv, char **env);
void print_callstack(struct wasm_interp *interp);

// builtin helpers
int get_params(struct wasm_interp *interp, struct val** vals, u32 num_vals);
int get_var_params(struct wasm_interp *interp, struct val** vals, u32 *num_vals);
u8 *interp_mem_ptr(struct wasm_interp *interp, u32 ptr, int size);

static INLINE struct callframe *top_callframe(struct cursor *cur)
{
    return (struct callframe*)cursor_top(cur, sizeof(struct callframe));
}


static INLINE struct cursor *interp_codeptr(struct wasm_interp *interp)
{
    struct callframe *frame;
    if (unlikely(!(frame = top_callframe(&interp->callframes))))
        return 0;
    return &frame->code;
}


static INLINE int mem_ptr_str(struct wasm_interp *interp, u32 ptr,
        const char **str)
{
    // still technically unsafe if the string runs over the end of memory...
    if (!(*str = (const char*)interp_mem_ptr(interp, ptr, 1))) {
        return interp_error(interp, "int memptr");
    }
    return 1;
}

static INLINE int mem_ptr_i32(struct wasm_interp *interp, u32 ptr, int **i)
{
    if (!(*i = (int*)interp_mem_ptr(interp, ptr, sizeof(int))))
        return interp_error(interp, "int memptr");
    return 1;
}

static INLINE int cursor_pushval(struct cursor *cur, struct val *val)
{
    return cursor_push(cur, (u8*)val, sizeof(*val));
}

static INLINE int cursor_push_i32(struct cursor *stack, int i)
{
    struct val val;
    val.type = val_i32;
    val.num.i32 = i;

    return cursor_pushval(stack, &val);
}

static INLINE int stack_push_i32(struct wasm_interp *interp, int i)
{
    return cursor_push_i32(&interp->stack, i);
}

static INLINE struct callframe *top_callframes(struct cursor *cur, int top)
{
    return (struct callframe*)cursor_topn(cur, sizeof(struct callframe), top);
}

static INLINE int was_section_parsed(struct module *module,
    enum section_tag section)
{
    if (section == section_custom)
        return module->custom_sections > 0;

    return module->parsed & (1 << section);
}


#endif /* PROTOVERSE_WASM_H */
