#!/usr/bin/env python3
"""
Generate profile bootstrap bundle for Damus (Simple HTTP version)

Uses nostr.band API to fetch events - no external dependencies needed.
"""

import json
import urllib.request
import urllib.parse
import sys
from typing import Set, List

# Root npubs for WOT scoring
ROOT_NPUBS = [
    "npub1g53mukxnjkcmr94fhryzkqutdz2ukq4ks0gvy5af25rgmwsl4ngq43drvk",
    "npub1v0lxxxxutpvrelsksy8cdhgfux9l6a42hsj2qzquu2zk7vc9qnkszrqj49",
    "npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6",
    "npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s",
    "npub1s05p3ha7en49dv8429tkk07nnfa9pcwczkf5x5qrdraqshxdje9sq6eyhe",
    "npub13kwjkaunpmj5aslyd7hhwnwaqswmknj25dddglqztzz29pkavhaq25wg2a",
    "npub1995y964wmxl94crx3ksfley24szjr390skdd237ex9z7ttp5c9lqld8vtf",
    "npub1hu3hdctm5nkzd8gslnyedfr5ddz3z547jqcl5j88g4fame2jd08qh6h8nh",
    "npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9",
]

def bech32_decode(bech32_str: str) -> str:
    """Decode npub to hex pubkey"""
    charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

    if not bech32_str.startswith("npub1"):
        raise ValueError("Invalid npub format")

    data = bech32_str[5:]

    # Decode bech32
    values = []
    for char in data:
        if char in charset:
            values.append(charset.index(char))

    # Convert 5-bit to 8-bit
    bits = []
    for value in values:
        bits.extend([int(b) for b in format(value, '05b')])

    # Group into bytes
    hex_bytes = []
    for i in range(0, len(bits) - len(bits) % 8, 8):
        byte = 0
        for j in range(8):
            byte = (byte << 1) | bits[i + j]
        hex_bytes.append(byte)

    # Return as hex (remove checksum)
    return ''.join(format(b, '02x') for b in hex_bytes[:-6])

def fetch_events_from_api(authors: List[str], kinds: List[int], limit: int = 1000) -> List[dict]:
    """Fetch events from nostr.band API"""
    # Build filter
    filter_obj = {
        "authors": authors,
        "kinds": kinds,
        "limit": limit
    }

    url = f"https://api.nostr.band/v0/events"

    try:
        # Make POST request
        data = json.dumps(filter_obj).encode('utf-8')
        req = urllib.request.Request(
            url,
            data=data,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=30) as response:
            result = json.loads(response.read().decode('utf-8'))
            return result.get('events', [])

    except Exception as e:
        print(f"Error fetching from nostr.band: {e}", file=sys.stderr)
        return []

def main():
    print("Converting npubs to hex pubkeys...", file=sys.stderr)
    root_pubkeys = []

    for npub in ROOT_NPUBS:
        try:
            pubkey = bech32_decode(npub)
            root_pubkeys.append(pubkey)
            print(f"  {npub[:16]}... -> {pubkey[:16]}...", file=sys.stderr)
        except Exception as e:
            print(f"  Error decoding {npub}: {e}", file=sys.stderr)

    print(f"\nFetching kind 3 (contact lists) for {len(root_pubkeys)} root users...", file=sys.stderr)

    # Fetch kind 3 for roots
    kind3_events = fetch_events_from_api(root_pubkeys, [3], limit=100)
    print(f"  Found {len(kind3_events)} contact list events", file=sys.stderr)

    # Extract followed pubkeys
    followed_pubkeys: Set[str] = set(root_pubkeys)

    for event in kind3_events:
        tags = event.get('tags', [])
        for tag in tags:
            if len(tag) >= 2 and tag[0] == 'p':
                followed_pubkeys.add(tag[1])

    print(f"  Discovered {len(followed_pubkeys)} unique pubkeys", file=sys.stderr)

    # Fetch kind 0 in batches
    print(f"\nFetching kind 0 (profiles) for {len(followed_pubkeys)} users...", file=sys.stderr)

    followed_list = list(followed_pubkeys)
    kind0_events = []

    batch_size = 100
    for i in range(0, len(followed_list), batch_size):
        batch = followed_list[i:i+batch_size]
        print(f"  Fetching batch {i//batch_size + 1}/{(len(followed_list)-1)//batch_size + 1}...", file=sys.stderr)

        batch_events = fetch_events_from_api(batch, [0], limit=len(batch))
        kind0_events.extend(batch_events)

    print(f"  Total profiles: {len(kind0_events)}", file=sys.stderr)

    # Combine all events
    all_events = kind3_events + kind0_events

    # Sort by created_at
    all_events.sort(key=lambda e: e.get('created_at', 0))

    # Output JSONL
    print(f"\nGenerating JSONL...", file=sys.stderr)

    for event in all_events:
        print(json.dumps(event))

    print(f"\n✓ Generated bootstrap with {len(all_events)} events", file=sys.stderr)
    print(f"  - {len(kind3_events)} contact lists", file=sys.stderr)
    print(f"  - {len(kind0_events)} profiles", file=sys.stderr)
    print(f"  - {len(followed_pubkeys)} unique users", file=sys.stderr)

if __name__ == "__main__":
    main()
