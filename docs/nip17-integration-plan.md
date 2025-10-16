NIP-17 Integration Plan
=======================

Goal
----

Add first-class support for NIP-17 encrypted direct messages by pushing the heavy lifting (gift-wrap parsing, seal verification, room indexing) into `nostrdb` while keeping the Swift UI/API surface close to the existing NIP-04 implementation.

Scope
-----

- Support ingesting, storing, and querying gift wraps (`kind:1059`), seals (`kind:13`), and unsigned chat/file messages (`kind:14`/`kind:15`) in `nostrdb`.
- Surface decrypted chat/file events to Swift as `NostrEvent`s, keeping parity with the current DM timeline and notification logic.
- Handle per-recipient relay preferences (`kind:10050`) when publishing.

Architecture Changes
--------------------

### 1. `nostrdb` Event Handling

- **Common kind expansion:** extend `ndb_kind_to_common_kind` / `ndb_kind_name` to include `seal`, `chat_dm`, `file_dm`, `giftwrap`, and `dm_relay_list`.
- **Gift wrap ingestion path:**
  - Accept & verify signed `kind:1059` events as-is (signature check already passes with random key).
  - Parse tags once, extract recipient pubkeys and optional aliases.
  - Store the raw ciphertext payload keyed by event id.
  - New metadata record: `struct ndb_dm17_envelope { uint64_t note_key; uint32_t created_at; uint32_t sender_align; uint8_t recipient_count; … }` persisted in a dedicated database (`NDB_DB_DM17_ENVELOPES`).
- **Seal + message cache:**
  - On-demand decrypt the `kind:1059` payload using the recipient private key (provided via new `ndb_set_dm_keyring` API). Cache the intermediate seal (`kind:13`) and final message (`kind:14/15`) in `NDB_DB_DM17_CACHE`.
  - Persist: validated sender pubkey, conversation room hash (sorted pubkeys), plaintext bytes (for 14) or file descriptor (for 15), plus verification flags (e.g. `auth_ok`, `schema_ok`).
  - Reuse cache in subsequent lookups to avoid repeat decryption.
- **Unsigned event synthesis:**
  - Represent decrypted 14/15 messages internally using existing `ndb_note` layout with `sig` zeroed.
  - Skip signature verification via ingest filter for `kind` 14/15 when the source is a trusted DM cache. Mark note origin to avoid external injection.

### 2. Key Management Bridge

- Introduce `ndb_dm_key` struct storing pubkey/private key pairs (including alias keys). Offer Swift-facing API:
  - `ndb_reset_dm_keyring(ndb, keys[], count)` to atomically refresh keys.
  - Keys live only in memory (wiped on `ndb_close`).
  - Optionally support per-recipient override for sealed gifts that use alias key distinct from main key.

### 3. Query APIs

- New C helpers for Swift:
  - `ndb_dm17_fetch_room_messages(txn, room_hash, limit, after_timestamp)` returning materialised `ndb_note` handles for decrypted messages.
  - `ndb_dm17_list_rooms(txn)` returning summaries by `room_hash` sorted by latest message timestamp, enabling quick DM list rendering.
  - `ndb_dm17_resolve_giftwrap(txn, note_id)` giving access to cached plaintext + metadata for debugging or resend.
- Extend existing tag iterators to expose DM17-specific metadata (room hash, participants, subject tag).

### 4. Migration / Storage Layout

- Schema version bump in `NdbMeta`.
- `NDB_DB_DM17_ENVELOPES` (key: giftwrap note key -> value: envelope metadata).
- `NDB_DB_DM17_CACHE` (key: room hash + created_at + sender pubkey -> value: serialized 14/15 payload + auth flags).
- Background migration to prefill cache for existing stored gift wraps, throttled to avoid UI stalls.

Swift-Side Updates
------------------

- Extend `NostrKind` with `.dmChat17`, `.dmFile17`, `.giftWrap`, `.seal`, `.dmRelayPreferences`.
- Update `DirectMessagesModel` to consume `ndb_dm17_list_rooms` and fetch messages via new APIs instead of manually aggregating `NostrEvent`s.
- Introduce `DM17Service` that coordinates:
  - Sending: compose unsigned 14/15 event, call into `nostrdb` helper to build seal+gift wraps, enqueue to relay layer.
  - Receiving: subscribe to `kind:1059` events, pass to `Ndb` for ingestion (decryption happens automatically once keys available), observe callbacks to refresh Swift models.
- Maintain compatibility with legacy NIP-04 by gradually migrating UI references to new service (dual-mode until all relays/users migrate).

Swift Pipeline Details
----------------------

- **State management (`DamusState`):**
  - Add a shared `DM17Service` responsible for keyring sync, room snapshots, and background cache rebuilds.
  - Expose lightweight room/message publishers so `DirectMessagesModel` can stay as the UI-facing observable.

- **Message composition:**
  - Update DM composer to build unsigned 14 payloads (plain text) or 15 payload descriptors (file metadata, encryption material).
  - Service returns progress handles for per-recipient sending (enqueue, relay ack, failure states) to drive UI toasts/spinners.

- **Decryption consumption:**
  - `DM17Service` listens for NDB subscription callbacks signalling new decrypted cache entries.
  - Converts `ndb_note` handles into `NostrEvent` wrappers (including subject, participants) and updates `DirectMessagesModel`.
  - Supports pagination through room-specific cursors backed by `ndb_dm17_fetch_room_messages`.

- **Keyring sync:**
  - On login, key rotation, or alias changes, refresh keyring via `ndb_reset_dm_keyring`.
  - Trigger reprocessing of stored envelopes that previously failed to decrypt.

- **Drafts & attachments:**
  - Tag drafts with DM17 room hash/version so unsent NIP-04 drafts remain untouched.
  - Extend attachment pipeline to store encrypted file metadata (nonce/key) alongside upload task.

- **Notification bridge:**
  - Reuse existing notification generation pipeline by mapping DM17 events into `NostrEvent` before calling `handle_incoming_dm`.
  - Include gift wrap id in notification payload for quick jump-to-message handling.

Networking Strategy
-------------------

- **Relay preference discovery (`kind:10050`):**
  - Extend `RelayPool` bootstrap to request `kind:10050` for our pubkey and known contacts.
  - Cache preferred inbox relays in `Contacts`/`Profiles`.
  - Provide helper `preferred_dm_relays(for pubkey)` combining 10050 results with fallbacks (mutual relays / default set).

- **Gift wrap subscriptions:**
  - Replace existing DM subscriptions (`kind:4`) with `kind:1059` filtered by:
    - `#p` tag matching any of our DM aliases.
    - Authors optionally limited to trusted sets when `friend_filter` enabled.
  - Support ephemeral alias rotation by re-subscribing when the keyring changes.

- **Publishing workflow:**
  - When sending, query each recipient’s `kind:10050` relay list.
  - Publish generated gift wrap (`kind:1059`) individually per relay and per recipient, plus self-copy.
  - Maintain retry queue per relay with exponential backoff; track `pub`/`ok` acknowledgements.

- **Backfill / replay:**
  - On startup, request `kind:1059` from preferred DM relays limited by timestamp/limit.
  - Provide manual re-sync hook (pull last N days) for debugging mismatched histories.

- **Compatibility:**
  - Continue to subscribe to `kind:4` behind feature flag until rollout complete.
  - Add heuristics to prioritise relays that simultaneously advertise NIP-17 support.

Performance Considerations
--------------------------

- Decryption happens once per gift wrap and is cached in LMDB (plain text encrypted at rest by platform facilities if available).
- Room queries rely on precomputed `room_hash` secondary indexes for O(log n) fetch.
- Background seal verification uses ingest thread pool; results reported via existing subscription callback pipeline.

Open Questions
--------------

1. How to handle gift wraps addressed to alias keys unknown at ingest time? ⇒ Store envelope, attempt decryption whenever keyring updates.
2. Should plaintext cache be encrypted at rest? ⇒ Investigate leveraging iOS data protection classes or keep plaintext ephemeral in memory with on-disk re-encryption using application key.
3. File messages (kind 15) may require large payload handling; confirm cache size limits and streaming strategy.

Testing, Migration, and Rollout
-------------------------------

- **Unit coverage:**
  - C tests for seal->giftwrap roundtrip, keyring rotation, room hashing, cache serialization.
  - Swift tests covering DM17 service send/receive, pagination, notification payload creation, migration of drafts.
- **Integration scenarios:**
  - Simulated relay delivering mixed NIP-04 + NIP-17 events.
  - Alias key adoption mid-conversation (ensure old wraps decrypt once key added).
  - File transfer handshake verifying MIME metadata propagates correctly.
- **Migration:**
  - Database migration guard ensures new buckets created once; fallback to read-only mode if upgrade fails.
  - Background task enumerates stored gift wraps, attempts decrypt using latest keyring, populates cache without blocking UI.
  - Persist flag indicating DM17 cache ready to avoid repeated migrations.
- **Rollout:**
  - Feature flag toggled via remote config or build setting; dual-stack mode keeps NIP-04 active until confidence high.
  - Telemetry counters for decrypt failures, cache misses, relay publish latency, and fallback to NIP-04.
  - Provide manual “Rebuild DM Cache” developer setting for debugging.

Next Steps
----------

1. Prototype new LMDB buckets and caching logic in `nostrdb`, including keyring bridge.
2. Wire Swift `DamusState` to keep keyring synced with `nostrdb`.
3. Replace DM timeline data source with DM17-backed queries guarded by feature flag.
4. Add migration jobs + background workers to backfill caches for stored gift wraps.
5. Build comprehensive tests: C unit tests for decrypt/verify pipeline, Swift integration tests for send/receive roundtrips.
6. Stage rollout via feature flag; collect telemetry on decrypt failures and relay delivery latency.
