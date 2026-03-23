NIP-A7
======

Spells
------

`draft` `optional`

Source: https://github.com/nostr-protocol/nips/pull/2244

## Abstract

This NIP defines `kind:777` events ("spells") that encode Nostr relay query filters as portable, shareable events. A spell stores a REQ or COUNT filter with optional runtime variables and relative timestamps, allowing users to publish, discover, and execute saved queries across clients.

## Event Format

A spell is a regular (non-replaceable) event with `kind:777`.

The `content` field contains a human-readable description of the query in plain text. It MAY be an empty string.

### Required Tags

| tag   | values        | description            |
| ----- | ------------- | ---------------------- |
| `cmd` | `REQ`\|`COUNT` | Query command type     |

A spell MUST contain at least one filter tag (see below).

### Filter Tags

Filter tags encode the fields of a Nostr REQ filter.

| tag       | values                                  | REQ filter field | notes                              |
| --------- | --------------------------------------- | ---------------- | ---------------------------------- |
| `k`       | `<kind number>`                         | `kinds`          | One tag per kind for queryability  |
| `authors` | `<pubkey1>`, `<pubkey2>`, ...           | `authors`        | Single tag, multiple values        |
| `ids`     | `<id1>`, `<id2>`, ...                   | `ids`            | Single tag, multiple values        |
| `tag`     | `<letter>`, `<val1>`, `<val2>`, ...     | `#<letter>`      | See Tag Filters                    |
| `limit`   | `<integer>`                             | `limit`          |                                    |
| `since`   | `<timestamp>` or `<relative>`           | `since`          | See Relative Timestamps            |
| `until`   | `<timestamp>` or `<relative>`           | `until`          | See Relative Timestamps            |
| `search`  | `<query string>`                        | `search`         | NIP-50                             |
| `relays`  | `<wss://url1>`, `<wss://url2>`, ...     | ---              | Target relay URLs                  |

All filter tag values are strings. Numeric values (kinds, limit, timestamps) MUST be encoded as decimal strings.

### Tag Filters

Filter conditions on event tags are encoded as `["tag", <letter>, <value>, ...]` rather than using the tag letter directly (e.g., `["e", ...]` or `["p", ...]`). This prevents semantic collision -- a `["p", <pubkey>]` tag on a Nostr event normally means "this event references this pubkey," which would cause relays and clients to misinterpret filter parameters as social graph references.

The `k` tag is the exception: it uses the tag letter directly (`["k", "1"]`) to enable relay-side indexing and discovery of spells by the kinds they query.

Examples:

    ["tag", "t", "bitcoin", "nostr"]   -> filter: {"#t": ["bitcoin", "nostr"]}
    ["tag", "p", "abcd...", "ef01..."] -> filter: {"#p": ["abcd...", "ef01..."]}
    ["tag", "e", "abcd..."]           -> filter: {"#e": ["abcd..."]}

### Metadata Tags

| tag              | values     | description                                                  |
| ---------------- | ---------- | ------------------------------------------------------------ |
| `name`           | `<string>` | Human-readable spell name                                    |
| `alt`            | `<string>` | NIP-31 alternative text                                      |
| `t`              | `<topic>`  | Topic tag for categorization (multiple allowed)              |
| `close-on-eose` | none       | Clients SHOULD close the subscription after EOSE             |
| `e`              | `<event-id>` | Fork provenance: references the parent spell event        |

Note: `["t", "bitcoin"]` as a top-level tag categorizes the spell itself, while `["tag", "t", "bitcoin"]` is a filter condition matching events with #t = bitcoin. Both may appear in the same event.

## Runtime Variables

The `authors` tag and `tag` filter values MAY contain runtime variables that are resolved at execution time.

| variable     | resolves to                                           |
| ------------ | ----------------------------------------------------- |
| `$me`        | The executing user's pubkey                           |
| `$contacts`  | All pubkeys from the executing user's kind 3 contact list |

Variables are case-sensitive and MUST be lowercase.

If a client cannot resolve a variable (no logged-in user for `$me`, no contact list for `$contacts`), it MUST NOT send the REQ and SHOULD display a message explaining the unresolved dependency.

## Relative Timestamps

The `since` and `until` tags MAY contain relative time expressions instead of Unix timestamps.

Grammar:

    value = unix-timestamp / relative-time / "now"
    relative-time = 1*DIGIT unit
    unit = "s" / "m" / "h" / "d" / "w" / "mo" / "y"

| unit | meaning | seconds   |
| ---- | ------- | --------- |
| `s`  | seconds | 1         |
| `m`  | minutes | 60        |
| `h`  | hours   | 3600      |
| `d`  | days    | 86400     |
| `w`  | weeks   | 604800    |
| `mo` | months  | 2592000   |
| `y`  | years   | 31536000  |

Months and years use approximate fixed durations (30 days and 365 days respectively).

`now` resolves to the current Unix timestamp. A relative time like `7d` resolves to `now - 7 * 86400`.

Clients MUST resolve relative timestamps to absolute Unix timestamps before constructing a REQ message.

## Executing a Spell

To execute a spell, a client:

1. Parses the event tags to reconstruct a filter object
2. Resolves runtime variables (`$me`, `$contacts`) using the executing user's identity
3. Resolves relative timestamps to absolute Unix timestamps
4. Constructs a REQ or COUNT message (per the `cmd` tag) with the resolved filter
5. Determines target relays (see Relay Resolution)
6. Sends the REQ or COUNT message to the resolved relays
7. If `close-on-eose` is present, closes the subscription after receiving EOSE from all connected relays

### Relay Resolution

If the spell contains a `relays` tag, the client SHOULD send the query to those relays.

If no `relays` tag is present, the client SHOULD use NIP-65 relay lists to determine where to send the query, falling back to the executing user's NIP-65 read relays.

## Discovering Spells

Clients can discover spells using standard Nostr queries:

- By author: `{"kinds": [777], "authors": ["<pubkey>"]}`
- By topic: `{"kinds": [777], "#t": ["bitcoin"]}`
- By queried kind: `{"kinds": [777], "#k": ["1"]}`
