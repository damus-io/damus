#!/usr/bin/env python3
"""
Generate profile bootstrap bundle for Damus

Fetches kind 3 (contact lists) and kind 0 (profiles) for root users and their follows,
exports to JSONL format for bundling with the app.
"""

import json
import asyncio
import websockets
import sys
from typing import Set, List, Dict, Any

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

# Popular Nostr relays
RELAYS = [
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.nostr.band",
]

def bech32_decode(bech32_str: str) -> bytes:
    """Decode npub to hex pubkey"""
    # Simple bech32 decoder for npub
    charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

    if not bech32_str.startswith("npub1"):
        raise ValueError("Invalid npub format")

    data = bech32_str[5:]  # Remove "npub1" prefix

    # Decode bech32 data
    values = []
    for char in data:
        if char not in charset:
            continue
        values.append(charset.index(char))

    # Convert from 5-bit to 8-bit
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

    # Return as hex string (remove checksum - last 6 bytes)
    return ''.join(format(b, '02x') for b in hex_bytes[:-6])

async def fetch_events(relay_url: str, filters: List[Dict], timeout: int = 10) -> List[Dict]:
    """Fetch events from a relay"""
    events = []
    subscription_id = "profile_bootstrap"

    try:
        async with websockets.connect(relay_url, ping_interval=None) as websocket:
            # Send REQ message
            req_msg = json.dumps(["REQ", subscription_id] + filters)
            await websocket.send(req_msg)

            # Collect events with timeout
            try:
                async with asyncio.timeout(timeout):
                    while True:
                        msg = await websocket.recv()
                        data = json.loads(msg)

                        if data[0] == "EVENT" and data[1] == subscription_id:
                            events.append(data[2])
                        elif data[0] == "EOSE" and data[1] == subscription_id:
                            break
            except asyncio.TimeoutError:
                pass

            # Close subscription
            close_msg = json.dumps(["CLOSE", subscription_id])
            await websocket.send(close_msg)

    except Exception as e:
        print(f"Error fetching from {relay_url}: {e}", file=sys.stderr)

    return events

async def fetch_from_multiple_relays(filters: List[Dict]) -> List[Dict]:
    """Fetch events from multiple relays in parallel"""
    tasks = [fetch_events(relay, filters) for relay in RELAYS]
    results = await asyncio.gather(*tasks, return_exceptions=True)

    # Combine and deduplicate by event id
    seen_ids = set()
    unique_events = []

    for result in results:
        if isinstance(result, Exception):
            continue
        for event in result:
            event_id = event.get('id')
            if event_id and event_id not in seen_ids:
                seen_ids.add(event_id)
                unique_events.append(event)

    return unique_events

async def main():
    print("Converting npubs to hex pubkeys...", file=sys.stderr)
    root_pubkeys = []
    for npub in ROOT_NPUBS:
        try:
            pubkey = bech32_decode(npub)
            root_pubkeys.append(pubkey)
            print(f"  {npub} -> {pubkey}", file=sys.stderr)
        except Exception as e:
            print(f"  Error decoding {npub}: {e}", file=sys.stderr)

    print(f"\nFetching kind 3 (contact lists) for {len(root_pubkeys)} root users...", file=sys.stderr)

    # Fetch kind 3 for roots
    kind3_filter = {
        "kinds": [3],
        "authors": root_pubkeys,
        "limit": 100
    }

    kind3_events = await fetch_from_multiple_relays([kind3_filter])
    print(f"  Found {len(kind3_events)} contact list events", file=sys.stderr)

    # Extract all followed pubkeys from kind 3 events
    followed_pubkeys: Set[str] = set(root_pubkeys)  # Include roots

    for event in kind3_events:
        tags = event.get('tags', [])
        for tag in tags:
            if len(tag) >= 2 and tag[0] == 'p':
                followed_pubkeys.add(tag[1])

    print(f"  Discovered {len(followed_pubkeys)} unique pubkeys", file=sys.stderr)

    # Fetch kind 0 for all discovered pubkeys
    print(f"\nFetching kind 0 (profiles) for {len(followed_pubkeys)} users...", file=sys.stderr)

    # Batch into groups of 100 (relay limits)
    followed_list = list(followed_pubkeys)
    kind0_events = []

    for i in range(0, len(followed_list), 100):
        batch = followed_list[i:i+100]
        kind0_filter = {
            "kinds": [0],
            "authors": batch,
            "limit": len(batch)
        }
        batch_events = await fetch_from_multiple_relays([kind0_filter])
        kind0_events.extend(batch_events)
        print(f"  Fetched {len(batch_events)} profiles (batch {i//100 + 1})", file=sys.stderr)

    print(f"  Total profiles: {len(kind0_events)}", file=sys.stderr)

    # Combine all events
    all_events = kind3_events + kind0_events

    # Sort by created_at (oldest first)
    all_events.sort(key=lambda e: e.get('created_at', 0))

    # Output JSONL
    print(f"\nGenerating JSONL with {len(all_events)} events...", file=sys.stderr)

    for event in all_events:
        print(json.dumps(event))

    print(f"\n✓ Generated profile-bootstrap.jsonl with {len(all_events)} events", file=sys.stderr)
    print(f"  - {len(kind3_events)} contact lists", file=sys.stderr)
    print(f"  - {len(kind0_events)} profiles", file=sys.stderr)
    print(f"  - {len(followed_pubkeys)} unique users", file=sys.stderr)

if __name__ == "__main__":
    asyncio.run(main())
