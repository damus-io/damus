//
//  NostrEvent.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import CommonCrypto
import secp256k1
import secp256k1_implementation
import CryptoKit

struct OtherEvent {
    let event_id: String
    let relay_url: String
}

struct KeyEvent {
    let key: String
    let relay_url: String
}

struct ReferencedId: Identifiable, Hashable {
    let ref_id: String
    let relay_id: String?
    let key: String

    var id: String {
        return ref_id
    }
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
    var boosted_by: String?

    // cached field for pow calc
    var pow: Int?

    // custom flags for internal use
    var flags: Int = 0

    let pubkey: String
    let created_at: Int64
    let kind: Int
    let content: String
    
    var is_textlike: Bool {
        return kind == 1 || kind == 42
    }
    
    var too_big: Bool {
        return self.content.count > 32000
    }
    
    var should_show_event: Bool {
        return !too_big
    }

    private var _blocks: [Block]? = nil
    func blocks(_ privkey: String?) -> [Block] {
        if let bs = _blocks {
            return bs
        }
        let blocks = parse_mentions(content: self.get_content(privkey), tags: self.tags)
        self._blocks = blocks
        return blocks
    }

    lazy var inner_event: NostrEvent? = {
        return event_from_json(dat: self.content)
    }()

    private var _event_refs: [EventRef]? = nil
    func event_refs(_ privkey: String?) -> [EventRef] {
        if let rs = _event_refs {
            return rs
        }
        let refs = interpret_event_refs(blocks: self.blocks(privkey), tags: self.tags)
        self._event_refs = refs
        return refs
    }

    var decrypted_content: String? = nil

    func decrypted(privkey: String?) -> String? {
        if let decrypted_content = decrypted_content {
            return decrypted_content
        }

        guard let key = privkey else {
            return nil
        }
        
        guard let our_pubkey = privkey_to_pubkey(privkey: key) else {
            return nil
        }
        
        var pubkey = self.pubkey
        // This is our DM, we need to use the pubkey of the person we're talking to instead
        if our_pubkey == pubkey {
            guard let refkey = self.referenced_pubkeys.first else {
                return nil
            }
            
            pubkey = refkey.ref_id
        }

        let dec = decrypt_dm(key, pubkey: pubkey, content: self.content)
        self.decrypted_content = dec

        return dec
    }

    func get_content(_ privkey: String?) -> String {
        if known_kind == .dm {
            return decrypted(privkey: privkey) ?? "*failed to decrypt content*"
        }
        return content
    }

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

    public func direct_replies(_ privkey: String?) -> [ReferencedId] {
        return event_refs(privkey).reduce(into: []) { acc, evref in
            if let direct_reply = evref.is_direct_reply {
                acc.append(direct_reply)
            }
        }
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

    func is_reply(_ privkey: String?) -> Bool {
        return event_is_reply(self, privkey: privkey)
    }

    public var referenced_ids: [ReferencedId] {
        return get_referenced_ids(key: "e")
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

    init(from: NostrEvent, content: String? = nil) {
        self.id = from.id
        self.sig = from.sig

        self.content = content ?? from.content
        self.pubkey = from.pubkey
        self.kind = from.kind
        self.tags = from.tags
        self.created_at = from.created_at
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
    let priv_key_bytes = try! privkey.bytes
    let key = try! secp256k1.Signing.PrivateKey(rawRepresentation: priv_key_bytes)

    // Extra params for custom signing

    var aux_rand = random_bytes(count: 64)
    var digest = try! ev.id.bytes

    // API allows for signing variable length messages
    let signature = try! key.schnorr.signature(message: &digest, auxiliaryRand: &aux_rand)

    return hex_encode(signature.rawRepresentation)
}

func decode_nostr_event(txt: String) -> NostrResponse? {
    return decode_data(Data(txt.utf8))
}

func encode_json<T: Encodable>(_ val: T) -> String? {
    let encoder = JSONEncoder()
    return (try? encoder.encode(val)).map { String(decoding: $0, as: UTF8.self) }
}

func decode_json<T: Decodable>(_ val: String) -> T? {
    return try? JSONDecoder().decode(T.self, from: Data(val.utf8))
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

func get_referenced_id_set(tags: [[String]], key: String) -> Set<ReferencedId> {
    return tags.reduce(into: Set()) { (acc, tag) in
        if tag.count >= 2 && tag[0] == key {
            var relay_id: String? = nil
            if tag.count >= 3 {
                relay_id = tag[2]
            }
            acc.insert(ReferencedId(ref_id: tag[1], relay_id: relay_id, key: key))
        }
    }
}

func make_first_contact_event(keypair: Keypair) -> NostrEvent? {
    guard let privkey = keypair.privkey else {
        return nil
    }

    let rw_relay_info = RelayInfo(read: true, write: true)
    let relays: [String: RelayInfo] = ["wss://relay.damus.io": rw_relay_info]
    let relay_json = encode_json(relays)!
    let damus_pubkey = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
    let tags = [
        ["p", damus_pubkey],
        ["p", keypair.pubkey] // you're a friend of yourself!
    ]
    let ev = NostrEvent(content: relay_json,
                        pubkey: keypair.pubkey,
                        kind: NostrKind.contacts.rawValue,
                        tags: tags)
    ev.calculate_id()
    ev.sign(privkey: privkey)
    return ev
}

func make_metadata_event(keypair: Keypair, metadata: NostrMetadata) -> NostrEvent? {
    guard let privkey = keypair.privkey else {
        return nil
    }

    let metadata_json = encode_json(metadata)!
    let ev = NostrEvent(content: metadata_json,
                        pubkey: keypair.pubkey,
                        kind: NostrKind.metadata.rawValue,
                        tags: [])

    ev.calculate_id()
    ev.sign(privkey: privkey)
    return ev
}

func make_boost_event(pubkey: String, privkey: String, boosted: NostrEvent) -> NostrEvent {
    var tags: [[String]] = boosted.tags.filter { tag in tag.count >= 2 && (tag[0] == "e" || tag[0] == "p") }
    tags.append(["e", boosted.id])
    tags.append(["p", boosted.pubkey])

    let ev = NostrEvent(content: event_to_json(ev: boosted), pubkey: pubkey, kind: 6, tags: tags)
    ev.calculate_id()
    ev.sign(privkey: privkey)
    return ev
}

func make_like_event(pubkey: String, privkey: String, liked: NostrEvent) -> NostrEvent {
    var tags: [[String]] = liked.tags.filter { tag in tag.count >= 2 && (tag[0] == "e" || tag[0] == "p") }
    tags.append(["e", liked.id])
    tags.append(["p", liked.pubkey])
    let ev = NostrEvent(content: "", pubkey: pubkey, kind: 7, tags: tags)
    ev.calculate_id()
    ev.sign(privkey: privkey)

    return ev
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

func event_from_json(dat: String) -> NostrEvent? {
    return try? JSONDecoder().decode(NostrEvent.self, from: Data(dat.utf8))
}

func event_to_json(ev: NostrEvent) -> String {
    let encoder = JSONEncoder()
    guard let res = try? encoder.encode(ev) else {
        return "{}"
    }
    guard let str = String(data: res, encoding: .utf8) else {
        return "{}"
    }
    return str
}

func decrypt_dm(_ privkey: String?, pubkey: String, content: String) -> String? {
    guard let privkey = privkey else {
        return nil
    }
    guard let shared_sec = get_shared_secret(privkey: privkey, pubkey: pubkey) else {
        return nil
    }
    guard let dat = decode_dm_base64(content) else {
        return nil
    }
    guard let dat = aes_decrypt(data: dat.content, iv: dat.iv, shared_sec: shared_sec) else {
        return nil
    }
    return String(data: dat, encoding: .utf8)
}


func get_shared_secret(privkey: String, pubkey: String) -> [UInt8]? {
    guard let privkey_bytes = try? privkey.bytes else {
        return nil
    }
    guard var pk_bytes = try? pubkey.bytes else {
        return nil
    }
    pk_bytes.insert(2, at: 0)
    
    var publicKey = secp256k1_pubkey()
    var shared_secret = [UInt8](repeating: 0, count: 32)

    var ok =
        secp256k1_ec_pubkey_parse(
            secp256k1.Context.raw,
            &publicKey,
            pk_bytes,
            pk_bytes.count) != 0

    if !ok {
        return nil
    }

    ok = secp256k1_ecdh(
        secp256k1.Context.raw,
        &shared_secret,
        &publicKey,
        privkey_bytes, {(output,x32,_,_) in
            memcpy(output,x32,32)
            return 1
        }, nil) != 0

    if !ok {
        return nil
    }

    return shared_secret
}

struct DirectMessageBase64 {
    let content: [UInt8]
    let iv: [UInt8]
}

func encode_dm_base64(content: [UInt8], iv: [UInt8]) -> String {
    let content_b64 = base64_encode(content)
    let iv_b64 = base64_encode(iv)
    return content_b64 + "?iv=" + iv_b64
}

func decode_dm_base64(_ all: String) -> DirectMessageBase64? {
    let splits = Array(all.split(separator: "?"))

    if splits.count != 2 {
        return nil
    }

    guard let content = base64_decode(String(splits[0])) else {
        return nil
    }

    var sec = String(splits[1])
    if !sec.hasPrefix("iv=") {
        return nil
    }

    sec = String(sec.dropFirst(3))
    guard let iv = base64_decode(sec) else {
        return nil
    }

    return DirectMessageBase64(content: content, iv: iv)
}

func base64_encode(_ content: [UInt8]) -> String {
    return Data(content).base64EncodedString()
}

func base64_decode(_ content: String) -> [UInt8]? {
    guard let dat = Data(base64Encoded: content) else {
        return nil
    }
    return dat.bytes
}

func aes_decrypt(data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
    return aes_operation(operation: CCOperation(kCCDecrypt), data: data, iv: iv, shared_sec: shared_sec)
}

func aes_encrypt(data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
    return aes_operation(operation: CCOperation(kCCEncrypt), data: data, iv: iv, shared_sec: shared_sec)
}

func aes_operation(operation: CCOperation, data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
    let data_len = data.count
    let bsize = kCCBlockSizeAES128
    let len = Int(data_len) + bsize
    var decrypted_data = [UInt8](repeating: 0, count: len)

    let key_length = size_t(kCCKeySizeAES256)
    if shared_sec.count != key_length {
        assert(false, "unexpected shared_sec len: \(shared_sec.count) != 32")
        return nil
    }

    let algorithm: CCAlgorithm = UInt32(kCCAlgorithmAES128)
    let options:   CCOptions   = UInt32(kCCOptionPKCS7Padding)

    var num_bytes_decrypted :size_t = 0

    let status = CCCrypt(operation,  /*op:*/
                         algorithm,  /*alg:*/
                         options,    /*options:*/
                         shared_sec, /*key:*/
                         key_length, /*keyLength:*/
                         iv,         /*iv:*/
                         data,       /*dataIn:*/
                         data_len, /*dataInLength:*/
                         &decrypted_data,/*dataOut:*/
                         len,/*dataOutAvailable:*/
                         &num_bytes_decrypted/*dataOutMoved:*/
    )

    if UInt32(status) != UInt32(kCCSuccess) {
        return nil
    }

    return Data(bytes: decrypted_data, count: num_bytes_decrypted)

}

