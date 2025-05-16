#!/usr/bin/env python3
"""
Nostr Event Updater

This script fetches Nostr events based on a YAML mapping file, updates them with
'tags' based on the mapping data, and signs them with a specified private key.
Optionally can publish the updated events to a relay.

Example YAML mapping file format:
```
# mapping.yaml
"39089:17538dc2a62769d09443f18c37cbe358fab5bbf981173542aa7c5ff171ed77c4:cioc58duuftq": ["farmers", "agriculture"]
"1:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789:someid": "technology"
```

Each key is in the format "kind:pubkey:d-value" and the value is either a single tag string
or a list of tag strings to add.
"""
import sys
import json
import argparse
import yaml
import subprocess
import time
import os
from typing import Dict, List, Optional, Tuple, Any, Union


def parse_args():
    parser = argparse.ArgumentParser(
        description="Fetch Nostr events, update them with tags 't' based on a mapping, and sign them with a private key.",
        epilog="""
Examples:
  # Fetch events, update tags, and print to stdout
  ./update_jsonl.py mapping.yaml nsec1...

  # Fetch events, update tags, and publish to a relay
  ./update_jsonl.py mapping.yaml nsec1... --publish --relay wss://relay.example.com

  # Fetch events, update tags, save to file, and update timestamps
  ./update_jsonl.py mapping.yaml nsec1... --output updated_events.jsonl --update-timestamp
"""
    )
    parser.add_argument(
        "map_yaml_file", 
        help="Path to the YAML file containing the mapping in format 'kind:pubkey:d-value': [tags]"
    )
    parser.add_argument(
        "private_key", 
        help="Private key (hex or nsec format) for signing the updated events."
    )
    parser.add_argument(
        "--relay", 
        default="wss://relay.damus.io", 
        help="Relay URL to fetch events from and optionally publish to. (default: wss://relay.damus.io)"
    )
    parser.add_argument(
        "--output", 
        default=None, 
        help="Output file path to save updated events. If not provided, print to stdout."
    )
    parser.add_argument(
        "--publish", 
        action="store_true", 
        help="Publish updated events to the specified relay."
    )
    parser.add_argument(
        "--update-timestamp", 
        action="store_true", 
        help="Update event timestamps to current time instead of preserving original timestamps."
    )
    return parser.parse_args()


def split_coordinate(coordinate: str) -> Tuple[int, str, str]:
    """Split a coordinate string into kind, pubkey, and d-tag value."""
    parts = coordinate.split(":")
    if len(parts) != 3:
        raise ValueError(f"Invalid coordinate format: {coordinate}")
    kind = int(parts[0])
    pubkey = parts[1]
    d_value = parts[2]
    return kind, pubkey, d_value


def fetch_event(kind: int, pubkey: str, d_value: str, relay: str) -> Optional[Dict]:
    """Fetch an event from the Nostr network using nak CLI.
    
    Args:
        kind: The event kind to fetch
        pubkey: The author's public key
        d_value: The d-tag value to match
        relay: The relay URL to fetch from
        
    Returns:
        The event as a dictionary, or None if not found or error
    """
    try:
        # Check if nak CLI is available
        try:
            subprocess.run(["nak", "--version"], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            sys.stderr.write("Error: 'nak' CLI tool is not available or not in PATH.\n")
            sys.stderr.write("Please install it from https://github.com/fiatjaf/nak\n")
            sys.exit(1)
            
        # Prepare the request command
        cmd = [
            "nak", "req", 
            "--kind", str(kind), 
            "--author", pubkey, 
            "-d", d_value,
            relay
        ]
        
        sys.stderr.write(f"Fetching event: kind={kind}, author={pubkey}, d={d_value} from {relay}...\n")
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        
        if not result.stdout.strip():
            sys.stderr.write(f"No event found for kind={kind}, pubkey={pubkey}, d={d_value}\n")
            return None
        
        event_data = json.loads(result.stdout.strip())
        sys.stderr.write(f"Successfully fetched event with ID: {event_data.get('id', 'unknown')}\n")
        return event_data
        
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"Error fetching event: {e}\n")
        sys.stderr.write(f"stderr: {e.stderr}\n")
        return None
    except json.JSONDecodeError as e:
        sys.stderr.write(f"Invalid JSON response: {e}\n")
        sys.stderr.write(f"Response: {result.stdout}\n")
        return None
    except Exception as e:
        sys.stderr.write(f"Unexpected error fetching event: {e}\n")
        return None


def get_d_tag(tags: List[List[str]]) -> Optional[str]:
    """Find the d-tag value in the event tags."""
    for tag in tags:
        if tag and len(tag) > 1 and tag[0] == "d":
            return tag[1]
    return None


def update_event_tags(event: Dict, tag_values: List[str]) -> Dict:
    """Update the event tags with new t-tags."""
    if "tags" not in event:
        event["tags"] = []
    
    # Remove existing t-tags to avoid duplicates
    event["tags"] = [tag for tag in event["tags"] if not (tag and tag[0] == "t")]
    
    # Add new t-tags
    for val in tag_values:
        event["tags"].append(["t", val])
    
    return event


def sign_and_publish_event(event: Dict, private_key: str, relay: str = None) -> Dict:
    """Sign the event with the provided private key using nak and optionally publish it.
    
    Args:
        event: The event to sign
        private_key: The private key (hex or nsec format) for signing
        relay: Optional relay URL to publish to
        
    Returns:
        The signed event as a dictionary
    
    Raises:
        SystemExit: If signing or publishing fails
    """
    # Preserve the original event's structure, but remove fields that will be regenerated
    # (id, sig, pubkey) as they'll be replaced by the signing process
    signing_event = {
        "kind": event["kind"],
        "created_at": event["created_at"],  # Preserve original timestamp
        "content": event["content"],
        "tags": event["tags"],
    }
    
    try:
        # Set up nak event command with private key
        cmd = ["nak", "event", "--sec", private_key]
        
        # Add relay if publishing is requested
        if relay:
            cmd.append(relay)
            
        event_json = json.dumps(signing_event)
        
        sys.stderr.write(f"Signing event of kind {event['kind']}...\n")
        result = subprocess.run(
            cmd, 
            input=event_json, 
            capture_output=True, 
            text=True, 
            check=True
        )
        
        signed_event = json.loads(result.stdout.strip())
        
        if relay:
            sys.stderr.write(f"Published event to {relay}: {signed_event['id']}\n")
        else:
            sys.stderr.write(f"Event signed with ID: {signed_event['id']}\n")
            
        return signed_event
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"Error signing/publishing event: {e}\n")
        sys.stderr.write(f"stderr: {e.stderr}\n")
        sys.exit(1)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"Invalid JSON in signed event: {e}\n")
        sys.stderr.write(f"Response: {result.stdout}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Unexpected error during signing/publishing: {e}\n")
        sys.exit(1)


def validate_private_key(private_key: str) -> bool:
    """Validate that the provided private key is in a valid format.
    
    Args:
        private_key: The private key string to validate
        
    Returns:
        True if the key format appears valid, False otherwise
    """
    # Check for nsec format
    if private_key.startswith("nsec1"):
        return len(private_key) >= 60  # Approx length for nsec keys
        
    # Check for hex format
    if all(c in "0123456789abcdefABCDEF" for c in private_key):
        return len(private_key) == 64
        
    return False


def main():
    args = parse_args()

    # Validate the private key format
    if not validate_private_key(args.private_key):
        sys.stderr.write("Error: Invalid private key format. Must be hex (64 chars) or nsec1 format.\n")
        sys.exit(1)

    # Check if the mapping file exists
    if not os.path.isfile(args.map_yaml_file):
        sys.stderr.write(f"Error: Mapping file '{args.map_yaml_file}' does not exist or is not accessible.\n")
        sys.exit(1)

    # Load the mapping from the provided YAML file
    try:
        with open(args.map_yaml_file, "r") as mf:
            mapping = yaml.safe_load(mf)
            if mapping is None:
                sys.stderr.write(f"Error: Mapping file '{args.map_yaml_file}' is empty or invalid.\n")
                sys.exit(1)
    except yaml.YAMLError as e:
        sys.stderr.write(f"Error parsing YAML file: {e}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Error loading mapping file: {e}\n")
        sys.exit(1)

    # If the mapping is a list, convert it to a dictionary
    if isinstance(mapping, list):
        new_mapping = {}
        for item in mapping:
            if isinstance(item, dict):
                new_mapping.update(item)
            else:
                sys.stderr.write(f"Unexpected item in mapping list: {item}\n")
        mapping = new_mapping

    # Make sure we have at least one mapping
    if not mapping:
        sys.stderr.write("Error: No valid mappings found in the YAML file.\n")
        sys.exit(1)

    # Prepare output file if specified
    output_file = None
    if args.output:
        try:
            output_file = open(args.output, "w")
            sys.stderr.write(f"Writing output to '{args.output}'\n")
        except Exception as e:
            sys.stderr.write(f"Error opening output file: {e}\n")
            sys.exit(1)

    updated_events = []
    total_events = len(mapping)
    
    sys.stderr.write(f"Processing {total_events} events from mapping...\n")

    # Process each coordinate in the mapping
    for i, (coordinate, tag_values) in enumerate(mapping.items(), 1):
        try:
            sys.stderr.write(f"[{i}/{total_events}] Processing coordinate: {coordinate}\n")
            kind, pubkey, d_value = split_coordinate(coordinate)
            
            # Fetch the event
            event = fetch_event(kind, pubkey, d_value, args.relay)
            if not event:
                sys.stderr.write(f"Skipping coordinate {coordinate}: Event not found\n")
                continue
            
            # Verify the event has the expected d-tag
            event_d_tag = get_d_tag(event.get("tags", []))
            if event_d_tag != d_value:
                sys.stderr.write(f"Skipping coordinate {coordinate}: D-tag mismatch (expected={d_value}, found={event_d_tag})\n")
                continue
            
            # Update the event tags
            if isinstance(tag_values, list):
                updated_event = update_event_tags(event, tag_values)
                sys.stderr.write(f"Added {len(tag_values)} t-tags: {', '.join(tag_values)}\n")
            elif tag_values is not None:
                updated_event = update_event_tags(event, [tag_values])
                sys.stderr.write(f"Added t-tag: {tag_values}\n")
            else:
                sys.stderr.write(f"Skipping coordinate {coordinate}: No tag values\n")
                continue
            
            # Update timestamp if requested
            if args.update_timestamp:
                updated_event["created_at"] = int(time.time())
                sys.stderr.write(f"Updated timestamp to current time: {updated_event['created_at']}\n")
                
            # Sign the updated event and optionally publish it
            signed_event = sign_and_publish_event(
                updated_event, 
                args.private_key,
                args.relay if args.publish else None
            )
            
            # Save or print the updated event
            updated_events.append(signed_event)
            if output_file:
                output_file.write(json.dumps(signed_event) + "\n")
            else:
                print(json.dumps(signed_event))
                
        except ValueError as e:
            sys.stderr.write(f"Error processing coordinate {coordinate}: {e}\n")
            continue
        except Exception as e:
            sys.stderr.write(f"Unexpected error processing coordinate {coordinate}: {e}\n")
            continue

    # Close output file if opened
    if output_file:
        output_file.close()

    successful = len(updated_events)
    failed = total_events - successful
    sys.stderr.write(f"Summary: Successfully processed {successful} events, {failed} failed\n")


if __name__ == "__main__":
    main()
