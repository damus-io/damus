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

class NostrEvent: Codable, Identifiable, CustomStringConvertible {
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
    
    lazy var blocks: [Block] = {
        return parse_mentions(content: self.content, tags: self.tags)
    }()
    
    var description: String {
        let p = pow.map { String($0) } ?? "?"
        return "NostrEvent { id: \(id) pubkey \(pubkey) kind \(kind) tags \(tags) pow \(p) content '\(content)' }"
    }
    
    var known_kind: NostrKind? {
        return NostrKind.init(rawValue: kind)
    }

    private enum CodingKeys: String, CodingKey {
        case id, sig, tags, pubkey, created_at, kind, content
    }

    private func get_referenced_ids(key: String) -> [ReferencedId] {
        return damus.get_referenced_ids(tags: self.tags, key: key)
    }
    
    public func is_root_event() -> Bool {
        for tag in tags {
            if tag.count >= 1 && tag[0] == "e" {
                return false
            }
        }
        return true
    }
    
    /// find a non-root reply
    public func find_direct_reply() -> String? {
        var i = tags.count - 1
        var first: String? = nil
        var matches: Int = 0
        
        while i >= 0 {
            let tag = tags[i]
            if tag.count >= 2 && tag[0] == "e" {
                if first == nil {
                    first = tag[1]
                }
                matches += 1
            }
            i -= 1
        }
        
        if matches <= 1 {
            return nil
        }
        
        return first
    }
    
    public func last_refid() -> ReferencedId? {
        var mlast: Int? = nil
        var i: Int = 0
        for tag in tags {
            if tag.count >= 2 && tag[0] == "e" {
                mlast = i
            }
            i += 1
        }
        
        guard let last = mlast else {
            return nil
        }
        
        return tag_to_refid(tags[last])
    }
    
    public func directly_references(_ id: String) -> Bool {
        // conditions: if it only has 1 e ref
        // OR it has more than 1 e ref, ignoring the first
        
        var nrefs = 0
        var i = 0
        var first_matched = false
        var matched = true
        
        for tag in tags {
            if tag.count >= 2 && tag[0] == "e" {
                nrefs += 1
                if tag[1] == id {
                    matched = true
                    first_matched = nrefs == 1
                }
            }
            i += 1
        }
        
        return (nrefs == 1 && matched) || (nrefs > 1 && matched && !first_matched)
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
    
    public var referenced_ids: [ReferencedId] {
        return get_referenced_ids(key: "e")
    }
    
    public var reply_description: ([String], Int) {
        var c = 0
        var ns: [String] = []
        var i = tags.count - 1
        
        while i >= 0 {
            let tag = tags[i]
            if tag.count >= 2 && tag[0] == "p" {
                c += 1
                if ns.count < 2 {
                    ns.append(tag[1])
                }
            }
            i -= 1
        }
        
        return (ns, c)
    }
    
    public func count_ids() -> Int {
        return count_refs("e")
    }
    
    public func count_refs(_ type: String) -> Int {
        var count: Int = 0
        for tag in tags {
            if tag.count >= 2 && tag[0] == "e" {
                count += 1
            }
        }
        return count
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
    encoder.outputFormatting = .withoutEscapingSlashes
    let str_data = try! encoder.encode(ev.content)
    let content = String(decoding: str_data, as: UTF8.self)
    let commit = "[0,\"\(ev.pubkey)\",\(ev.created_at),\(ev.kind),\(tags),\(content)]"
    //print("COMMIT", commit)
    return commit
}

func calculate_event_id(ev: NostrEvent) -> String {
    let tags_encoder = JSONEncoder()
    tags_encoder.outputFormatting = .withoutEscapingSlashes
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

func refid_to_tag(_ ref: ReferencedId) -> [String] {
    var tag = [ref.key, ref.ref_id]
    if let relay_id = ref.relay_id {
        tag.append(relay_id)
    }
    return tag
}

func tag_to_refid(_ tag: [String]) -> ReferencedId? {
    if tag.count == 0 {
        return nil
    }
    if tag.count == 1 {
        return nil
    }
    
    var relay_id: String? = nil
    if tag.count > 2 {
        relay_id = tag[2]
    }
    
    return ReferencedId(ref_id: tag[1], relay_id: relay_id, key: tag[0])
}

func parse_reply_refs(tags: [[String]]) -> ReplyRefs? {
    let ids = get_referenced_ids(tags: tags, key: "e")
    
    if ids.count == 0 {
        return nil
    }
    
    let first = ids.first!
    let last = ids.last!
    
    return ReplyRefs(thread_id: first.ref_id, direct_reply: last.ref_id)
}
    
func get_referenced_ids(tags: [[String]], key: String) -> [ReferencedId] {
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


func make_like_event(pubkey: String, liked: NostrEvent) -> NostrEvent? {
    var tags: [[String]]
    
    if let refs = parse_reply_refs(tags: liked.tags) {
        if refs.thread_id == refs.direct_reply {
            tags = [["e", refs.thread_id], ["e", liked.id]]
        } else {
            tags = [["e", refs.thread_id], ["e", refs.direct_reply], ["e", liked.id]]
        }
    } else {
        // root event
        tags = [["e", liked.id]]
    }
    
   
    return NostrEvent(content: "", pubkey: pubkey, kind: 7, tags: tags)
}

func gather_reply_ids(our_pubkey: String, from: NostrEvent) -> [ReferencedId] {
    var ids = get_referenced_ids(tags: from.tags, key: "e").first.map { [$0] } ?? []
    
    ids.append(ReferencedId(ref_id: from.id, relay_id: nil, key: "e"))
    ids.append(contentsOf: from.referenced_pubkeys.filter { $0.ref_id != our_pubkey })
    if from.pubkey != our_pubkey {
        ids.append(ReferencedId(ref_id: from.pubkey, relay_id: nil, key: "p"))
    }
    return ids
}

