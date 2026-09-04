# Vendoring nostrdb

`nostrdb/` is a vendored copy of https://github.com/damus-io/nostrdb, not a
submodule. The Swift files at the top of this directory (`Ndb.swift`,
`NdbFilter.swift`, `NdbNote.swift`, `NdbTxn.swift`, the iterators, `Test/`, …)
are **damus-local** — upstream is C-only. Everything under `src/`, `ccan/` and
`flatcc/` comes from upstream.

## Currently synced to

Upstream `master` at **5dbd1ce80bb5** ("test: destroy what the tests
allocate").

## damus-local divergence from that commit

These are the only intentional differences. All of them except the
`sodium/` shim and the build-layout edits are damus bug fixes that should be
upstreamed rather than carried here forever.

| Where | What | Origin |
| --- | --- | --- |
| `src/sodium/` | Minimal ChaCha20-IETF providing `crypto_stream_chacha20_ietf_xor_ic`, the only libsodium symbol `src/nip44.c` uses. Upstream links all of `deps/libsodium`; vendoring that into the Xcode project would pull in its build system, CPU dispatch, randombytes and utils layers for one stream cipher. Validated against nostrdb's own NIP-44 test vectors. | damus-local |
| `src/nostrdb.c` | Debug-only watchdog that registers read transactions in `_ndb_begin_query` keyed by owning `struct ndb_lmdb`, clears them in `ndb_end_query` and per-env in `ndb_destroy`, and aborts with the opening stack trace if one stays open past 3s. `#ifdef DEBUG` only. | `21ea74469b8f` and its follow-ups |
| `src/nostrdb.c`, `src/nostrdb.h` | `ndb_prune` sizes its destination map from the source's pages *in use* (×1.5, floored at `NDB_PRUNE_MIN_DST_MAPSIZE`, capped at the source's mapsize) instead of from the source's mapsize. Upstream's version asks for a second reservation as large as the live database's — 32 GiB on top of 32 GiB on iOS, at the per-process address space ceiling — and `mdb_env_open` returns ENOMEM. The destination only ever receives a subset of the source, so its usage bounds the output. | headway:damus-ios/mansion-grow-kite |
| `src/nostrdb.c`, `src/nostrdb.h` | `ndb_prune` takes a `struct ndb_prune_error *` out-param (may be NULL) reporting which of its failure sites fired, the LMDB `rc`, the mapsize it asked of the destination, and how many profiles/notes it had copied; `ndb_prune_phase_name` names a phase. `ndb_init_lmdb` reports the same way through `enum ndb_prune_phase *`/`int *` out-params (`ndb_init` passes NULL) and now closes its env and aborts its txn on every failure path instead of leaking them, and `ndb_init` frees the half-built `struct ndb` when it fails — damus retries `ndb_init` with a halved mapsize, which otherwise stranded a multi-gigabyte mapping per attempt. Upstream returns 0/1 and only `fprintf`s the cause, which is unrecoverable from a field crash report. | headway:damus-ios/mansion-grow-kite |
| `src/nostrdb.c` | `ndb_note_to_blocks` passes the real buffer size (`2<<18`) to `ndb_parse_content`; upstream passes `content_len` as the buffer size. | `12a7b483a0ed` |
| `src/nostrdb.h`, `src/nostr_bech32.c` | `kind`/`has_kind` on `bech32_nevent` and `bech32_nprofile`, `kind` on `bech32_naddr`, the `nostr_bech32_t` typedef, and `TLV_KIND` parsing (naddr additionally requires a kind). Consumed by `Bech32Object.swift`. | `d8e7b4707e7e` |
| `src/block.c` | `assert(blocks->total_size < 1000000)` in `ndb_blocks_total_size`. | `919f644cba93` |
| `src/content_parser.c` | `MAX_PREFIX` 8 → 9 (room for the NUL), a null-terminated copy of the invoice string before `bolt11_decode_minimal`, and `blocks_size` measured from the buffer start rather than `blocks_start`. | `fae061cec0e1`, `05b62c5860e8`, `b9d8b1dbf364` |
| `src/bolt11/bech32.c` | `bech32_decode` derives the max HRP length from the input length instead of a constant, and `bech32_decode_len` reserves a byte for the NUL. Supersedes upstream's `8 -> 10` bump. | `5b6534fd566c` |
| `src/bolt11/bolt11.c` | NULL `fail` guard in `decode_fail`; `len < 8` guard against underflow in `bech32_decode_alloc`. | `05b62c5860e8` |
| `src/bindings/c/*.h`, `src/bindings/swift/*.swift` | Build-layout edits: the `flatcc/` prefix is stripped from includes (flatcc is flattened into `nostrdb/flatcc/` here) and `import FlatBuffers` is removed. | `copy-ndb` |

Not built: `src/giftwrap.c` is copied in by the re-sync below but is in no
target's Sources phase, matching upstream, which leaves it out of its own
`SRCS` because it does not compile. `src/configurator.c` is not vendored at all
(`src/config.h` is checked in).

`src/nostrdb.c` is otherwise byte-identical to upstream, as are `ccan/` and
`flatcc/` (both unchanged upstream since the previous sync).

## Re-syncing

Do it as a 3-way merge rather than a copy, so the local patches above either
rebase cleanly or show up as conflicts:

```bash
UPSTREAM=~/dev/github/damus-io/nostrdb          # a checkout of upstream master
git -C "$UPSTREAM" fetch origin

# 1. find the upstream commit the vendored copy is closest to
V=nostrdb/src/nostrdb.c
for c in $(git -C "$UPSTREAM" log --format=%H master -- src/nostrdb.c); do
  n=$(git -C "$UPSTREAM" cat-file blob "$c:src/nostrdb.c" | diff - "$V" | wc -l)
  echo "$n $c"
done | sort -n | head -1

# 2. reconstruct "that base + damus patches" in a scratch clone, then rebase
git clone --shared "$UPSTREAM" /tmp/ndb-sync
cd /tmp/ndb-sync
git checkout -b damus-local <BASE_FROM_STEP_1>
cp -R <damus>/nostrdb/src/. src/
git add -A src && git commit -m 'damus-local patches'
git rebase master            # resolve conflicts, keeping the table above in mind

# 3. copy the result back and drop upstream-only build files
cd <damus>
git archive --remote=/tmp/ndb-sync damus-local src | tar -x -C /tmp/merged
rm -f /tmp/merged/src/configurator.c
rsync -a --delete /tmp/merged/src/ nostrdb/src/
```

When only a handful of files changed upstream (`git -C "$UPSTREAM" diff --stat
<BASE>..<TARGET> -- src/` tells you), a per-file `git merge-file` is quicker
than the scratch-clone rebase and gives the same 3-way result:

```bash
for f in nostrdb.c nostrdb.h ...; do
  git -C "$UPSTREAM" cat-file blob <BASE>:src/$f   > /tmp/$f.base
  git -C "$UPSTREAM" cat-file blob <TARGET>:src/$f > /tmp/$f.theirs
  cp nostrdb/src/$f /tmp/$f.merged
  git merge-file -L damus -L upstream-base -L upstream-new \
    /tmp/$f.merged /tmp/$f.base /tmp/$f.theirs
done
```

Either way, verify the result before committing: `diff` each merged file
against the upstream target blob and check that what is left over is exactly
the divergence table above, no more and no less.

Then add any new `src/*.c` to the four `Sources` build phases that already
compile `nostrdb.c` (damus, damusTests, DamusNotificationService and the
share/highlighter extensions), rebuild, and run both `just test` and upstream's
`make check` on the merged tree.
