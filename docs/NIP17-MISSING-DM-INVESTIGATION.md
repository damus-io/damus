# NIP-17 Missing DM Investigation

**Date**: 2026-02-04
**Issue**: jb55's DM sent via notedeck not received in Damus iOS
**Status**: Under investigation

---

## Summary

A NIP-17 direct message sent from jb55 (using notedeck) to the test user was never received in Damus iOS.

**Key observation**: Other NIP-17 DMs (from 0xchat, nospeak) ARE arriving successfully. This indicates:
- The NIP-17 receive pipeline works (key registration, unwrap, display)
- The failure is **sender-specific** (notedeck/jb55), not a global NIP-17 issue

**What we know**:
1. Relay overlap exists between sender 10002 and receiver 10050
2. Other senders' messages arrive and display correctly
3. Multiple gift wraps for receiver exist on shared relays

**What we DON'T know** (gaps to fill):
1. Whether notedeck actually sent to receiver's 10050 relays
2. Whether Damus was connected to those relays at send time
3. Whether the gift wrap exists on any relay post-send
4. Whether `since` filtering dropped the message
5. Whether AUTH requirements blocked delivery

---

## Environment

### Receiver (Damus iOS)
- **Pubkey**: `fa486cb1ff142934ed9094c8ac2dc6ac7ef76e29a6cad67860882ca1decf6152`
- **npub**: `npub1lfyxev0lzs5nfmvsjny2ctwx43l0wm3f5m9dv7rq3qk2rhk0v9fqh6dk9l`

### Sender (notedeck)
- **Pubkey**: `32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245` (jb55)
- **Client**: notedeck (damus-io/notedeck)
- **Message content**: "works"

---

## Relay Configuration (Verified via `nak`)

### Receiver's Relay Lists

**kind:10002 (NIP-65 Relay List)**
```
wss://nos.lol
wss://nostr.wine
wss://relay.damus.io
wss://relay.primal.net
wss://nostr.land
```

**kind:10050 (NIP-17 DM Relay List)**
```
wss://nos.lol
wss://nostr.wine
wss://relay.damus.io
```

### Sender's Relay Lists

**kind:10002 (NIP-65 Relay List)**
```
ws://relay.jb55.com
wss://nos.lol
wss://nostr.land
wss://nostr.wine
wss://relay.damus.io
wss://relay.nostr.band
```

**kind:10050 (NIP-17 DM Relay List)**
```
(not published)
```

### Relay Overlap Analysis

| Relay | Receiver 10050 | Sender 10002 | Overlap |
|-------|----------------|--------------|---------|
| wss://nos.lol | ✓ | ✓ | **YES** |
| wss://nostr.wine | ✓ | ✓ | **YES** |
| wss://relay.damus.io | ✓ | ✓ | **YES** |
| wss://relay.primal.net | (10002 only) | ✗ | no |
| wss://nostr.land | (10002 only) | ✓ | n/a |
| ws://relay.jb55.com | ✗ | ✓ | no |
| wss://relay.nostr.band | ✗ | ✓ | no |

**Conclusion**: 3 relays overlap (nos.lol, nostr.wine, relay.damus.io). Relay mismatch is NOT the root cause.

---

## What Works

1. **Inbound from 0xchat**: Messages from `npub1zafcms4xya5...` arrive and display correctly
2. **Inbound from nospeak**: Messages from `npub18lp30xf7ag6...` arrive and display correctly
3. **Outbound NIP-17**: Sending NIP-17 messages works (confirmed by recipients)
4. **Gift wrap presence**: Multiple kind:1059 events for receiver exist on nos.lol

---

## What Doesn't Work

1. **jb55's message**: Never appears in logs or UI
2. **No unwrap attempt**: Logs show no `unwrap: SUCCESS` or `unwrap: FAIL` for jb55's pubkey

---

## Debug Logs (Receiver)

Messages successfully received and processed:
```
[DM-DEBUG] unwrap: SUCCESS rumor from:npub1zafcms4xya5 content:'Test send via 0xchat'
[DM-DEBUG] unwrap: SUCCESS rumor from:npub1zafcms4xya5 content:'0xchatt'
[DM-DEBUG] unwrap: SUCCESS rumor from:npub1zafcms4xya5 content:'Uno mas'
[DM-DEBUG] unwrap: SUCCESS rumor from:npub18lp30xf7ag6 content:'nospeak test'
```

**No log entries for jb55's pubkey** (`32e1827635450ebb...` / `npub1xtscya34g58...`)

---

## Hypotheses (Prioritized)

### H0: Gift wrap filtered by `since` optimization (MOST LIKELY)
- NIP-17 randomizes `created_at` up to 2 days in the past
- Damus DM subscriptions use `since = latestTimestamp - 120s`
- If jb55's gift wrap had old randomized timestamp, relay would exclude it
- **Evidence needed**: Compare gift wrap `created_at` vs subscription `since` value
- **Test**: Query relay with NO `since` filter for gift wraps after send time

### H1: Notedeck did not fetch/honor recipient's 10050
- NIP-17 spec: "send to recipient's kind:10050 relays"
- If notedeck sends only to sender's relays, overlap is coincidental
- **Evidence needed**: notedeck logs showing 10050 fetch and relay targets
- **Question for notedeck**: Does it fetch recipient 10050 before sending?

### H2: Damus not connected to DM relays at send time
- Relay overlap in config ≠ active connections
- **Evidence needed**: Damus connection logs at send time
- **Test**: Log active relay connections during resend test

### H3: AUTH requirement blocked delivery (UNLIKELY)
- nos.lol and relay.damus.io do NOT require AUTH
- nostr.wine status unknown but likely same
- **Deprioritized**: AUTH is unlikely to be the cause

### H4: Notedeck send failed silently
- Send may have errored without user feedback
- **Evidence needed**: notedeck send logs/confirmation
- **Test**: Have jb55 resend while monitoring both clients

### H5: Gift wrap exists but failed to unwrap
- Less likely since other messages unwrap fine
- **Evidence needed**: Query relays for all gift wraps, attempt manual unwrap
- **Complication**: Gift wraps use ephemeral keys, can't identify sender without unwrapping

---

## Questions for notedeck team

1. **Send confirmation**: Does notedeck log successful gift wrap publication?
2. **Relay selection**: Which relays does notedeck send DMs to?
   - Sender's 10002?
   - Recipient's 10050 (if fetched)?
   - Hardcoded list?
3. **10050 fetching**: Does notedeck fetch recipient's kind:10050 before sending?
4. **Error handling**: Would notedeck show an error if send failed?

---

## Focused Tests

### Test 1: Coordinated Resend with Full Logging
1. Have jb55 resend "works" at a known UTC time
2. Capture Damus logs during send window, looking for:
   - `dmsStream: Received gift_wrap ...` lines
   - Any AUTH log lines
   - Connection status to DM relays
3. Record exact time window (UTC) for correlation

### Test 2: Post-Send Relay Query (No `since` filter)
```bash
# Query each DM relay for gift wraps AFTER the resend time
nak req -k 1059 -p <receiver_hex> --since <send_timestamp> wss://nos.lol wss://nostr.wine wss://relay.damus.io
```
- Record all event IDs and `created_at` values
- Note: `created_at` may be randomized up to 2 days in past

### Test 3: Connection Verification
- Log which relays Damus was actually connected to at send time
- Verify connection to all three DM relays (nos.lol, nostr.wine, relay.damus.io)

### Test 4: Gift Wrap Comparison
- Take a known-good gift wrap from 0xchat/nospeak
- Compare: relay source, `created_at` skew, structure
- Check if jb55's gift wrap (if found) differs in any way

### Test 5: AUTH Check
- Verify whether Damus performed AUTH on DM relays
- Check if any DM relay requires AUTH for kind:1059

---

## Questions for notedeck Team

1. **10050 Fetching**: Does notedeck fetch recipient's kind:10050 before sending? Is this logged?
2. **Relay Targets**: Which relays did notedeck actually publish the gift wrap to for this send?
3. **Error Handling**: Was there any error/timeout or retry behavior? Would user see it?
4. **Timestamp Randomization**: Does notedeck randomize gift wrap/seal `created_at` up to 2 days like spec?
5. **AUTH**: Does notedeck require or perform relay AUTH for DM operations?

---

## Questions for Damus iOS (Self-Check)

1. Were you authenticated to nos.lol / nostr.wine / relay.damus.io at send time?
2. Did your DM subscription use a `since` filter at the time of the send? (likely yes - this is the prime suspect)
3. Were you connected to all three DM relays, or just a subset?
4. Is there a `dmsStream: Received gift_wrap` log line for any event around the send time?

---

## Requested Actions

### From jb55/notedeck side:
1. Check if send showed success in notedeck UI
2. Provide notedeck debug logs from the send attempt (especially relay targets)
3. Confirm whether notedeck fetched recipient's 10050
4. Resend "works" message at coordinated time while receiver monitors logs
5. Confirm which relays notedeck actually sent to

### From Damus iOS side:
1. Query overlapping relays with NO `since` filter for gift wraps after send time
2. Log active relay connections during resend test
3. Check AUTH status on DM relays
4. Search logs for `gift_wrap` receipt (not just unwrap success)
5. Compare timestamps of received vs missing messages

---

## Related Issues

- **damus-xco**: Notedeck→iOS NIP-17 flow investigation
- **damus-h2p**: jb55 inbound DM not received

---

## References

- NIP-17 spec: https://github.com/nostr-protocol/nips/blob/master/17.md
- notedeck NIP-17 impl: https://github.com/damus-io/notedeck/tree/master/crates/notedeck_messages/src/nip17
- Damus iOS NIP-17 impl: `damus/Core/NIPs/NIP17/NIP17.swift`
