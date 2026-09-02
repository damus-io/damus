# Vendoring nostrdb

`nostrdb/` is a vendored copy of https://github.com/damus-io/nostrdb, not a
submodule. The Swift files at the top of this directory (`Ndb.swift`,
`NdbFilter.swift`, `NdbNote.swift`, `NdbTxn.swift`, the iterators, `Test/`, …)
are **damus-local** — upstream is C-only. Everything under `src/`, `ccan/` and
`flatcc/` comes from upstream.

## Currently synced to

Upstream `master` at **1b42298990a8** ("query: let author_kinds serve
multi-author filters").

## damus-local divergence from that commit

These are the only intentional differences. All of them except the
`sodium/` shim and the build-layout edits are damus bug fixes that should be
upstreamed rather than carried here forever.

| Where | What | Origin |
| --- | --- | --- |
| `src/sodium/` | Minimal ChaCha20-IETF providing `crypto_stream_chacha20_ietf_xor_ic`, the only libsodium symbol `src/nip44.c` uses. Upstream links all of `deps/libsodium`; vendoring that into the Xcode project would pull in its build system, CPU dispatch, randombytes and utils layers for one stream cipher. Validated against nostrdb's own NIP-44 test vectors. | damus-local |
| `src/nostrdb.c` | Debug-only watchdog that registers read transactions in `_ndb_begin_query` keyed by owning `struct ndb_lmdb`, clears them in `ndb_end_query` and per-env in `ndb_destroy`, and aborts with the opening stack trace if one stays open past 3s. `#ifdef DEBUG` only. | `21ea74469b8f` and its follow-ups |
| `src/nostrdb.c` | `ndb_note_to_blocks` passes the real buffer size (`2<<18`) to `ndb_parse_content`; upstream passes `content_len` as the buffer size. | `12a7b483a0ed` |
| `src/nostrdb.h`, `src/nostr_bech32.c` | `kind`/`has_kind` on `bech32_nevent` and `bech32_nprofile`, `kind` on `bech32_naddr`, the `nostr_bech32_t` typedef, and `TLV_KIND` parsing (naddr additionally requires a kind). Consumed by `Bech32Object.swift`. | `d8e7b4707e7e` |
| `src/block.c` | `assert(blocks->total_size < 1000000)` in `ndb_blocks_total_size`. | `919f644cba93` |
| `src/content_parser.c` | `MAX_PREFIX` 8 → 9 (room for the NUL), a null-terminated copy of the invoice string before `bolt11_decode_minimal`, and `blocks_size` measured from the buffer start rather than `blocks_start`. | `fae061cec0e1`, `05b62c5860e8`, `b9d8b1dbf364` |
| `src/bolt11/bech32.c` | `bech32_decode` derives the max HRP length from the input length instead of a constant, and `bech32_decode_len` reserves a byte for the NUL. Supersedes upstream's `8 -> 10` bump. | `5b6534fd566c` |
| `src/bolt11/bolt11.c` | NULL `fail` guard in `decode_fail`; `len < 8` guard against underflow in `bech32_decode_alloc`. | `05b62c5860e8` |
| `src/bindings/c/*.h`, `src/bindings/swift/*.swift` | Build-layout edits: the `flatcc/` prefix is stripped from includes (flatcc is flattened into `nostrdb/flatcc/` here) and `import FlatBuffers` is removed. | `copy-ndb` |

Not vendored: `src/giftwrap.c` (present upstream but absent from its `SRCS` and
does not compile) and `src/configurator.c` (`src/config.h` is checked in).

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

Then add any new `src/*.c` to the four `Sources` build phases that already
compile `nostrdb.c` (damus, damusTests, DamusNotificationService and the
share/highlighter extensions), rebuild, and run both `just test` and upstream's
`make check` on the merged tree.
