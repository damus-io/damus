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

enum NegentropyResponse {
    /// Negentropy error
    case error(subscriptionId: String, reasonCodeString: String)
    /// Negentropy message
    case message(subscriptionId: String, data: [UInt8])
    /// Invalid negentropy message
    case invalidResponse(subscriptionId: String)
    
    var subscriptionId: String {
        switch self {
        case .error(subscriptionId: let subscriptionId, reasonCodeString: _):
            return subscriptionId
        case .message(subscriptionId: let subscriptionId, data: _):
            return subscriptionId
        case .invalidResponse(subscriptionId: let subscriptionId):
            return subscriptionId
        }
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
    /// Negentropy error
    case negentropyError(subscriptionId: String, reasonCodeString: String)
    /// Negentropy message
    case negentropyMessage(subscriptionId: String, hexEncodedData: String)

    var subid: String? {
        switch self {
        case .ok:
            return nil
        case .event(let sub_id, _):
            return sub_id
        case .eose(let sub_id):
            return sub_id
        case .notice(_):
            return nil
        case .auth(let challenge_string):
            return challenge_string
        case .negentropyError(subscriptionId: let subscriptionId, reasonCodeString: _):
            return subscriptionId
        case .negentropyMessage(subscriptionId: let subscriptionId, hexEncodedData: _):
            return subscriptionId
        }
    }
    
    var negentropyResponse: NegentropyResponse? {
        switch self {
        case .event(_, _):
            return nil
        case .notice(_):
            return nil
        case .eose(_):
            return nil
        case .ok(_):
            return nil
        case .auth(_):
            return nil
        case .negentropyError(subscriptionId: let subscriptionId, reasonCodeString: let reasonCodeString):
            return .error(subscriptionId: subscriptionId, reasonCodeString: reasonCodeString)
        case .negentropyMessage(subscriptionId: let subscriptionId, hexEncodedData: let hexData):
            if let bytes = hex_decode(hexData) {
                return .message(subscriptionId: subscriptionId, data: bytes)
            }
            return .invalidResponse(subscriptionId: subscriptionId)
        }
    }

    static func owned_from_json(json: String) -> NostrResponse? {
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
