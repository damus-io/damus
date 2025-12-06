#!/bin/bash
# Fetch profiles for extracted pubkeys in batches

export PATH="$PATH:$HOME/go/bin"
RELAY="wss://relay.damus.io"

# Extract unique pubkeys from contact lists
cat profile-bootstrap.jsonl | jq -r '.tags[]? | select(.[0] == "p") | .[1]' | sort -u | head -200 > pubkeys.txt

total=$(wc -l < pubkeys.txt | tr -d ' ')
echo "Fetching profiles for $total pubkeys in batches of 50..."

count=0
while IFS= read -r pubkey; do
    nak req -k 0 --author "$pubkey" "$RELAY" 2>/dev/null >> profiles_temp.jsonl &
    count=$((count + 1))

    # Wait every 50 requests
    if [ $((count % 50)) -eq 0 ]; then
        wait
        echo "  Fetched $count/$total..."
    fi
done < pubkeys.txt

wait
echo "Done fetching. Combining..."

# Combine contact lists and profiles, sort by created_at
cat profile-bootstrap.jsonl profiles_temp.jsonl | jq -c -s 'sort_by(.created_at) | .[]' > profile-bootstrap-full.jsonl

profiles=$(cat profiles_temp.jsonl | wc -l | tr -d ' ')
total_events=$(cat profile-bootstrap-full.jsonl | wc -l | tr -d ' ')

echo "✓ Generated profile-bootstrap-full.jsonl"
echo "  - 7 contact lists"
echo "  - $profiles profiles"
echo "  - $total_events total events"

cp profile-bootstrap-full.jsonl ../damus/Resources/profile-bootstrap.jsonl
echo "✓ Copied to Resources/profile-bootstrap.jsonl"
