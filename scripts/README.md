# Profile Bootstrap Generation Scripts

Scripts to generate the profile-bootstrap.jsonl bundle for Damus pre-caching.

## Quick Start

### Option 1: Using nak (recommended)

```bash
# Install nak (Nostr Army Knife)
go install github.com/fiatjaf/nak@latest

# Generate the bundle
./generate_profile_bootstrap.sh > profile-bootstrap.jsonl
```

### Option 2: Manual

1. Use any Nostr client or relay browser
2. Fetch kind 3 events for the 9 root npubs
3. Extract all p-tags (followed pubkeys)
4. Fetch kind 0 events for all discovered pubkeys
5. Save as JSONL (one JSON object per line)

## Root NPubs

The 9 root users for WOT scoring:

```
npub1g53mukxnjkcmr94fhryzkqutdz2ukq4ks0gvy5af25rgmwsl4ngq43drvk
npub1v0lxxxxutpvrelsksy8cdhgfux9l6a42hsj2qzquu2zk7vc9qnkszrqj49
npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6
npub1xtscya34g58tk0z605fvr788k263gsu6cy9x0mhnm87echrgufzsevkk5s
npub1s05p3ha7en49dv8429tkk07nnfa9pcwczkf5x5qrdraqshxdje9sq6eyhe
npub13kwjkaunpmj5aslyd7hhwnwaqswmknj25dddglqztzz29pkavhaq25wg2a
npub1995y964wmxl94crx3ksfley24szjr390skdd237ex9z7ttp5c9lqld8vtf
npub1hu3hdctm5nkzd8gslnyedfr5ddz3z547jqcl5j88g4fame2jd08qh6h8nh
npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9
```

## Output Format

JSONL file containing:
- Kind 3 events (contact lists) from root users
- Kind 0 events (profiles) for all discovered users
- Sorted by created_at timestamp
- One JSON event per line

## Usage in Damus

Once generated, place `profile-bootstrap.jsonl` in the app bundle and load on first launch.
