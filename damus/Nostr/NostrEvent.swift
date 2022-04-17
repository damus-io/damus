//
//  NostrEvent.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import CommonCrypto
import secp256k1

struct OtherEvent {
    let event_id: String
    let relay_url: String
}

struct KeyEvent {
    let key: String
    let relay_url: String
}

struct ReferencedId {
    let ref_id: String
    let relay_id: String?
    let key: String
}

struct EventId: Identifiable, CustomStringConvertible {
    let id: String

    var description: String {
        id
    }
}

class NostrEvent: Codable, Identifiable {
    var id: String
    var sig: String
    var tags: [[String]]

    // cached field for pow calc
    var pow: Int?

    // custom flags for internal use
    var flags: Int = 0

    let pubkey: String
    let created_at: Int64
    let kind: Int
    let content: String

    private enum CodingKeys: String, CodingKey {
        case id, sig, tags, pubkey, created_at, kind, content
    }

    private func get_referenced_ids(key: String) -> [ReferencedId] {
        return tags.reduce(into: []) { (acc, tag) in
            if tag.count >= 2 && tag[0] == key {
                var relay_id: String? = nil
                if tag.count >= 3 {
                    relay_id = tag[2]
                }
                acc.append(ReferencedId(ref_id: tag[1], relay_id: relay_id, key: key))
            }
        }
    }

    public func references(id: String, key: String) -> Bool {
        for tag in tags {
            if tag.count >= 2 && tag[0] == key {
                if tag[1] == id {
                    return true
                }
            }
        }

        return false
    }

    public var is_reply: Bool {
        for tag in tags {
            if tag[0] == "e" {
                return true
            }
        }

        return false
    }
    
    public func reply_ids(pubkey: String) -> [ReferencedId] {
        var ids = self.referenced_ids
        ids.append(contentsOf: self.referenced_pubkeys)
        ids.append(ReferencedId(ref_id: self.id, relay_id: nil, key: "e"))
        ids.append(ReferencedId(ref_id: pubkey, relay_id: nil, key: "p"))
        return ids
    }
    
    public var referenced_ids: [ReferencedId] {
        return get_referenced_ids(key: "e")
    }

    public var referenced_pubkeys: [ReferencedId] {
        return get_referenced_ids(key: "p")
    }

    /// Make a local event
    public static func local(content: String, pubkey: String) -> NostrEvent {
        let ev = NostrEvent(content: content, pubkey: pubkey)
        ev.flags |= 1
        return ev
    }

    public var is_local: Bool {
        return (self.flags & 1) != 0
    }

    init(content: String, pubkey: String, kind: Int = 1, tags: [[String]] = []) {
        self.id = ""
        self.sig = ""

        self.content = content
        self.pubkey = pubkey
        self.kind = kind
        self.tags = tags
        self.created_at = Int64(Date().timeIntervalSince1970)

        self.calculate_id()
    }

    func calculate_id() {
        self.id = calculate_event_id(ev: self)
        self.pow = count_hash_leading_zero_bits(self.id)
    }

    // TODO: timeout
    /*
    func mine_id(pow: Int, done: @escaping (String) -> ()) {
        let nonce_ind = self.ensure_nonce_tag()
        let nonce: Int64 = 0

        DispatchQueue.global(qos: .background).async {
            while
        }
    }
     */

    private func ensure_nonce_tag() -> Int {
        for (i, tags) in self.tags.enumerated() {
            for tag in tags {
                if tags.count == 2 && tag == "nonce" {
                    return i
                }
            }
        }

        self.tags.append(["nonce", "0"])
        return self.tags.count - 1
    }

    func sign(privkey: String) {
        self.sig = sign_event(privkey: privkey, ev: self)
    }
}

func sign_event(privkey: String, ev: NostrEvent) -> String {
    let priv_key_bytes = try! privkey.byteArray()
    let key = try! secp256k1.Signing.PrivateKey(rawRepresentation: priv_key_bytes)

    // Extra params for custom signing

    var aux_rand = random_bytes(count: 64)
    var digest = try! ev.id.byteArray()

    // API allows for signing variable length messages
    let signature = try! key.schnorr.signature(message: &digest, auxiliaryRand: &aux_rand)

    return hex_encode(signature.rawRepresentation)
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

func event_commitment(ev: NostrEvent, tags: String) -> String {
    let encoder = JSONEncoder()
    let str_data = try! encoder.encode(ev.content)
    let content = String(decoding: str_data, as: UTF8.self)
    return "[0,\"\(ev.pubkey)\",\(ev.created_at),\(ev.kind),\(tags),\(content)]"
}

func calculate_event_id(ev: NostrEvent) -> String {
    let tags_encoder = JSONEncoder()
    let tags_data = try! tags_encoder.encode(ev.tags)
    let tags = String(decoding: tags_data, as: UTF8.self)

    let target = event_commitment(ev: ev, tags: tags)
    let target_data = target.data(using: .utf8)!
    let hash = sha256(target_data)

    return hex_encode(hash)
}


func sha256(_ data: Data) -> Data {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return Data(hash)
}

func hexchar(_ val: UInt8) -> UInt8 {
    if val < 10 {
        return 48 + val;
    }
    if val < 16 {
        return 97 + val - 10;
    }
    assertionFailure("impossiburu")
    return 0
}


func hex_encode(_ data: Data) -> String {
    var str = ""
    for c in data {
        let c1 = hexchar(c >> 4)
        let c2 = hexchar(c & 0xF)

        str.append(Character(Unicode.Scalar(c1)))
        str.append(Character(Unicode.Scalar(c2)))
    }
    return str
}



func random_bytes(count: Int) -> Data {
    var data = Data(count: count)
    _ = data.withUnsafeMutableBytes { mutableBytes in
        SecRandomCopyBytes(kSecRandomDefault, count, mutableBytes)
    }
    return data
}
