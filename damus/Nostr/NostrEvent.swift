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
import NaturalLanguage


/// A protocol for structs and classes that can convert themselves from/to a NostrEvent
protocol NostrEventConvertible {
    associatedtype E: Error
    
    /// Iniitialize this type from a NostrEvent
    init(event: NostrEvent) throws(E)
    
    /// Convert this type into a Nostr Event, using a keypair for signing and a specific timestamp
    func toNostrEvent(keypair: FullKeypair, timestamp: UInt32?) -> NostrEvent?
}


enum ValidationResult: Decodable {
    case unknown
    case ok
    case bad_id
    case bad_sig
}

    /*
class NostrEventOld: Codable, Identifiable, CustomStringConvertible, Equatable, Hashable, Comparable {
    // TODO: memory mapped db events
    private var note_data: UnsafeMutablePointer<ndb_note>

    init(data: UnsafeMutablePointer<ndb_note>) {
        self.note_data = data
    }

    var id: [UInt8] {
        let buffer = UnsafeBufferPointer(start: ndb_note_id(note_data), count: 32)
        return Array(buffer)
    }

    var content: String {
        String(cString: ndb_note_content(self.note_data))
    }

    var sig: [UInt8] {
        let buffer = UnsafeBufferPointer(start: ndb_note_signature(note_data), count: 64)
        return Array(buffer)
    }

    var tags: TagIterator

    let id: String
    let content: String
    let sig: String
    let tags: Tags

    //var boosted_by: String?

    // cached field for pow calc
    //var pow: Int?

    // custom flags for internal use
    //var flags: Int = 0

    let pubkey: String
    let created_at: UInt32
    let kind: UInt32

    // cached stuff
    private var _event_refs: [EventRef]? = nil
    var decrypted_content: String? = nil
    private var _blocks: Blocks? = nil
    private lazy var inner_event: NostrEventOld? = {
        return event_from_json(dat: self.content)
    }()

    static func == (lhs: NostrEventOld, rhs: NostrEventOld) -> Bool {
        return lhs.id == rhs.id
    }

    static func < (lhs: NostrEventOld, rhs: NostrEventOld) -> Bool {
        return lhs.created_at < rhs.created_at
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private enum CodingKeys: String, CodingKey {
        case id, sig, tags, pubkey, created_at, kind, content
    }

    static func owned_from_json(json: String) -> NostrEventOld? {
        let decoder = JSONDecoder()
        guard let dat = json.data(using: .utf8) else {
            return nil
        }
        guard let ev = try? decoder.decode(NostrEventOld.self, from: dat) else {
            return nil
        }

        return ev
    }

    init?(content: String, keypair: Keypair, kind: UInt32 = 1, tags: [[String]] = [], createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) {

        self.content = content
        self.pubkey = keypair.pubkey
        self.kind = kind
        self.tags = tags
        self.created_at = createdAt

        if let privkey = keypair.privkey {
            self.id = hex_encode(calculate_event_id(pubkey: pubkey, created_at: created_at, kind: kind, tags: tags, content: content))
            self.sig = sign_id(privkey: privkey, id: self.id)
        } else {
            self.id = ""
            self.sig = ""
        }
    }
}

extension NostrEventOld {
    var is_textlike: Bool {
        return kind == 1 || kind == 42 || kind == 30023
    }

    var too_big: Bool {
        return known_kind != .longform && self.content.utf8.count > 16000
    }

    var should_show_event: Bool {
        return !too_big
    }

    func blocks(_ privkey: String?) -> Blocks {
        if let bs = _blocks {
            return bs
        }
        let blocks = get_blocks(content: self.get_content(privkey))
        self._blocks = blocks
        return blocks
    }

    func get_blocks(content: String) -> Blocks {
        return parse_note_content(content: content, tags: self.tags)
    }


    func get_inner_event(cache: EventCache) -> NostrEventOld? {
        guard self.known_kind == .boost else {
            return nil
        }

        if self.content == "", let ref = self.referenced_ids.first {
            return cache.lookup(ref.ref_id.string())
        }

        return self.inner_event
    }

    func event_refs(_ privkey: String?) -> [EventRef] {
        if let rs = _event_refs {
            return rs
        }
        let refs = interpret_event_refs(blocks: self.blocks(privkey).blocks, tags: self.tags)
        self._event_refs = refs
        return refs
    }


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

        let dec = decrypt_dm(key, pubkey: pubkey, content: self.content, encoding: .base64)
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
        return "NostrEvent { id: \(id) pubkey \(pubkey) kind \(kind) tags \(tags) content '\(content)' }"
    }

    var known_kind: NostrKind? {
        return NostrKind.init(rawValue: kind)
    }

    private func get_referenced_ids(key: String) -> [ReferencedId] {
        return damus.get_referenced_ids(tags: self.tags, key: key)
    }

    public func direct_replies(_ privkey: String?) -> [ReferencedId] {
        return event_refs(privkey).reduce(into: []) { acc, evref in
            if let direct_reply = evref.is_direct_reply {
                acc.append(direct_reply)
            }
        }
    }

    public func thread_id(privkey: String?) -> String {
        for ref in event_refs(privkey) {
            if let thread_id = ref.is_thread_id {
                return thread_id.ref_id
            }
        }

        return self.id
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

    public func references(id: String, key: AsciiCharacter) -> Bool {
        for tag in tags {
            if tag.count >= 2 && tag[0].matches_char(key) {
                if tag[1] == id {
                    return true
                }
            }
        }

        return false
    }

    func is_reply(_ privkey: String?) -> Bool {
        return event_is_reply(self.event_refs(privkey))
    }

    func note_language(_ privkey: String?) -> String? {
        // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the note is in
        // and filter on only the text portions of the content as URLs and hashtags confuse the language recognizer.
        let originalBlocks = blocks(privkey).blocks
        let originalOnlyText = originalBlocks.compactMap { $0.is_text }.joined(separator: " ")

        // Only accept language recognition hypothesis if there's at least a 50% probability that it's accurate.
        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(originalOnlyText)

        guard let locale = languageRecognizer.languageHypotheses(withMaximum: 1).first(where: { $0.value >= 0.5 })?.key.rawValue else {
            return nil
        }

        // Remove the variant component and just take the language part as translation services typically only supports the variant-less language.
        // Moreover, speakers of one variant can generally understand other variants.
        return localeToLanguage(locale)
    }

    public var referenced_ids: [ReferencedId] {
        return get_referenced_ids(key: "e")
    }

    public var referenced_pubkeys: [ReferencedId] {
        return get_referenced_ids(key: "p")
    }

    public var referenced_hashtags: [ReferencedId] {
        return get_referenced_ids(key: "t")
    }

    var age: TimeInterval {
        let event_date = Date(timeIntervalSince1970: TimeInterval(created_at))
        return Date.now.timeIntervalSince(event_date)
    }
}
     */

func sign_id(privkey: String, id: String) -> String {
    let priv_key_bytes = try! privkey.bytes
    let key = try! secp256k1.Signing.PrivateKey(rawRepresentation: priv_key_bytes)

    // Extra params for custom signing

    var aux_rand = random_bytes(count: 64).bytes
    var digest = try! id.bytes

    // API allows for signing variable length messages
    let signature = try! key.schnorr.signature(message: &digest, auxiliaryRand: &aux_rand)

    return hex_encode(signature.rawRepresentation)
}

func decode_nostr_event(txt: String) -> NostrResponse? {
    return NostrResponse.owned_from_json(json: txt)
}

func encode_json<T: Encodable>(_ val: T) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return (try? encode_json_data(val)).map { String(decoding: $0, as: UTF8.self) }
}

func encode_json_data<T: Encodable>(_ val: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return try encoder.encode(val)
}

func decode_nostr_event_json(json: String) -> NostrEvent? {
    return NostrEvent.owned_from_json(json: json)
}

/*
func decode_nostr_event_json(json: String) -> NostrEvent? {
    guard let json_str = json.cString(using: .utf8) else {
        return nil
    }

    // Allocate a double pointer (pointer to pointer) for ndb_note
    var notePtr: UnsafeMutablePointer<ndb_note>? = nil

    // Create the buffer
    var buf = [Int8](repeating: 0, count: 2<<18)

    // Call the C function
    let result = withUnsafeMutablePointer(to: &notePtr) { (ptr) -> Int32 in
        return ndb_note_from_json(json_str, Int32(json_str.count), ptr, &buf, Int32(buf.count))
    }

    guard result == 0, let note = notePtr?.pointee else {
        return nil
    }

    return .init(data: note)
}
*/

func decode_json<T: Decodable>(_ val: String) -> T? {
    return try? JSONDecoder().decode(T.self, from: Data(val.utf8))
}

func decode_json_throwing<T: Decodable>(_ val: String) throws -> T {
    return try JSONDecoder().decode(T.self, from: Data(val.utf8))
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

func event_commitment(pubkey: Pubkey, created_at: UInt32, kind: UInt32, tags: [[String]], content: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let str_data = try! encoder.encode(content)
    let content = String(decoding: str_data, as: UTF8.self)
    
    let tags_encoder = JSONEncoder()
    tags_encoder.outputFormatting = .withoutEscapingSlashes
    let tags_data = try! tags_encoder.encode(tags)
    let tags = String(decoding: tags_data, as: UTF8.self)

    return "[0,\"\(pubkey.hex())\",\(created_at),\(kind),\(tags),\(content)]"
}

func calculate_event_commitment(pubkey: Pubkey, created_at: UInt32, kind: UInt32, tags: [[String]], content: String) -> Data {
    let target = event_commitment(pubkey: pubkey, created_at: created_at, kind: kind, tags: tags, content: content)
    return target.data(using: .utf8)!
}

func calculate_event_id(pubkey: Pubkey, created_at: UInt32, kind: UInt32, tags: [[String]], content: String) -> NoteId {
    let commitment = calculate_event_commitment(pubkey: pubkey, created_at: created_at, kind: kind, tags: tags, content: content)
    return NoteId(sha256(commitment))
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

func random_bytes(count: Int) -> Data {
    var bytes = [Int8](repeating: 0, count: count)
    guard
        SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
    else {
        fatalError("can't copy secure random data")
    }
    return Data(bytes: bytes, count: count)
}

func make_boost_event(keypair: FullKeypair, boosted: NostrEvent) -> NostrEvent? {
    var tags = Array(boosted.referenced_pubkeys).map({ pk in pk.tag })

    tags.append(["e", boosted.id.hex(), "", "root"])
    tags.append(["p", boosted.pubkey.hex()])

    let content = event_to_json(ev: boosted)
    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 6, tags: tags)
}

func make_like_event(keypair: FullKeypair, liked: NostrEvent, content: String = "🤙") -> NostrEvent? {
    var tags = liked.tags.reduce(into: [[String]]()) { ts, tag in
        guard tag.count >= 2,
              (tag[0].matches_char("e") || tag[0].matches_char("p")) else {
            return
        }
        ts.append(tag.strings())
    }

    tags.append(["e", liked.id.hex()])
    tags.append(["p", liked.pubkey.hex()])

    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 7, tags: tags)
}

func generate_private_keypair(our_privkey: Privkey, id: NoteId, created_at: UInt32) -> FullKeypair? {
    let to_hash = our_privkey.hex() + id.hex() + String(created_at)
    guard let dat = to_hash.data(using: .utf8) else {
        return nil
    }
    let privkey_bytes = sha256(dat)
    let privkey = Privkey(privkey_bytes)
    guard let pubkey = privkey_to_pubkey(privkey: privkey) else { return nil }

    return FullKeypair(pubkey: pubkey, privkey: privkey)
}

func uniq<T: Hashable>(_ xs: [T]) -> [T] {
    var s = Set<T>()
    var ys: [T] = []
    
    for x in xs {
        if s.contains(x) {
            continue
        }
        s.insert(x)
        ys.append(x)
    }
    
    return ys
}

func gather_quote_ids(our_pubkey: Pubkey, from: NostrEvent) -> [RefId] {
    var ids: [RefId] = [.quote(from.id.quote_id)]
    if from.pubkey != our_pubkey {
        ids.append(.pubkey(from.pubkey))
    }
    return ids
}


func gather_reply_ids(our_pubkey: Pubkey, from: NostrEvent) -> [RefId] {
    var ids: [RefId] = from.referenced_ids.first.map({ ref in [ .event(ref) ] }) ?? []

    let pks = from.referenced_pubkeys.reduce(into: [RefId]()) { rs, pk in
        if pk == our_pubkey {
            return
        }
        rs.append(.pubkey(pk))
    }

    ids.append(.event(from.id))
    ids.append(contentsOf: uniq(pks))

    if from.pubkey != our_pubkey {
        ids.append(.pubkey(from.pubkey))
    }

    return ids
}

func event_from_json(dat: String) -> NostrEvent? {
    return NostrEvent.owned_from_json(json: dat)
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

@available(*, deprecated, renamed: "NIP04.decryptContent", message: "Deprecated, please use NIP04.decryptContent instead")
func decrypt_dm(_ privkey: Privkey?, pubkey: Pubkey, content: String, encoding: EncEncoding) -> String? {
    guard let privkey = privkey else {
        return nil
    }
    guard let shared_sec = get_shared_secret(privkey: privkey, pubkey: pubkey) else {
        return nil
    }
    guard let dat = (encoding == .base64 ? decode_dm_base64(content) : decode_dm_bech32(content)) else {
        return nil
    }
    guard let dat = aes_decrypt(data: dat.content, iv: dat.iv, shared_sec: shared_sec) else {
        return nil
    }
    return String(data: dat, encoding: .utf8)
}

func decrypt_note(our_privkey: Privkey, their_pubkey: Pubkey, enc_note: String, encoding: EncEncoding) -> NostrEvent? {
    guard let dec = decrypt_dm(our_privkey, pubkey: their_pubkey, content: enc_note, encoding: encoding) else {
        return nil
    }
    
    return decode_nostr_event_json(json: dec)
}

func get_shared_secret(privkey: Privkey, pubkey: Pubkey) -> [UInt8]? {
    let privkey_bytes = privkey.bytes
    var pk_bytes = pubkey.bytes

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

enum EncEncoding {
    case base64
    case bech32
}

struct DirectMessageBase64 {
    let content: [UInt8]
    let iv: [UInt8]
}



func encode_dm_bech32(content: [UInt8], iv: [UInt8]) -> String {
    let content_bech32 = bech32_encode(hrp: "pzap", content)
    let iv_bech32 = bech32_encode(hrp: "iv", iv)
    return content_bech32 + "_" + iv_bech32
}

func decode_dm_bech32(_ all: String) -> DirectMessageBase64? {
    let parts = all.split(separator: "_")
    guard parts.count == 2 else {
        return nil
    }
    
    let content_bech32 = String(parts[0])
    let iv_bech32 = String(parts[1])
    
    guard let content_tup = try? bech32_decode(content_bech32) else {
        return nil
    }
    guard let iv_tup = try? bech32_decode(iv_bech32) else {
        return nil
    }
    guard content_tup.hrp == "pzap" else {
        return nil
    }
    guard iv_tup.hrp == "iv" else {
        return nil
    }
    
    return DirectMessageBase64(content: content_tup.data.bytes, iv: iv_tup.data.bytes)
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



func validate_event(ev: NostrEvent) -> ValidationResult {
    let id = calculate_event_id(pubkey: ev.pubkey, created_at: ev.created_at, kind: ev.kind, tags: ev.tags.strings(), content: ev.content)

    if id != ev.id {
        return .bad_id
    }

    let ctx = secp256k1.Context.raw
    var xonly_pubkey = secp256k1_xonly_pubkey.init()

    var ev_pubkey = ev.pubkey.id.bytes

    var ok = secp256k1_xonly_pubkey_parse(ctx, &xonly_pubkey, &ev_pubkey) != 0
    if !ok {
        return .bad_sig
    }

    var sig = ev.sig.data.bytes
    var idbytes = id.id.bytes

    ok = secp256k1_schnorrsig_verify(ctx, &sig, &idbytes, 32, &xonly_pubkey) > 0
    return ok ? .ok : .bad_sig
}

func first_eref_mention(ndb: Ndb, ev: NostrEvent, keypair: Keypair) -> Mention<NoteId>? {
    guard let blockGroup = try? NdbBlockGroup.from(event: ev, using: ndb, and: keypair) else {
        return nil
    }
    
    return try? blockGroup.forEachBlock({ index, block in
        // Step 1: Filter
        switch block {
        case .mention(let mention):
            switch mention.bech32_type {
            case .note:
                let data = mention.bech32.note.event_id.as_data(size: 32)
                return .loopReturn(.note(NoteId(data)))
            case .nevent:
                let data = mention.bech32.nevent.event_id.as_data(size: 32)
                return .loopReturn(.note(NoteId(data)))
            default:
                return .loopBreak
            }
        default:
            return .loopContinue
        }
    })
}

func separate_invoices(ndb: Ndb, ev: NostrEvent, keypair: Keypair) -> [Invoice]? {
    guard let blockGroup = try? NdbBlockGroup.from(event: ev, using: ndb, and: keypair) else {
        return nil
    }
    let invoiceBlocks: [Invoice] = (try? blockGroup.reduce(initialResult: [Invoice](), { index, invoices, block in
        switch block {
        case .invoice(let invoice):
            if let invoice = invoice.as_invoice() {
                return .loopReturn(invoices + [invoice])
            }
        default:
            break
        }
        return .loopContinue
    })) ?? []
    return invoiceBlocks.isEmpty ? nil : invoiceBlocks
}

/**
 Transforms a `NostrEvent` of known kind `NostrKind.like`to a human-readable emoji.
 If the known kind is not a `NostrKind.like`, it will return `nil`.
 If the event content is an empty string or `+`, it will map that to a heart ❤️ emoji.
 If the event content is a "-", it will map that to a dislike 👎 emoji.
 Otherwise, it will return the event content at face value without transforming it.
 */
func to_reaction_emoji(ev: NostrEvent) -> String? {
    guard ev.known_kind == NostrKind.like else {
        return nil
    }

    switch ev.content {
    case "", "+":
        return "❤️"
    case "-":
        return "👎"
    default:
        return ev.content
    }
}

extension NostrEvent {
    /// The mutelist for a given event
    ///
    /// If the event is not a mutelist it will return `nil`.
    var mute_list: Set<MuteItem>? {
        if (self.kind == NostrKind.list_deprecated.rawValue && self.referenced_params.contains(where: { p in p.param.matches_str("mute") })) || self.kind == NostrKind.mute_list.rawValue {
            return Set(self.referenced_mute_items)
        } else {
            return nil
        }
    }
}
