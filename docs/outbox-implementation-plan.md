# iOS Damus Outbox Model Implementation Plan

## Context

**Problem:** Damus iOS currently broadcasts all subscriptions to all connected relays and fetches from the same flat list. This means:
- Events from users on personal/niche relays are missed entirely
- Subscription load scales poorly (every relay gets every filter)
- Publishing doesn't reach tagged users' preferred relays
- Users must manually manage relay configuration

**Prompt:** damus-io/damus#423 ("Autopilot mode / Outbox model") calls for outbox-based relay routing so Damus "just works." jb55 confirmed this is the direction: *"I built nostrdb specifically to support the outbox model."* Notedeck PR #1288 landed the outbox infrastructure for the Rust/desktop client.

**Goal:** Produce a detailed, externally reviewable implementation plan that adapts the notedeck outbox architecture to iOS Damus's Swift/async-await paradigm, leveraging the substantial existing infrastructure.

**NIPs reviewed:** 01, 05, 10, 11, 17, 19, 42, 51, 65, 66, 70.

---

## What iOS Damus Already Has (Foundations)

| Component | File | Outbox-Relevant Capability |
|-----------|------|---------------------------|
| `RelayPool` | `damus/Core/Nostr/RelayPool.swift` | Ephemeral relay management (`acquireEphemeralRelays`, `releaseEphemeralRelays`, `ensureConnected`), reference-counted leases |
| `SubscriptionManager` | `damus/Core/Networking/NostrNetworkManager/SubscriptionManager.swift` | Relay-hint-aware `lookup(noteId:)` with ephemeral connections, `advancedStream` with multiple stream modes |
| `NIP65` | `damus/Core/NIPs/NIP65/NIP65.swift` | Full kind:10002 parsing with `RelayList`, `RelayItem`, `RWConfiguration` (read/write/readWrite) |
| `PostBox` | `damus/Features/Posting/Models/PostBox.swift` | Retry with backoff, delayed sends, per-relay tracking |
| `TagSequence` relay hints | `nostrdb/NdbTagIterator.swift` | Extracts relay hints from tag position 2 |
| `Bech32Object` | `damus/Shared/Utilities/Bech32Object.swift` | NIP-19 relay hints from nevent/nprofile/naddr (multi-relay, tolerant of unknown TLVs per NIP-19) |
| `RelayAuthenticationState` | `damus/Core/Nostr/Relay.swift:80` | NIP-42 auth state tracking (none/pending/verified/error), challenge handling |
| `Limitations` struct | `damus/Core/Nostr/Relay.swift:91` | Exists but minimal — only `payment_required`. **Needs expansion.** |
| Relay hints tests | `damusTests/RelayHintsTests.swift` | 11 test cases covering ephemeral relay management and hint-based fetching |

### Identified Gaps

| Gap | Impact | NIP |
|-----|--------|-----|
| No kind:10050 DM relay handling | DM delivery would use wrong relays | NIP-17 |
| No kind:10006 blocked relay list | Outbox could dial relays user explicitly blocked | NIP-51 |
| No CLOSED message handling | Can't retry auth-required subs or handle server-side termination | NIP-01, NIP-42 |
| `Limitations` struct is minimal | Can't enforce max_subscriptions, max_message_length, etc. | NIP-11 |
| No machine-readable prefix parsing on OK/CLOSED | Can't distinguish auth-required vs rate-limited vs blocked | NIP-01, NIP-42 |
| No NIP-05 relay hint fallback | Missing bootstrap path when kind:10002 unavailable | NIP-05 |
| No NIP-70 protected event awareness | Write path could fail silently on `["-"]` events without auth | NIP-70 |

**Key insight:** The lookup path (single-event fetch with relay hints) already works end-to-end. What's missing is the **feed path** (multi-author timeline subscriptions routed per-author), the **write path** (publishing to tagged users' inboxes, split by event class), and **relay protocol compliance** (CLOSED handling, auth retry, limits enforcement).

---

## Notedeck PR #1288 Architecture (What We're Adapting)

The notedeck outbox system (6931 additions) introduces a layered architecture:

```
App Layer (Damus/Columns)
    └── RelayPool wrapper (convenience: subscribe/broadcast using account relay set)
        └── OutboxSessionHandler (RAII session, batches mutations per frame)
            └── OutboxPool (owns all coordinators, global subscription registry)
                └── CoordinationData (per-relay orchestrator)
                    ├── CompactionRelay (packs N outbox subs into few REQs, default)
                    ├── TransparentRelay (1:1 outbox sub → REQ, for EOSE-sensitive subs)
                    ├── BroadcastRelay (EVENT sending with offline queue)
                    └── SubPassGuardian (enforces NIP-11 max_subscriptions)
```

### Key Concepts to Port

1. **OutboxSubscriptions** — Global registry mapping subscription IDs to their filters + relay sets. Tracks JSON size for compaction bin-packing. Supports `since_optimize()` after EOSE.

2. **SubPass accounting** — Each relay has a limited number of subscription slots (NIP-11 `max_subscriptions`, default 10). Passes are tokens that must be held to send a REQ. Compaction and transparent modes compete for passes.

3. **CompactionRelay** — Packs multiple outbox subscriptions into fewer websocket REQs by combining filters, respecting `max_json_bytes` per message. When full, queues excess subs. Can compact (merge smallest REQs) to free a pass.

4. **TransparentRelay** — 1:1 mapping for subs that need independent EOSE (e.g., timeline initial load). Uses dedicated passes. As kernelkind explains: *"guaranteed that the relay subscription the OutboxSubId uses is not used by any other OutboxSubId subscriptions."*

5. **QueuedTasks** — `BTreeSet` of deferred subscription IDs when no passes available. Drained when passes are freed. Per kernelkind: *"things are queued when we hit [NIP-11] limitations."*

6. **Relay selection** (not in PR, but from hzrd149/community): Greedy set-cover algorithm — calculate relay popularity from kind:10002, limit each user to 2 relays, greedily pick relay covering most uncovered users.

### What Doesn't Apply to iOS

- **Per-frame session batching** — Notedeck uses Rust RAII (Drop). iOS uses async/await with explicit calls.
- **Multicast (LAN relay)** — Desktop-only feature.
- **Wakeup trait** — egui-specific. iOS uses `@MainActor` and async notifications.
- **BroadcastRelay offline queue** — iOS `PostBox` already handles this with retry/backoff.

---

## Proposed Architecture for iOS Damus

### Layer 1: OutboxRelayResolver (New)
**Purpose:** Maintains a cache of relay preferences per pubkey from multiple sources: kind:10002 (NIP-65), kind:10050 (NIP-17 DM relays), NIP-05 hints, and kind:10006 (NIP-51 blocked relays as denylist).

```
Actor: OutboxRelayResolver
├── relayListCache: [Pubkey: NIP65.RelayList]         // kind:10002
├── dmRelayCache: [Pubkey: [RelayURL]]                // kind:10050
├── nip05RelayCache: [Pubkey: [RelayURL]]             // from /.well-known/nostr.json
├── blockedRelays: Set<RelayURL>                       // kind:10006 for current user
│
├── resolveWriteRelays(for: Pubkey) -> [RelayURL]     // where to fetch FROM a user (their 10002 write relays)
├── resolveReadRelays(for: Pubkey) -> [RelayURL]      // where to send TO reach a user (their 10002 read relays / inbox)
├── resolveDMRelays(for: Pubkey) -> [RelayURL]?       // kind:10050 relays, nil = not ready for NIP-17
├── resolveWriteRelays(for: [Pubkey]) -> [Pubkey: [RelayURL]]  // batch
│
├── refreshFromNdb(ndb: Ndb, pubkeys: [Pubkey])       // query NostrDB for kind:10002 + kind:10050
├── refreshFromNip05(pubkey: Pubkey, nip05: String)    // fetch /.well-known/nostr.json relay hints
├── loadBlockedRelays(ndb: Ndb, user: Pubkey)          // load kind:10006 for current user
├── invalidate(pubkey: Pubkey)                          // on new kind:10002/10050 event
│
├── isBlocked(relay: RelayURL) -> Bool                  // check user's kind:10006 denylist
└── fallbackRelays(for: Pubkey) -> [RelayURL]          // cascade: 10002 → NIP-05 → empty
```

**File:** `damus/Core/Networking/OutboxRelayResolver.swift` (new)

**Dependencies:** `NIP65.swift` (exists), `Ndb` (exists)

**Design notes:**
- Actor-isolated for thread safety (like `RelayPoolActor`)
- Lazily populates on first request per pubkey
- Watches for new kind:10002 and kind:10050 events to invalidate
- Returns empty array for unknown pubkeys (caller falls back to user's relays)
- NIP-05 relay hints used as fallback when kind:10002 unavailable — helpful for first-run bootstrap
- **All relay resolution filters through `isBlocked()` denylist** from kind:10006 (NIP-51)
- NIP-10 pubkey hints on `e` tags used as outbox fallback: if relay hint fails, resolve via the pubkey's write relays

### Layer 2: OutboxRelaySelector (New)
**Purpose:** Given a set of pubkeys and their relay preferences, computes a minimal relay set while respecting the user's blocked relay list.

```
struct OutboxRelaySelector
├── selectRelays(
│     authorRelays: [Pubkey: [RelayURL]],
│     userRelays: [RelayURL],           // user's own configured relays
│     blockedRelays: Set<RelayURL>,     // kind:10006 denylist
│     maxConnections: Int = 8           // configurable limit
│   ) -> RelayPlan
└── RelayPlan:
      ├── relayAssignments: [RelayURL: Set<Pubkey>]  // which authors on which relay
      ├── fallbackAuthors: Set<Pubkey>                 // authors with no known relays → use user's relays
      └── totalRelays: Int
```

**File:** `damus/Core/Networking/OutboxRelaySelector.swift` (new)

**Algorithm (adapted from hzrd149):**
1. **Filter:** Remove all `blockedRelays` from candidate relays
2. For each pubkey, get their write relays, **hard-capped to `maxRelaysPerAuthor` (2)** after filtering
3. Count relay popularity across all pubkeys
4. Greedily: pick relay covering most uncovered pubkeys, assign them
5. Repeat until all covered or `maxConnections` hit
6. Remaining pubkeys → `fallbackAuthors` (query on user's own relays)

**Design notes:**
- Pure function, no state, easily testable
- `maxConnections` prevents opening too many ephemeral connections on mobile
- `maxRelaysPerAuthor` (hard cap = 2) prevents hostile kind:10002 lists with 30+ relays from inflating the plan
- User's own relays always included (they serve as hubs)
- **Blocked relays never dialed** — filtered at selection time
- All budget constants defined in `OutboxBudget` (see Design Decision #8)

### Layer 3: Effective Relay Policy / NIP-11 (New)
**Purpose:** Fetch, cache, and enforce full NIP-11 relay information. Not just `max_subscriptions` — the full effective policy that controls what the client can do with each relay.

```
Actor: RelayPolicyCache
├── cache: [RelayURL: RelayPolicy]
├── fetchPolicy(relay: RelayURL) async -> RelayPolicy?
│
├── RelayPolicy: Codable
│     ├── maxSubscriptions: Int?          // NIP-11 limitation.max_subscriptions
│     ├── maxMessageLength: Int?          // limitation.max_message_length
│     ├── maxLimit: Int?                  // limitation.max_limit (filter limit clamp)
│     ├── defaultLimit: Int?              // limitation.default_limit
│     ├── authRequired: Bool              // limitation.auth_required
│     ├── paymentRequired: Bool           // limitation.payment_required
│     ├── restrictedWrites: Bool          // limitation.restricted_writes
│     ├── supportedNips: [Int]            // for capability detection
│     └── raw: [String: Any]?            // full JSON for future use
│
├── effectiveLimit(relay: RelayURL, requestedLimit: Int?) -> Int  // clamp to max_limit
├── canWrite(relay: RelayURL) -> Bool                              // !restricted_writes || authenticated
├── needsAuth(relay: RelayURL) -> Bool                             // auth_required
├── maxMessageBytes(relay: RelayURL) -> Int                        // for filter JSON size budgets
│
└── Subscription Slot Tracking (per relay):
      ├── activeSubscriptions: [RelayURL: Int]
      ├── acquireSlot(relay: RelayURL) -> Bool          // false if at max_subscriptions
      ├── releaseSlot(relay: RelayURL)
      └── queuedSubscriptions: [RelayURL: [(filters, continuation)]]  // QueuedTasks analog
```

**File:** `damus/Core/Networking/RelayPolicyCache.swift` (new)

**Also modify:** `damus/Core/Nostr/Relay.swift` — expand `Limitations` struct to match full NIP-11 `limitation` object.

#### NIP-11 Fetch Operational Specification

```
Fetch Behavior:
├── Trigger: on first connection to any relay (user-configured or ephemeral)
│   Fetch is async and non-blocking — subscriptions proceed with defaults while fetch is in-flight.
├── HTTP request: GET <relay_http_url> with Accept: application/nostr+json
│   where <relay_http_url> is the relay WebSocket URL converted by scheme only:
│   - wss://... -> https://...
│   - ws://...  -> http://...
│   and preserving host, port, and path exactly.
│   Example: wss://relay.example.com/nostr -> https://relay.example.com/nostr
│   (NIP-11: same URI as websocket endpoint, over HTTP(S))
├── URL conversion helper (normative):
│   Input: relayWebSocketURL: String
│   Steps:
│   1. Parse as URL; if invalid -> skip NIP-11 fetch, use defaults.
│   2. If scheme == "wss", set scheme = "https".
│   3. If scheme == "ws",  set scheme = "http".
│   4. For any other scheme, skip NIP-11 fetch, use defaults.
│   5. Preserve authority (host + optional port), path, and query exactly.
│   6. Preserve trailing slash semantics (no path normalization rewrite).
│   Output: converted HTTP(S) URL string used for GET with Accept: application/nostr+json.
│
│   Examples:
│   - wss://relay.example.com         -> https://relay.example.com
│   - wss://relay.example.com/nostr   -> https://relay.example.com/nostr
│   - wss://relay.example.com/ws?v=1  -> https://relay.example.com/ws?v=1
│   - ws://127.0.0.1:7000/            -> http://127.0.0.1:7000/
├── Timeout: 5 seconds. If exceeded, treat as fetch failure.
├── Concurrency: max 4 concurrent NIP-11 fetches. Excess queued FIFO, drained as fetches complete.
│   Prevents burst of HTTP requests when many ephemeral relays connect simultaneously.
├── Cache TTL: 6 hours for user-configured relays (long-lived connections).
│   Ephemeral relays: cache retained for 10 minutes after lease released (grace window).
│   If reconnected within grace window, reuse cached policy without re-fetch.
│   After grace window expires, evict from cache.
│   Rationale: many ephemeral relays are reconnected within minutes (e.g., scrolling
│   through feed triggers the same author's relay multiple times). Grace window prevents
│   fetch churn without unbounded cache growth.
├── Retry on failure: no retry. Use defaults until next natural re-fetch opportunity (reconnect or TTL expiry).
│   Rationale: NIP-11 is optimization, not correctness. Silent fallback to defaults is safe.

Default Fallback Values (when fetch fails or field is null):
├── maxSubscriptions: 20         // conservative; most relays allow 10-100
├── maxMessageLength: 131072     // 128 KB; conservative default to reduce early rejection risk
├── maxLimit: 5000               // safe upper bound for filter limit
├── defaultLimit: 100            // reasonable page size
├── authRequired: false          // assume open relay
├── paymentRequired: false       // assume free relay
├── restrictedWrites: false      // assume open writes
├── supportedNips: []            // assume no declared support
```

These defaults are deliberately **conservative but permissive**: conservative for message size (don't overwhelm relay), permissive for access (don't self-restrict). The client will learn actual limits from CLOSED/OK responses at runtime even without NIP-11.

**Integration points:**
- `SubscriptionManager` checks `acquireSlot` before opening new subs. If at limit, queues the subscription. When a sub closes (`releaseSlot`), flushes the queue.
- `outboxStream` respects `maxMessageBytes` when building per-relay filters (don't exceed relay's `max_message_length`)
- `effectiveLimit` applied to all filters before sending (relay would silently clamp anyway, but this lets the client know the true limit)
- Adaptive downshift: if relay responds with CLOSED/OK invalid/error indicating message/filter too large,
  reduce cached maxMessageBytes for that relay (e.g., halve, floor at 16 KB) for the session.

### Layer 4: Auth Orchestration & CLOSED Handling (New + Modify)
**Purpose:** Handle NIP-42 auth retry flow for both REQ and EVENT, and handle CLOSED messages with machine-readable prefix branching.

#### 4a: CLOSED Message Support

Currently, iOS Damus parses OK and AUTH but **does not parse CLOSED messages**. This must be added.

```
// New in NostrResponse.swift:
case closed(ClosedResult)

struct ClosedResult {
    let subscriptionId: String
    let message: String
    var prefix: MachineReadablePrefix?     // parsed from message
}

enum MachineReadablePrefix: String {
    case authRequired = "auth-required"
    case restricted = "restricted"
    case duplicate = "duplicate"
    case pow = "pow"
    case blocked = "blocked"
    case rateLimited = "rate-limited"
    case invalid = "invalid"
    case error = "error"
    case mute = "mute"
}
```

**Files to modify:**
- `damus/Core/Nostr/NostrResponse.swift` — add `closed` case and `MachineReadablePrefix` parsing
- `damus/Core/Nostr/RelayPool.swift` — handle CLOSED in the message dispatch loop

#### 4b: Auth Retry Orchestrator

```
Enhancement to RelayPool / SubscriptionManager:

On CLOSED with "auth-required:" prefix:
  1. Check if relay has sent AUTH challenge (stored per-relay in RelayAuthenticationState)
  2. If challenge available and we have keypair:
     a. Sign kind:22242 auth event with relay URL + challenge tags
     b. Send ["AUTH", <signed-event>]
     c. Wait for ["OK", ..., true, ...]
     d. Re-send the original REQ that was CLOSED
  3. If no keypair (read-only user): log warning, skip this relay
  4. If already verified but got "restricted:": relay rejected our key, don't retry

On OK with "auth-required:" prefix (for EVENT sends):
  1. Same auth flow as above
  2. Re-send the EVENT after successful auth
  3. If NIP-70 protected event (["-"] tag) and auth fails: warn user, don't retry on this relay
```

**Files to modify:**
- `damus/Core/Nostr/RelayPool.swift` — add CLOSED dispatch, auth retry on CLOSED/OK
- `damus/Core/Nostr/Relay.swift` — store challenge string per relay (already has `RelayAuthenticationState`, may need to add `lastChallenge: String?`)

**NIP-70 awareness:** When the write path sends a protected event (contains `["-"]` tag), it MUST ensure the target relay is NIP-42 authenticated first, or skip that relay with a warning. Most relays reject `["-"]` events from unauthenticated senders.

### Layer 5: Feed-Level Outbox Routing (Enhancement to SubscriptionManager)
**Purpose:** Route timeline/feed subscriptions through the outbox relay resolver and selector.

```
Extension on SubscriptionManager:
├── outboxStream(
│     filters: [NostrFilter],
│     resolver: OutboxRelayResolver,
│     selector: OutboxRelaySelector,
│     timeout: Duration?,
│     streamMode: StreamMode?
│   ) -> AsyncStream<NdbNoteLender>
│
│   Implementation:
│   1. Extract author pubkeys from filters
│   2. Resolve relay preferences via OutboxRelayResolver (cascading: 10002 → NIP-05 → empty)
│   3. Compute relay plan via OutboxRelaySelector (respects blocked relays, maxConnections)
│   4. For each relay in plan:
│      a. Build author-scoped filter (original filter + only this relay's assigned authors)
│      b. Check RelayPolicyCache: acquireSlot, clamp limit, check maxMessageBytes for filter JSON
│      c. Acquire ephemeral relay lease
│      d. If relay needs auth (NIP-11 auth_required): trigger auth flow before subscribing
│      e. Subscribe to that relay with scoped filter
│   5. For fallback authors: subscribe on user's relays
│   6. Merge all streams into single output
│   7. On per-relay EOSE: apply since-optimization for future re-subscriptions
│   8. On CLOSED with auth-required: trigger auth retry flow (Layer 4b)
│   9. Release leases on cancellation/completion, releaseSlot on unsubscribe
│
│   NIP-10 fallback: When a relay hint on an `e` tag doesn't resolve the event,
│   use the `<pubkey>` from the tag to look up that author's write relays and try those next.
```

**File:** `damus/Core/Networking/NostrNetworkManager/SubscriptionManager.swift` (modify)

**Design notes:**
- Builds on existing `pool.subscribe(filters:to:)` with relay targeting
- Builds on existing ephemeral relay management (`acquireEphemeralRelays`)
- Each sub-subscription gets its own EOSE tracking (like notedeck transparent mode)
- Since-optimization applied per relay after EOSE (like notedeck `MetadataFilters.since_optimize`)
- Filter JSON size checked against `maxMessageBytes` before sending

### Layer 6: Write-Side Routing — Split by Event Class (Enhancement to PostBox/NostrNetworkManager)
**Purpose:** Route published events to the right relays based on event type.

**Critical distinction:** Write routing MUST be split by event class:

```
Enhancement to NostrNetworkManager.send(event:):

ROUTING POLICY BY EVENT CLASS:

1. Normal notes (kind:1, etc.) with p-tags:
   a. Send to author's WRITE relays (from kind:10002)
   b. Send to each tagged user's READ relays (from kind:10002) — "inbox delivery"
   c. Republish author's kind:10002 per dedup policy in Design Decision #10
      (to all target relays, deduplicated by per-relay sent-state)

2. NIP-17 DM giftwrap (kind:1059):
   a. Resolve recipient's kind:10050 DM relay list (NOT kind:10002!)
   b. If 10050 found: send ONLY to those relays
   c. If 10050 NOT found: DO NOT SEND — recipient not ready for NIP-17
   d. Log warning for missing 10050 so user/developer can see delivery failure reason

3. Protected events (contains ["-"] tag, NIP-70):
   a. For each target relay: ensure NIP-42 auth completed first
   b. If auth fails or not possible: skip relay, warn user
   c. Relay will reject ["-"] events from unauthenticated senders

4. Events without p-tags (kind:1 root posts, etc.):
   a. Send to author's WRITE relays only
   b. Republish author's kind:10002 per dedup policy in Design Decision #10

For ALL event classes:
   - Filter target relays through blockedRelays denylist (kind:10006)
   - Handle OK "auth-required:" responses with auth retry (Layer 4b)
   - Handle OK "restricted:" responses by skipping relay (already authed but rejected)
```

**Files to modify:**
- `damus/Core/Networking/NostrNetworkManager/NostrNetworkManager.swift`
- `damus/Features/Posting/Models/PostBox.swift` (add event-class-aware relay resolution)

### Layer 7: Autopilot Toggle & Settings UI
**Purpose:** User-facing setting to enable/disable outbox routing.

- Default: **enabled** (outbox active, app "just works")
- When disabled: all subscriptions broadcast to user's configured relays only (current behavior)
- Setting stored in UserDefaults via existing settings infrastructure

**File:** `damus/Features/Settings/` (modify existing relay settings view)

---

## Implementation Order & Dependencies

```
Phase 0 (Protocol Compliance — unblocks everything):
  CLOSED message parsing + MachineReadablePrefix              ← no deps, small change
  Expand Limitations struct to full NIP-11                    ← no deps, small change

Phase 1 (Foundation):
  OutboxRelayResolver                                         ← no deps, start here
       includes: kind:10002, kind:10050, kind:10006, NIP-05 fallback
  Tests: resolver + selector                                  ← depends on resolver, selector

Phase 2 (Selection + Policy):
  RelaySelector algorithm                                     ← depends on resolver
  RelayPolicyCache (full NIP-11)                              ← depends on Phase 0
  Auth orchestrator + CLOSED retry                            ← depends on Phase 0
  Tests: CLOSED parsing + NIP-11 policy                       ← depends on CLOSED parsing, policy cache

Phase 3 (Core Integration):
  Feed-level outbox routing                                   ← depends on resolver + selector + policy + auth
  Tests: auth retry + feed routing                            ← depends on auth orchestrator, feed routing

Phase 4 (Write Path):
  Write-side routing (split by event class)                   ← depends on resolver + auth
  Tests: write-side routing + stress                          ← depends on write routing

Phase 5 (Polish):
  Autopilot toggle UI                                         ← depends on feed routing
```

---

## Key Design Decisions

### 1. Actor vs Session Model
**Notedeck:** Per-frame session batching with RAII Drop flush (Rust immediate-mode GUI).
**iOS Damus:** Actor-isolated components with async/await. No session batching needed — each subscription call is already async and can directly interact with the pool.

### 2. Compaction Strategy
**Notedeck:** Complex bin-packing of multiple outbox subs into shared REQ messages with pass accounting.
**iOS Damus (proposed):** Simpler per-relay filter splitting. Instead of packing N logical subs into M physical REQs, we split one logical subscription into N per-relay subscriptions each with a smaller author list. This is simpler and fits the existing `pool.subscribe(filters:to:)` API. The relay selection algorithm handles the "minimize connections" concern at a higher level.

**Trade-off:** Less optimal subscription slot usage per relay, but dramatically simpler code. If NIP-11 limits become a problem in practice, the subscription slot tracking in `RelayPolicyCache` provides the foundation for compaction later.

### 3. DM vs Generic Routing (Critical)
**Write routing is NOT one-size-fits-all.** NIP-17 DM giftwrap (kind:1059) MUST use kind:10050 DM relays, NOT kind:10002 read relays. If kind:10050 is missing, the client must not attempt delivery — the recipient isn't ready for NIP-17. This is explicitly stated in NIP-17.

### 4. Relay Scoring
**Start without scoring.** Use kind:10002 as truth, NIP-05 as fallback. Add scoring in a follow-up if needed (track which relays actually return events vs timeout). NIP-66 (relay monitor events kind:30166) could provide liveness/RTT data for future scoring.

### 5. Connection Limits
**Concern:** Opening connections to many ephemeral relays could be expensive on mobile.
**Mitigation:** `maxConnections` parameter on `OutboxRelaySelector` (default 8). Long-tail authors fall back to user's own relays. Ephemeral connections are reference-counted and released when subscriptions end.

### 6. Auth-Required Relay Handling
Outbox will inevitably connect to relays that require NIP-42 authentication. The client must:
- Store the AUTH challenge per relay (already tracked in `RelayAuthenticationState`)
- On `CLOSED "auth-required: ..."`: sign kind:22242, send AUTH, re-send REQ
- On `OK false "auth-required: ..."`: sign kind:22242, send AUTH, re-send EVENT
- On `"restricted: "`: relay rejected our key even after auth — don't retry, skip relay
- Per NIP-42: *"the client must have a stored challenge associated with that relay"*

### 7. CLOSED Handling — Explicit State Machine

CLOSED is not parsed in the current codebase. The outbox must implement a per-subscription state machine with prefix-aware branching, retry limits, and terminal states.

**State machine per (relay, subscription_id):**

Each (relay, subscription_id) pair tracks a **unified retry budget**: `total_retries` across all CLOSED reasons. This prevents infinite loops from any combination of prefixes.

```
States: Active → (CLOSED received) → Evaluating → Retrying | Terminal | Requeued

Shared budget per (relay, subscription_id):
  total_retries: Int = 0
  MAX_TOTAL_RETRIES = 5          // absolute ceiling across all prefix types

On CLOSED:
  if total_retries >= MAX_TOTAL_RETRIES:
    → Terminal (retry budget exhausted, regardless of prefix)

  Parse MachineReadablePrefix from message.
  total_retries += 1

  "auth-required:" →
    if auth_retries < MAX_AUTH_RETRIES (2):
      → Retrying: sign kind:22242, send AUTH, wait OK, re-send REQ
      auth_retries += 1
    else:
      → Terminal (auth exhausted)

  "restricted:" →
    → Terminal (relay rejected our key, don't retry)

  "rate-limited:" →
    if rate_limit_retries < MAX_RATE_RETRIES (3):
      → Requeued: jittered backoff (1s * 2^retry + random(0..500ms))
      rate_limit_retries += 1
    else:
      → Terminal (rate limit exhausted)

  "blocked:" →
    → Terminal (add relay to session-scoped denylist)

  "invalid:" →
    → Terminal (filter rejected, log error)

  "error:" →
    if error_retries < MAX_ERROR_RETRIES (1):
      → Requeued: 2s backoff
    else:
      → Terminal (server error)

  "mute:" →
    → Terminal (relay silently ignoring)

  Unknown/empty prefix (no recognized prefix, including server-side termination):
    if unknown_retries < MAX_UNKNOWN_RETRIES (2):
      → Requeued: 5s backoff (relay may have restarted)
      unknown_retries += 1
    else:
      → Terminal (unknown error exhausted, log full CLOSED message for diagnostics)

Terminal states: subscription cleaned up, slot released, no further retries.
Requeued states: subscription placed in relay queue, flushed on next slot availability or timer.
```

**Key invariant:** Every path reaches Terminal in at most `MAX_TOTAL_RETRIES` (5) attempts. Unknown/empty prefixes are **not** exempt — they are capped at 2 retries.

**Idempotency:** Re-sending a REQ with the same subscription_id is safe per NIP-01 (replaces previous filter). No dedup needed.

### 8. Anti-Amplification Budgets

Hostile kind:10002/10050 lists can force excessive relay connections. Hard caps:

```
OutboxBudget (configurable constants):
├── maxEphemeralRelaysPerResolve: Int = 8        // per outboxStream call (already in selector)
├── maxRelaysPerAuthor: Int = 2                   // hard cap AFTER popularity filtering
├── maxNewRelaysPerMinute: Int = 12               // rate limit on new ephemeral connections (shared)
├── maxFanoutRelaysPerPublish: Int = 6            // max relays per single event publish (inbox delivery)
├── maxDMRelaysPerRecipient: Int = 3              // cap on kind:10050 relay count per recipient
└── maxTotalEphemeralRelays: Int = 20             // absolute ceiling on concurrent ephemeral relays
```

#### Priority-Aware Rate Budgeting

The `maxNewRelaysPerMinute` (12) budget is consumed in priority order. When the sliding window is near exhaustion, higher-priority flows proceed while lower-priority flows are deferred or dropped.

```
Connection Priority Tiers (highest to lowest):
  P0 — DM delivery (kind:1059 to kind:10050 relays):
        Rationale: user-initiated, latency-sensitive, small fanout
        Budget reservation: 4 of 12 slots reserved (always available for P0)

  P1 — Event publish (inbox delivery to tagged users' read relays):
        Rationale: user-initiated write, but broader fanout
        Budget: draws from remaining pool after P0 reservation

  P2 — Feed/timeline subscriptions (outboxStream to authors' write relays):
        Rationale: background, can tolerate delay, largest consumer
        Budget: draws from remaining pool after P0+P1

  P3 — Single-event lookups (relay hint fetches, profile lookups):
        Rationale: speculative, user can retry
        Budget: draws from remaining pool, first to be deferred
```

**Enforcement:**
- `RelayPool`: sliding window tracks connections per minute. Each `acquireEphemeralRelays` call carries a priority tier.
- P0 reservation: 4 of 12 slots are reserved exclusively for P0. P1-P3 share the remaining 8. When only reserved slots remain, P1-P3 queue instead of dialing.
- Starvation guard: if there is at least one pending P1 request and no P1 slot has been granted
  in the current 10-second slice, grant the next available non-P0 slot to P1 before P2/P3.
  This prevents sustained P0 traffic from indefinitely starving user-initiated publishes.
- When budget exhausted for a tier: queue the request with jittered backoff (100ms + random(0..200ms)). Queued requests drain as the sliding window advances.
- `OutboxRelayResolver`: clamp returned relay lists to `maxRelaysPerAuthor` after filtering
- `OutboxRelaySelector`: already has `maxConnections`; also check `maxTotalEphemeralRelays` against `RelayPool.ephemeralLeases.count`
- Write path: clamp total target relays to `maxFanoutRelaysPerPublish`
- DM path: clamp kind:10050 results to `maxDMRelaysPerRecipient`

### 9. Subscription Queue Policy

The `RelayPolicyCache` subscription queue needs explicit fairness and lifecycle semantics:

```
Queue Policy:
├── Order: FIFO (first queued = first served when slot frees)
├── Priority tiers:
│   P0: Feed subscriptions (timeline, notifications) — PROTECTED, never dropped
│   P1: Single-event lookups (relay hints, thread context)
│   P2: Profile/metadata fetches
│   (within same priority: FIFO)
├── Drop policy (when queue full):
│   - Max queue depth per relay: 20
│   - If queue full, drop lowest-priority item (P2 first, then P1)
│   - P0 (feed subscriptions) are NEVER dropped by lower-priority eviction.
│   - P0 coalescing: when a new P0 item targets the same
│     (relay, author_set, filter_signature, stream_mode) as an existing queued P0 item,
│     REPLACE the older item (the newer request is more relevant).
│     This prevents unbounded P0 accumulation from repeated feed refreshes.
│   - If queue is full of non-coalescable P0 items: reject the new item and log
│     "queue full, all protected" at warning level.
│   - This prevents silent feed degradation while bounding queue growth.
├── Timeout: queued items expire after 30s. On expiry:
│   - Release continuation with empty result
│   - Log "subscription queue timeout" with priority level for diagnostics
│   - P0 timeouts logged at warning level (indicates relay is too slow for feeds)
├── Cancellation: when parent outboxStream task is cancelled:
│   - Remove all its queued items from all relay queues
│   - No dangling continuations
├── Backpressure: if queue depth > 10 for a relay, log warning
│   and consider that relay overloaded (don't add more from selector)
│   Exception: P0 items bypass backpressure (feeds must not be silently dropped)
```

### 10. kind:10002 Republish Policy

NIP-65 says: *"Send the author's kind:10002 event to all relays the event was published to."* This is a discoverability mechanism — other clients need to find our relay list to reach us.

**Scope clarification:** "all relays the event was published to" in Layer 6 means the full set of relays an event was actually sent to (author's write relays + tagged users' read relays). The republish optimization below controls **when** the kind:10002 is sent, not **where** — it deduplicates unnecessary resends but does not exclude any relay category.

```
Republish Rules:
├── Target relays: ALL relays the event was published to (per NIP-65 spec)
│   This includes user's own configured relays AND inbox-delivery relays.
│   No relay category is excluded.
├── Dedup: only send kind:10002 if that relay doesn't already have the latest version
│   Track via: (latest kind:10002 event ID, relay URL) → last_sent_timestamp
│   Stored in-memory. Lost on app restart — acceptable, see below.
├── Stale TTL: re-publish if last sent to this relay > 24 hours ago
├── First contact: always send to a relay on first event send of the session
├── Retries: kind:10002 republish does NOT trigger on event retries (only new events)
├── Restart churn (known v1 behavior): on app restart, in-memory dedup state is lost,
│   so kind:10002 may be re-sent to relays that already have it. This is harmless
│   (idempotent replaceable event) and self-corrects within one publish cycle.
│   If churn proves excessive in practice, persist dedup state to UserDefaults
│   as a follow-up optimization (not required for v1).
```

### 11. NIP-05 Relay Hints — Trust Boundaries

NIP-05 hints are useful for bootstrap but are a weak signal:

```
NIP-05 Trust Policy:
├── Classification: "weak hint" (vs kind:10002 = "authoritative")
├── Cache TTL: 1 hour (vs kind:10002 = until replaced by newer event)
├── Demotion: if NIP-05 relay fails to return events 3 times consecutively,
│   demote to "unreliable" and stop using for 24 hours
├── Priority: always prefer kind:10002 when available
│   NIP-05 only used when kind:10002 is absent
├── Trust boundary: NIP-05 relays are treated as read-only hints
│   (never used for write routing / inbox delivery)
├── Scoring integration (future): when relay scoring is added,
│   NIP-05 hints start with lower initial score than kind:10002
```

### 12. NostrDB Decision

**Decision: No nostrdb schema changes needed for initial outbox implementation.**

Rationale:
- kind:10002 and kind:10050 events are already stored in NostrDB and queryable via existing filter API
- The OutboxRelayResolver maintains an in-memory cache populated from NostrDB queries — no new index needed
- Relay hint extraction from tags uses existing `TagSequence` API

**Future consideration:** If relay scoring is added (Phase 2+), a `person_relay` table (like gossip's approach) tracking seen-on-relay timestamps and success rates would benefit from a nostrdb index. This would be a separate proposal.

### 13. Metrics & Rollout Plan

Default-on autopilot requires guardrails. Define launch gates and runtime metrics:

```
Metrics to Track (structured logging, not analytics):
├── event_completeness_delta:
│   - Count of events found via outbox that would have been missed without it
│   - Measured by: events returned only from ephemeral (non-user) relays
├── relay_dial_rate:
│   - New ephemeral connections per 5-minute window
│   - Alert threshold: > 30/5min suggests runaway resolution
├── auth_failure_rate:
│   - Auth attempts vs successes per relay
│   - Relays with > 50% failure rate flagged in diagnostics
├── queue_depth_p95:
│   - 95th percentile subscription queue depth across all relays
│   - > 10 sustained suggests budget is too tight or relay is slow
├── ephemeral_relay_lifetime:
│   - Average time from acquireEphemeralRelay to release
│   - Unexpectedly long = possible lease leak

Rollout Plan:
├── Phase A (internal): Enable behind developer_mode flag
│   Log all metrics, monitor for 1 week
├── Phase B (beta): Enable for TestFlight users
│   Validate: feed completeness improves, battery/network delta < 5%
├── Phase C (default-on): Enable for all users
│   With autopilot toggle visible in settings for opt-out
│   Kill switch: server-side flag to disable outbox globally if issues detected

Launch Gates (must pass before Phase C):
├── No increase in crash rate
├── Ephemeral relay connections released within 60s of subscription end (p99)
├── Battery delta < 5% vs baseline (measured via XCTest energy gauges)
├── Network transfer delta < 15% vs baseline
├── Event completeness improvement measurable (> 0 events recovered per session avg)
```

### 14. kind:10006 Blocked Relay Scope

**Semantics:** kind:10006 blocked relays apply globally to all outbox routing:
- Read path: never dial blocked relay for feed subscriptions
- Write path: never send events to blocked relay for inbox delivery
- DM path: never send giftwrap to blocked relay even if listed in recipient's kind:10050

**Manual-override exception — strict boundary:**

"Manually adds" is defined precisely as: **relays present in the user's kind:10002 (NIP-65) relay list that the user published themselves.** This is the only relay set the user explicitly controls. The override applies as follows:

```
Override Scope:
├── Definition: relay URL appears in BOTH kind:10006 AND the user's own kind:10002
├── Effect: relay is treated as user-configured for the user's OWN read/write operations only
│   - User can read from it (it's in their kind:10002)
│   - User can write to it (it's in their kind:10002)
├── Does NOT override for:
│   - Outbox auto-dialing (other authors' relays) — still blocked
│   - Inbox delivery (sending to tagged users) — still blocked
│   - DM delivery — still blocked
│   - Any relay not in user's own kind:10002 — still blocked
├── Rationale: User explicitly chose this relay for themselves despite blocking it.
│   This can happen when a user wants to use a relay but doesn't want outbox
│   auto-dialing it for other people's content.
```

**UX note:** If outbox wants to dial a blocked relay and skips it, log the skip at debug level. Don't nag the user.

---

## Verification Plan

### Unit Tests
1. `OutboxRelayResolver`: Mock NostrDB with fixture kind:10002 and kind:10050 events, verify correct relay resolution per pubkey. Test NIP-05 fallback when 10002 missing. Test blocked relay filtering.
2. `OutboxRelaySelector`: Given known relay maps, verify minimal relay set computation. Edge cases: no kind:10002 for any user, all users on same relay, maxConnections=1, blocked relays excluded.
3. `RelayPolicyCache`: Mock HTTP responses, verify full NIP-11 parsing. Test subscription slot tracking (acquire/release/queue).
4. `MachineReadablePrefix`: Parse all standard prefixes from OK and CLOSED messages.
5. `ClosedResult`: Verify CLOSED message parsing and prefix extraction.

### Integration Tests
6. **fiatjaf scenario** (from issue #423): Publish event only to obscure relay, verify outbox routing discovers it via kind:10002
7. **Feed routing**: Set up 3 test relays, distribute authors' kind:10002 across them, subscribe to timeline, verify events arrive from correct relays
8. **Fallback**: Verify authors without kind:10002 still work via user's relays (and NIP-05 if available)
9. **DM routing**: Verify kind:1059 giftwrap sent to kind:10050 relays, NOT kind:10002. Verify delivery blocked when 10050 missing.
10. **Auth retry**: Simulate relay sending CLOSED "auth-required:", verify client performs auth and re-sends REQ
11. **Blocked relay**: Add relay to kind:10006, verify it's never dialed even if it appears in an author's kind:10002
12. **NIP-10 pubkey fallback**: When e-tag relay hint fails, verify resolution falls back to author's write relays via pubkey in tag
13. **Protected event (NIP-70)**: Verify ["-"] events only sent to auth'd relays

### Stress / Soak Tests
14. **Large follow graph** (500+ follows): Verify selector converges in <100ms, total ephemeral relays stays within `maxTotalEphemeralRelays`, no lease leaks after 10 minutes
15. **Relay flap simulation**: Rapidly connect/disconnect ephemeral relays (10 cycles), verify subscription queue drains correctly, slots released, no dangling continuations
16. **Hostile kind:10002** (30 relays listed): Verify clamped to `maxRelaysPerAuthor`, total connections within budget
17. **Queue backpressure**: Fill relay queue to capacity (20), verify oldest/lowest-priority items dropped, new items accepted, no deadlock
18. **Auth retry exhaustion**: Relay always returns CLOSED "auth-required:", verify max 2 retries then terminal state, subscription cleaned up

### Manual Testing
19. Fresh install: Verify feed loads without manual relay configuration
20. Toggle autopilot off: Verify behavior reverts to broadcast-only
21. Monitor connection count: Ensure ephemeral connections are released after subscription ends
22. DM to user with kind:10050: Verify delivery succeeds. DM to user without: Verify graceful failure message.
23. Battery/network impact: Profile with Instruments, compare outbox-on vs outbox-off for 15-minute session

---

## Work Items

| # | Title | Priority | Depends On | Phase |
|---|-------|----------|------------|-------|
| 1 | CLOSED message parsing + MachineReadablePrefix | P1 | — | 0 |
| 2 | Expand Limitations struct to full NIP-11 | P1 | — | 0 |
| 3 | OutboxRelayResolver (10002 + 10050 + 10006 + NIP-05) | P1 | — | 1 |
| 4 | Relay selection algorithm (with denylist) | P1 | 3 | 2 |
| 5 | RelayPolicyCache (full NIP-11 + slot tracking) | P2 | 1, 2 | 2 |
| 6 | Auth retry orchestrator (NIP-42 CLOSED/OK auth-required) | P1 | 1 | 2 |
| 7 | Feed-level outbox routing | P1 | 3, 4, 5, 6 | 3 |
| 8 | Write-side routing (split by event class) | P2 | 3, 6 | 4 |
| 9 | Autopilot toggle UI | P3 | 7 | 5 |
| 10 | Tests: resolver + selector | P1 | 3, 4 | 1-2 |
| 11 | Tests: CLOSED parsing + NIP-11 policy | P1 | 1, 5 | 2 |
| 12 | Tests: auth retry + feed routing | P1 | 6, 7 | 3 |
| 13 | Tests: write-side routing + stress | P1 | 8 | 4 |

---

## References

- **Notedeck PR:** damus-io/notedeck#1288 (6931+, 1788-)
- **Damus Issue:** damus-io/damus#423 (Autopilot/Outbox)
- **Nostrability:** nostrability/nostrability#69 (community outbox implementations)
- **NIPs:** [01](https://github.com/nostr-protocol/nips/blob/master/01.md) (protocol/CLOSED), [05](https://github.com/nostr-protocol/nips/blob/master/05.md) (relay hints), [10](https://github.com/nostr-protocol/nips/blob/master/10.md) (e-tag pubkey for outbox fallback), [11](https://github.com/nostr-protocol/nips/blob/master/11.md) (relay info/limitations), [17](https://github.com/nostr-protocol/nips/blob/master/17.md) (DM via kind:10050), [19](https://github.com/nostr-protocol/nips/blob/master/19.md) (bech32 relay hints), [42](https://github.com/nostr-protocol/nips/blob/master/42.md) (authentication), [51](https://github.com/nostr-protocol/nips/blob/master/51.md) (lists/blocked relays kind:10006), [65](https://github.com/nostr-protocol/nips/blob/master/65.md) (relay list kind:10002), [66](https://github.com/nostr-protocol/nips/blob/master/66.md) (relay monitoring), [70](https://github.com/nostr-protocol/nips/blob/master/70.md) (protected events)
- **Community approaches:** hzrd149 (greedy set cover), gossip (per-pubkey relay scoring), coracle (relay stats, large follow list splitting), nostur (follow-limited outbox)
- **jb55 quote:** *"nostrdb was built specifically to support the outbox model"*
- **kernelkind on TransparentRelay:** *"guaranteed that the relay subscription the OutboxSubId uses is not used by any other OutboxSubId subscriptions"*
- **kernelkind on QueuedTasks:** *"things are queued when we hit [NIP-11] limitations"*
