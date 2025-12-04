#!/bin/bash
#
# Generate profile bootstrap bundle for Damus
# Fetches kind 3 and kind 0 events for root users using nostril CLI
#

set -e

# Root npubs
ROOTS=(
    "npub1g53mukxnjkcmr94fhryzkqutdz2ukq4ks0gvy5af25rgmwsl4ngq43drvk"
    "npub1v0lxxxxutpvrelsksy8cdhgfux9l6a42hsj2qzquu2zk7vc9qnkszrqj49"
    "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"
    "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s"
    "npub1s05p3ha7en49dv8429tkk07nnfa9pcwczkf5x5qrdraqshxdje9sq6eyhe"
    "npub13kwjkaunpmj5aslyd7hhwnwaqswmknj25dddglqztzz29pkavhaq25wg2a"
    "npub1995y964wmxl94crx3ksfley24szjr390skdd237ex9z7ttp5c9lqld8vtf"
    "npub1hu3hdctm5nkzd8gslnyedfr5ddz3z547jqcl5j88g4fame2jd08qh6h8nh"
    "npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9"
)

RELAY="wss://relay.damus.io"
OUTPUT="profile-bootstrap.jsonl"
TEMP_DIR=$(mktemp -d)

echo "==> Generating profile bootstrap bundle" >&2
echo "    Using ${#ROOTS[@]} root npubs" >&2
echo "    Relay: $RELAY" >&2
echo "" >&2

# Check for nak (nostr army knife CLI tool)
if ! command -v nak &> /dev/null; then
    echo "Error: 'nak' command not found" >&2
    echo "Install it with: go install github.com/fiatjaf/nak@latest" >&2
    echo "" >&2
    echo "Or use manual approach:" >&2
    echo "  You'll need to manually fetch events from Nostr relays" >&2
    exit 1
fi

# Fetch kind 3 (contact lists) for root users
echo "==> Step 1: Fetching contact lists (kind 3) for root users..." >&2

for npub in "${ROOTS[@]}"; do
    echo "    Fetching for $npub..." >&2
    nak req -k 3 --author "$npub" "$RELAY" 2>/dev/null | head -1 >> "$TEMP_DIR/kind3.jsonl" || true
done

KIND3_COUNT=$(wc -l < "$TEMP_DIR/kind3.jsonl" | tr -d ' ')
echo "    Found $KIND3_COUNT contact list events" >&2

# Extract all followed pubkeys
echo "" >&2
echo "==> Step 2: Extracting followed pubkeys..." >&2

# Extract p tags from kind 3 events
FOLLOWED=$(cat "$TEMP_DIR/kind3.jsonl" | \
    jq -r '.tags[]? | select(.[0] == "p") | .[1]' | \
    sort -u)

# Add root pubkeys too
for npub in "${ROOTS[@]}"; do
    # Convert npub to hex (basic conversion, works for most cases)
    # In production, use proper bech32 decoder
    echo "$npub"
done | nak decode 2>/dev/null | sort -u > "$TEMP_DIR/roots_hex.txt" || true

# Combine
cat "$TEMP_DIR/roots_hex.txt" <(echo "$FOLLOWED") | sort -u > "$TEMP_DIR/all_pubkeys.txt"

TOTAL_PUBKEYS=$(wc -l < "$TEMP_DIR/all_pubkeys.txt" | tr -d ' ')
echo "    Discovered $TOTAL_PUBKEYS unique pubkeys" >&2

# Fetch kind 0 (profiles) for all discovered pubkeys
echo "" >&2
echo "==> Step 3: Fetching profiles (kind 0) for $TOTAL_PUBKEYS users..." >&2

# Batch fetch (nak can handle multiple authors)
PUBKEY_LIST=$(cat "$TEMP_DIR/all_pubkeys.txt" | head -500 | tr '\n' ',' | sed 's/,$//')

if [ -n "$PUBKEY_LIST" ]; then
    echo "    Fetching profiles..." >&2
    nak req -k 0 --author "$PUBKEY_LIST" "$RELAY" 2>/dev/null >> "$TEMP_DIR/kind0.jsonl" || true
fi

KIND0_COUNT=$(wc -l < "$TEMP_DIR/kind0.jsonl" | tr -d ' ')
echo "    Found $KIND0_COUNT profile events" >&2

# Combine and output
echo "" >&2
echo "==> Step 4: Generating JSONL output..." >&2

cat "$TEMP_DIR/kind3.jsonl" "$TEMP_DIR/kind0.jsonl" | \
    jq -c -s 'sort_by(.created_at) | .[]' > "$OUTPUT"

TOTAL_EVENTS=$(wc -l < "$OUTPUT" | tr -d ' ')
FILE_SIZE=$(du -h "$OUTPUT" | cut -f1)

echo "" >&2
echo "✓ Generated $OUTPUT" >&2
echo "  - $KIND3_COUNT contact lists" >&2
echo "  - $KIND0_COUNT profiles" >&2
echo "  - $TOTAL_EVENTS total events" >&2
echo "  - $FILE_SIZE file size" >&2

# Cleanup
rm -rf "$TEMP_DIR"

echo "" >&2
echo "Done! Output saved to: $OUTPUT" >&2
