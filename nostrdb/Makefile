CFLAGS = -Wall -Wno-misleading-indentation -Wno-unused-function -Werror -O2 -g -Ideps/secp256k1/include -Ideps/lmdb -Ideps/flatcc/include
HEADERS = sha256.h nostrdb.h cursor.h hex.h jsmn.h config.h sha256.h random.h memchr.h cpu.h $(C_BINDINGS)
FLATCC_SRCS=deps/flatcc/src/runtime/json_parser.c deps/flatcc/src/runtime/verifier.c deps/flatcc/src/runtime/builder.c deps/flatcc/src/runtime/emitter.c deps/flatcc/src/runtime/refmap.c
BOLT11_SRCS = bolt11/bolt11.c bolt11/bech32.c bolt11/tal.c bolt11/talstr.c bolt11/take.c bolt11/list.c bolt11/utf8.c bolt11/amount.c bolt11/hash_u5.c
SRCS = nostrdb.c sha256.c $(BOLT11_SRCS) $(FLATCC_SRCS)
LDS = $(OBJS) $(ARS) 
OBJS = $(SRCS:.c=.o)
DEPS = $(OBJS) $(HEADERS) $(ARS)
ARS = deps/lmdb/liblmdb.a deps/secp256k1/.libs/libsecp256k1.a 
LMDB_VER=0.9.31
FLATCC_VER=05dc16dc2b0316e61063bb1fc75426647badce48
PREFIX ?= /usr/local
SUBMODULES = deps/secp256k1
C_BINDINGS_PROFILE=bindings/c/profile_builder.h bindings/c/profile_reader.h bindings/c/profile_verifier.h bindings/c/profile_json_parser.h
C_BINDINGS_META=bindings/c/meta_builder.h bindings/c/meta_reader.h bindings/c/meta_verifier.h bindings/c/meta_json_parser.h
C_BINDINGS_COMMON=bindings/c/flatbuffers_common_builder.h bindings/c/flatbuffers_common_reader.h
C_BINDINGS=$(C_BINDINGS_COMMON) $(C_BINDINGS_PROFILE) $(C_BINDINGS_META)
BINDINGS=bindings
BIN=ndb

CHECKDATA=testdata/db/v0/data.mdb

all: lib ndb

lib: benches test

ndb: ndb.c $(DEPS)
	$(CC) $(CFLAGS) ndb.c $(LDS) -o $@

bindings: bindings-swift bindings-rust bindings-c

check: test $(CHECKDATA)
	rm -rf testdata/db/*.mdb
	./test || rm -rf testdata/db/v0
	rm -rf testdata/db/v0

clean:
	rm -rf test bench bench-ingest bench-ingest-many

benches: bench

distclean: clean
	rm -rf deps

tags:
	find . -name '*.c' -or -name '*.h' | xargs ctags

configurator: configurator.c
	$(CC) $< -o $@

config.h: configurator
	./configurator > $@

bindings-c: $(C_BINDINGS)

bindings/%/.dir:
	mkdir -p $(shell dirname $@)
	touch $@

bindings/c/%_builder.h: schemas/%.fbs bindings/c/.dir
	flatcc --builder $< -o bindings/c

bindings/c/%_verifier.h bindings/c/%_reader.h: schemas/%.fbs bindings/c/.dir
	flatcc --verifier -o bindings/c $<

bindings/c/flatbuffers_common_reader.h: bindings/c/.dir
	flatcc --common_reader -o bindings/c

bindings/c/flatbuffers_common_builder.h: bindings/c/.dir
	flatcc --common_builder -o bindings/c

bindings/c/%_json_parser.h: schemas/%.fbs bindings/c/.dir
	flatcc --json-parser $< -o bindings/c

bindings-rust: bindings/rust/ndb_profile.rs bindings/rust/ndb_meta.rs

bindings/rust/ndb_profile.rs: schemas/profile.fbs bindings/rust
	flatc --gen-json-emit --rust $<
	@mv profile_generated.rs $@

bindings/rust/ndb_meta.rs: schemas/meta.fbs bindings/swift
	flatc --rust $< 
	@mv meta_generated.rs $@

bindings-swift: bindings/swift/NdbProfile.swift bindings/swift/NdbMeta.swift

bindings/swift/NdbProfile.swift: schemas/profile.fbs bindings/swift
	flatc --gen-json-emit --swift $<
	@mv profile_generated.swift $@

bindings/swift/NdbMeta.swift: schemas/meta.fbs bindings/swift
	flatc --swift $<
	@mv meta_generated.swift $@

deps/.dir:
	@mkdir -p deps
	touch deps/.dir

deps/LMDB_$(LMDB_VER).tar.gz: deps/.dir
	curl -L https://github.com/LMDB/lmdb/archive/refs/tags/LMDB_$(LMDB_VER).tar.gz -o $@

deps/flatcc_$(FLATCC_VER).tar.gz: deps/.dir
	curl -L https://github.com/jb55/flatcc/archive/$(FLATCC_VER).tar.gz -o $@

deps/flatcc/src/runtime/json_parser.c: deps/flatcc_$(FLATCC_VER).tar.gz deps/.dir
	tar xf $<
	rm -rf deps/flatcc
	mv flatcc-$(FLATCC_VER) deps/flatcc
	touch $@

deps/lmdb/lmdb.h: deps/LMDB_$(LMDB_VER).tar.gz deps/.dir
	tar xf $<
	rm -rf deps/lmdb
	mv lmdb-LMDB_$(LMDB_VER)/libraries/liblmdb deps/lmdb
	rm -rf lmdb-LMDB_$(LMDB_VER)
	touch $@

deps/secp256k1/.git: deps/.dir
	@devtools/refresh-submodules.sh $(SUBMODULES)

deps/secp256k1/include/secp256k1.h: deps/secp256k1/.git

deps/secp256k1/configure: deps/secp256k1/.git
	cd deps/secp256k1; \
	./autogen.sh

deps/secp256k1/.libs/libsecp256k1.a: deps/secp256k1/config.log
	cd deps/secp256k1; \
	make -j libsecp256k1.la

deps/secp256k1/config.log: deps/secp256k1/configure
	cd deps/secp256k1; \
	./configure --disable-shared --enable-module-ecdh --enable-module-schnorrsig --enable-module-extrakeys

deps/lmdb/liblmdb.a: deps/lmdb/lmdb.h
	$(MAKE) -C deps/lmdb liblmdb.a

bench: bench.c $(DEPS)
	$(CC) $(CFLAGS) bench.c $(LDS) -o $@

testdata/db/ndb-v0.tar.zst:
	curl https://cdn.jb55.com/s/ndb-v0.tar.zst -o $@

testdata/db/ndb-v0.tar: testdata/db/ndb-v0.tar.zst
	zstd -d < $< > $@

testdata/db/v0/data.mdb: testdata/db/ndb-v0.tar
	tar xf $<
	rm -rf testdata/db/v0
	mv v0 testdata/db

testdata/many-events.json.zst:
	curl https://cdn.jb55.com/s/many-events.json.zst -o $@

testdata/many-events.json: testdata/many-events.json.zst
	zstd -d $<

bench-ingest-many: bench-ingest-many.c $(DEPS) testdata/many-events.json
	$(CC) $(CFLAGS) $< $(LDS) -o $@

testdata/db/.dir:
	@mkdir -p testdata/db
	touch testdata/db/.dir

test: test.c $(DEPS) testdata/db/.dir
	$(CC) $(CFLAGS) test.c $(LDS) -o $@

.PHONY: tags clean
