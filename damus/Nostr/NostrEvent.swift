//
//  NostrEvent.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

struct OtherEvent {
    let event_id: String
    let relay_url: String
}

struct KeyEvent {
    let key: String
    let relay_url: String
}

struct NostrEvent: Decodable, Identifiable {
    let id: String
    let pubkey: String
    let created_at: Int64
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String
}

func decode_nostr_event(txt: String) -> NostrResponse? {
    return decode_data(Data(txt.utf8))
}

func decode_data<T: Decodable>(_ data: Data) -> T? {
    let decoder = JSONDecoder()
    do {
        return try decoder.decode(T.self, from: data)
    } catch {
        print("decode_data failed for \(T.self): \(error)")
    }

    return nil
}
