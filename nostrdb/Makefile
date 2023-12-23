CFLAGS = -Wall -Wno-misleading-indentation -Wno-unused-function -Werror -O2 -g -Ideps/secp256k1/include -Ideps/lmdb -Ideps/flatcc/include
HEADERS = src/sha256.h src/nostrdb.h src/cursor.h src/hex.h src/jsmn.h src/config.h src/sha256.h src/random.h src/memchr.h src/cpu.h $(C_BINDINGS)
FLATCC_SRCS=deps/flatcc/src/runtime/json_parser.c deps/flatcc/src/runtime/verifier.c deps/flatcc/src/runtime/builder.c deps/flatcc/src/runtime/emitter.c deps/flatcc/src/runtime/refmap.c
BOLT11_SRCS = src/bolt11/bolt11.c src/bolt11/bech32.c src/bolt11/tal.c src/bolt11/talstr.c src/bolt11/take.c src/bolt11/list.c src/bolt11/utf8.c src/bolt11/amount.c src/bolt11/hash_u5.c
SRCS = src/nostrdb.c src/sha256.c $(BOLT11_SRCS) $(FLATCC_SRCS)
LDS = $(OBJS) $(ARS) 
OBJS = $(SRCS:.c=.o)
DEPS = $(OBJS) $(HEADERS) $(ARS)
ARS = deps/lmdb/liblmdb.a deps/secp256k1/.libs/libsecp256k1.a 
LMDB_VER=0.9.31
FLATCC_VER=05dc16dc2b0316e61063bb1fc75426647badce48
PREFIX ?= /usr/local
SUBMODULES = deps/secp256k1
BINDINGS=src/bindings
C_BINDINGS_PROFILE=$(BINDINGS)/c/profile_builder.h $(BINDINGS)/c/profile_reader.h $(BINDINGS)/c/profile_verifier.h $(BINDINGS)/c/profile_json_parser.h
C_BINDINGS_META=$(BINDINGS)/c/meta_builder.h $(BINDINGS)/c/meta_reader.h $(BINDINGS)/c/meta_verifier.h $(BINDINGS)/c/meta_json_parser.h
C_BINDINGS_COMMON=$(BINDINGS)/c/flatbuffers_common_builder.h $(BINDINGS)/c/flatbuffers_common_reader.h
C_BINDINGS=$(C_BINDINGS_COMMON) $(C_BINDINGS_PROFILE) $(C_BINDINGS_META)
BIN=ndb

CHECKDATA=testdata/db/v0/data.mdb

all: lib ndb libnostrdb.a

libnostrdb.a: $(OBJS)
	ar rcs $@ $(OBJS)

lib: benches test

ndb: ndb.c $(DEPS)
	$(CC) -Isrc $(CFLAGS) ndb.c $(LDS) -o $@

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

src/bindings/%/.dir:
	mkdir -p $(shell dirname $@)
	touch $@

src/bindings/c/%_builder.h: schemas/%.fbs $(BINDINGS)/c/.dir
	flatcc --builder $< -o $(BINDINGS)/c

src/bindings/c/%_verifier.h bindings/c/%_reader.h: schemas/%.fbs $(BINDINGS)/c/.dir
	flatcc --verifier -o $(BINDINGS)/c $<

src/bindings/c/flatbuffers_common_reader.h: $(BINDINGS)/c/.dir
	flatcc --common_reader -o $(BINDINGS)/c

src/bindings/c/flatbuffers_common_builder.h: $(BINDINGS)/c/.dir
	flatcc --common_builder -o $(BINDINGS)/c

src/bindings/c/%_json_parser.h: schemas/%.fbs $(BINDINGS)/c/.dir
	flatcc --json-parser $< -o $(BINDINGS)/c

bindings-rust: $(BINDINGS)/rust/ndb_profile.rs $(BINDINGS)/rust/ndb_meta.rs

$(BINDINGS)/rust/ndb_profile.rs: schemas/profile.fbs $(BINDINGS)/rust
	flatc --gen-json-emit --rust $<
	@mv profile_generated.rs $@

$(BINDINGS)/rust/ndb_meta.rs: schemas/meta.fbs $(BINDINGS)/swift
	flatc --rust $< 
	@mv meta_generated.rs $@

bindings-swift: $(BINDINGS)/swift/NdbProfile.swift $(BINDINGS)/swift/NdbMeta.swift

$(BINDINGS)/swift/NdbProfile.swift: schemas/profile.fbs $(BINDINGS)/swift
	flatc --gen-json-emit --swift $<
	@mv profile_generated.swift $@

$(BINDINGS)/swift/NdbMeta.swift: schemas/meta.fbs $(BINDINGS)/swift
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

bench: bench-ingest-many.c $(DEPS) testdata/many-events.json
	$(CC) -Isrc $(CFLAGS) $< $(LDS) -o $@

testdata/db/.dir:
	@mkdir -p testdata/db
	touch testdata/db/.dir

test: test.c $(DEPS) testdata/db/.dir
	$(CC) -Isrc $(CFLAGS) test.c $(LDS) -o $@

.PHONY: tags clean
