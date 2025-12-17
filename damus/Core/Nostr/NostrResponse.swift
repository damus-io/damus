//
//  NostrResponse.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

struct CommandResult {
    let event_id: NoteId
    let ok: Bool
    let msg: String
}

enum MaybeResponse {
    case bad
    case ok(NostrResponse)
}

/// NIP-77 NEG-MSG response from relay
struct NegentropyResponse {
    let sub_id: String
    let message: String  // hex-encoded negentropy message
}

/// NIP-77 NEG-ERR response from relay
struct NegentropyError {
    let sub_id: String
    let reason: String
}

/// NIP-01 CLOSED response - relay closed a subscription
struct SubscriptionClosed {
    let sub_id: String
    let message: String

    /// Check if the closure was due to rate limiting
    var isRateLimited: Bool {
        message.hasPrefix("rate-limited:")
    }

    /// Check if the closure was due to an error
    var isError: Bool {
        message.hasPrefix("error:")
    }
}

enum NostrResponse {
    case event(String, NostrEvent)
    case notice(String)
    case eose(String)
    case ok(CommandResult)
    /// An [NIP-42](https://github.com/nostr-protocol/nips/blob/master/42.md) `auth` challenge.
    ///
    /// The associated type of this case is the challenge string sent by the server.
    case auth(String)
    /// NIP-77 negentropy message response
    case negMsg(NegentropyResponse)
    /// NIP-77 negentropy error response
    case negErr(NegentropyError)
    /// NIP-01 CLOSED - relay closed a subscription (e.g., rate limiting, error)
    case closed(SubscriptionClosed)

    var subid: String? {
        switch self {
        case .ok:
            return nil
        case .event(let sub_id, _):
            return sub_id
        case .eose(let sub_id):
            return sub_id
        case .notice:
            return nil
        case .auth(let challenge_string):
            return challenge_string
        case .negMsg(let response):
            return response.sub_id
        case .negErr(let error):
            return error.sub_id
        case .closed(let closed):
            return closed.sub_id
        }
    }

    /// Try to parse messages that nostrdb doesn't support (NIP-77 negentropy, CLOSED)
    static func parse_extended(json: String) -> NostrResponse? {
        // Quick check for messages we handle here
        guard json.hasPrefix("[\"NEG-") || json.hasPrefix("[\"CLOSED\"") else { return nil }

        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 2,
              let msgType = array[0] as? String,
              let subId = array[1] as? String else {
            return nil
        }

        switch msgType {
        case "NEG-MSG":
            guard array.count >= 3,
                  let message = array[2] as? String else {
                return nil
            }
            return .negMsg(NegentropyResponse(sub_id: subId, message: message))

        case "NEG-ERR":
            guard array.count >= 3,
                  let reason = array[2] as? String else {
                return nil
            }
            return .negErr(NegentropyError(sub_id: subId, reason: reason))

        case "CLOSED":
            // NIP-01: ["CLOSED", <subscription_id>, <message>]
            let message = array.count >= 3 ? (array[2] as? String ?? "") : ""
            return .closed(SubscriptionClosed(sub_id: subId, message: message))

        default:
            return nil
        }
    }

    static func owned_from_json(json: String) -> NostrResponse? {
        // Try extended messages first (nostrdb doesn't support them)
        if let extResponse = parse_extended(json: json) {
            return extResponse
        }

        return json.withCString{ cstr in
            let bufsize: Int = max(Int(Double(json.utf8.count) * 8.0), Int(getpagesize()))
            let data = malloc(bufsize)

            if data == nil {
                let r: NostrResponse? = nil
                return r
            }
            //guard var json_cstr = json.cString(using: .utf8) else { return nil }

            //json_cs
            var tce = ndb_tce()

            let len = ndb_ws_event_from_json(cstr, Int32(json.utf8.count), &tce, data, Int32(bufsize), nil)
            if len <= 0 {
                free(data)
                return nil
            }

            switch tce.evtype {
            case NDB_TCE_OK:
                defer { free(data) }

                guard let evid_str = sized_cstr(cstr: tce.subid, len: tce.subid_len),
                      let evid = hex_decode_noteid(evid_str),
                      let msg  = sized_cstr(cstr: tce.command_result.msg, len: tce.command_result.msglen) else {
                    return nil
                }
                let cr = CommandResult(event_id: evid, ok: tce.command_result.ok == 1, msg: msg)

                return .ok(cr)
            case NDB_TCE_EOSE:
                defer { free(data) }

                guard let subid = sized_cstr(cstr: tce.subid, len: tce.subid_len) else {
                    return nil
                }
                return .eose(subid)
            case NDB_TCE_EVENT:

                // Create new Data with just the valid bytes
                guard let note_data = realloc(data, Int(len)) else {
                    free(data)
                    return nil
                }
                let new_note = ndb_note_ptr(ptr: OpaquePointer(note_data))
                let note = NdbNote(note: new_note, size: Int(len), owned: true, key: nil)

                guard let subid = sized_cstr(cstr: tce.subid, len: tce.subid_len) else {
                    free(data)
                    return nil
                }
                return .event(subid, note)
            case NDB_TCE_NOTICE:
                free(data)
                return .notice("")
            case NDB_TCE_AUTH:
                defer { free(data) }

                guard let challenge_string = sized_cstr(cstr: tce.subid, len: tce.subid_len) else {
                    return nil
                }
                return .auth(challenge_string)
            default:
                free(data)
                return nil
            }
        }
    }
}

func sized_cstr(cstr: UnsafePointer<CChar>, len: Int32) -> String? {
    let msgbuf = Data(bytes: cstr, count: Int(len))
    return String(data: msgbuf, encoding: .utf8)
}

