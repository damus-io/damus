# DIP-05

## NIP-55 iOS Extension

This specification adapts NIP-55's signer protocol for iOS, enabling other iOS nostr apps to use Damus as their signer via URL schemes.

### Background

NIP-55 defines a signer protocol with two mechanisms:
1. **Android Intents** - Android-only, not applicable to iOS
2. **URL callbacks** - Originally for web apps, adapted here for iOS

This DIP documents iOS-specific requirements and deviations from NIP-55 web flows.

### URL Scheme

The `nostrsigner` URL scheme is used, matching NIP-55 for cross-platform recognition.

### Request Format

```
nostrsigner:<content>?type=<method>&callbackUrl=<url>&compressionType=<type>&returnType=<format>&pubkey=<hex>
```

#### Parameters

| Parameter | Required | Values | Description |
|-----------|----------|--------|-------------|
| `type` | Yes | `get_public_key`, `sign_event`, `nip04_encrypt`, `nip04_decrypt`, `nip44_encrypt`, `nip44_decrypt`, `decrypt_zap_event` | Operation to perform |
| `callbackUrl` | **Yes*** | URL-encoded callback | Where to send result (e.g., `primal://nostrsigner`) |
| `compressionType` | No | `none` (default), `gzip` | Encoding for `event` parameter in response |
| `returnType` | No | `signature`, `event` | For sign_event: return just sig or full event |
| `pubkey` | For encrypt/decrypt | hex | Target pubkey for encryption operations |

**\*iOS Deviation**: `callbackUrl` is required on iOS. NIP-55 allows clipboard fallback for web apps, but iOS does not support clipboard sharing between apps.

#### Content

The `<content>` portion is URL-encoded, matching NIP-55.

| Operation | Content |
|-----------|---------|
| `sign_event` | Unsigned event JSON `{"kind":1,"content":"...","tags":[],"created_at":123}` |
| `nip04_encrypt`, `nip44_encrypt` | Plaintext string to encrypt |
| `nip04_decrypt`, `nip44_decrypt` | NIP-04/44 ciphertext string |
| `get_public_key` | Empty or omitted |
| `decrypt_zap_event` | Encrypted zap event (NIP-04/44 ciphertext) |

### Response Format

The signer opens the callback URL with query parameters appended.

#### Query Parameter Appending

If the `callbackUrl` already contains query parameters, append with `&`. Otherwise, append with `?`.

```
# callbackUrl has no params:
primal://nostrsigner  →  primal://nostrsigner?result=<sig>

# callbackUrl already has params:
primal://callback?session=123  →  primal://callback?session=123&result=<sig>
```

#### Response Encoding

The `event` parameter encoding depends on `compressionType`:

| `compressionType` | `event` parameter |
|-------------------|-------------------|
| `none` (default) | URL-encoded JSON |
| `gzip` | `Signer1` + base64(gzip(JSON)) |

The `result` parameter encoding depends on operation type:

| Operation | `result` encoding |
|-----------|-------------------|
| `get_public_key` | Hex pubkey |
| `sign_event` | Hex signature |
| `nip04_encrypt`, `nip44_encrypt` | NIP-04/44 ciphertext string |
| `nip04_decrypt`, `nip44_decrypt` | Decrypted plaintext |
| `decrypt_zap_event` | Decrypted JSON string |

All response parameter values MUST be URL-encoded. Hex strings are inherently URL-safe. The `event` parameter contains JSON and MUST always be URL-encoded.

#### Success Response

| Parameter | Condition | Value |
|-----------|-----------|-------|
| `result` | Always | Operation result (see encoding table above) |
| `event` | `returnType=event` | Full signed event |

#### Error Response

| Parameter | Value |
|-----------|-------|
| `error` | Error code |
| `rejected` | `true` if user explicitly rejected |

Error codes: `user_rejected`, `invalid_content`, `invalid_callback`, `unsupported_type`, `invalid_pubkey`, `internal_error`

### Example Flow

```
1. Primal wants to post a note
2. Primal opens:
   nostrsigner:%7B%22kind%22%3A1%2C%22content%22%3A%22Hello%22%7D?type=sign_event&callbackUrl=primal%3A%2F%2Fnostrsigner&returnType=event

3. iOS switches to Damus
4. Damus parses request, shows approval UI
5. User approves
6. Damus signs event, opens:
   primal://nostrsigner?result=abc123...&event=%7B%22id%22%3A%22...%22%2C%22sig%22%3A%22abc123...%22%7D

7. iOS switches back to Primal with signed event
```

### Security Considerations

1. **Callback URL validation**: Reject dangerous schemes (`file://`, `javascript://`, `data://`, `about://`, `blob://`, `nostrsigner://`)

2. **Re-entrancy prevention**: Reject requests where `callbackUrl` uses `nostrsigner` scheme to prevent infinite loops.

3. **User approval**: All signing requests MUST show approval UI before signing.

### Client Identification

The client is identified from `callbackUrl` for permission tracking:
1. Use `callbackUrl.host` if present (e.g., `primal` from `primal://nostrsigner`)
2. Fallback to `callbackUrl.scheme` if host is empty
3. Fallback to `"unknown"` if both are empty

### iOS Implementation Notes

- Register `nostrsigner` scheme in `Info.plist`
- Handle incoming URLs via SwiftUI's `.onOpenURL` modifier
- Return results using `UIApplication.shared.open(callbackUrl)`
- Requesting apps must add `nostrsigner` to `LSApplicationQueriesSchemes`

### Differences from NIP-55

| Aspect | NIP-55 Web | DIP-05 iOS |
|--------|------------|------------|
| `callbackUrl` | Optional (clipboard fallback) | **Required** |
| Inter-app communication | Browser navigation | iOS URL schemes |

### References

- [NIP-55: Android Signer Application](https://github.com/nostr-protocol/nips/blob/master/55.md)
