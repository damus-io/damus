#!/usr/bin/env bash
#
# nostril-story.sh — emit test "story" events (kind:20, #T=story, NIP-40) to stdout.
#
# Examples:
#   # Emit 3 picsum slides from a fresh ephemeral key, 24h expiration.
#   # Prints the pubkey on stderr so you can follow it in damus.
#   devtools/nostril-story.sh | nostcat wss://relay.damus.io
#
#   # Custom key (same "author" persists across runs), custom images, 1h expiration
#   devtools/nostril-story.sh -s <hex_seckey> -d 1 \
#     -i https://example.com/a.jpg -i https://example.com/b.jpg \
#     | nostcat wss://relay.damus.io
#
# Requires: nostril, jq.

set -euo pipefail

rand_hex() {
    # $1 = number of bytes. Outputs 2*N hex chars, no newline.
    od -An -tx1 -N "$1" /dev/urandom | tr -d ' \n'
}

SEC=${SEC:=""}
EXPIRY_HOURS=24
IMAGES=()

usage() {
    sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

while getopts ":s:d:i:h" opt; do
    case "$opt" in
        s) SEC="$OPTARG" ;;
        d) EXPIRY_HOURS="$OPTARG" ;;
        i) IMAGES+=("$OPTARG") ;;
        h|*) usage ;;
    esac
done

# Default slide set: 3 picsum images with random seeds so each run is unique.
if [ "${#IMAGES[@]}" -eq 0 ]; then
    for n in 1 2 3; do
        IMAGES+=("https://picsum.photos/seed/$(rand_hex 4)/800/1200.jpg")
    done
fi

if [ -z "$SEC" ]; then
    SEC=$(rand_hex 32)
    echo "# generated seckey: $SEC" >&2
fi

PUBKEY=$(nostril --sec "$SEC" --kind 0 --content '{}' 2>/dev/null | jq -r '.pubkey')
echo "# author pubkey: $PUBKEY" >&2
echo "# follow this pubkey in damus to see the stories in your tray" >&2

now=$(date +%s)
expiry=$(( now + EXPIRY_HOURS * 3600 ))

# Stagger created_at so slides have a stable order within an author.
i=0
for url in "${IMAGES[@]}"; do
    ts=$(( now - (${#IMAGES[@]} - i - 1) * 10 ))
    # NOTE: nostril's --tagn is variadic-greedy, so all flags must come BEFORE
    # any --tagn invocation.
    nostril \
        --sec "$SEC" \
        --kind 20 \
        --created-at "$ts" \
        --content "test story slide" \
        --envelope \
        --tagn 2 T story \
        --tagn 2 expiration "$expiry" \
        --tagn 4 imeta "url $url" "m image/jpeg" "dim 800x1200"
    i=$((i + 1))
done

echo "# done. emitted ${#IMAGES[@]} slide(s) (expiry: $(date -d @$expiry 2>/dev/null || date -r $expiry))" >&2
