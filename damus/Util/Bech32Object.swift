//
//  Bech32Object.swift
//  damus
//
//  Created by William Casarin on 2023-01-28.
//

import Foundation

fileprivate extension String {
    /// Failable initializer to build a Swift.String from a C-backed `str_block_t`.
    init?(_ s: str_block_t) {
        let bytes = Data(bytes: s.str, count: Int(s.len))
        self.init(bytes: bytes, encoding: .utf8)
    }
}

struct NEvent : Equatable, Hashable {
    let noteid: NoteId
    let relays: [RelayURL]
    let author: Pubkey?
    let kind: UInt32?
    
    init(noteid: NoteId, relays: [RelayURL], author: Pubkey? = nil, kind: UInt32? = nil) {
        self.noteid = noteid
        self.relays = relays
        self.author = author
        self.kind = kind
    }
}

struct NProfile : Equatable, Hashable {
    let author: Pubkey
    let relays: [RelayURL]
}

struct NAddr : Equatable, Hashable {
    let identifier: String
    let author: Pubkey
    let relays: [RelayURL]
    let kind: UInt32
}

extension ndb_relays {
    func as_urls() -> [RelayURL] {
        var urls = [RelayURL]()

        //
        // This is so incredibly dumb but it's just what the Swift <-> C bridge
        // does and I don't have a better way that doesn't involve complicated 
        // and slow stuff like reflection
        //
        let (r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r13,r14,r15,r16,r17,r18,r19,r20,r21,r22,r23) = self.relays

        for i in 0..<self.num_relays {
            switch i {
            case 0:  if let relay = RelayURL(r0.as_str())  { urls.append(relay) }
            case 1:  if let relay = RelayURL(r1.as_str())  { urls.append(relay) }
            case 2:  if let relay = RelayURL(r2.as_str())  { urls.append(relay) }
            case 3:  if let relay = RelayURL(r3.as_str())  { urls.append(relay) }
            case 4:  if let relay = RelayURL(r4.as_str())  { urls.append(relay) }
            case 5:  if let relay = RelayURL(r5.as_str())  { urls.append(relay) }
            case 6:  if let relay = RelayURL(r6.as_str())  { urls.append(relay) }
            case 7:  if let relay = RelayURL(r7.as_str())  { urls.append(relay) }
            case 8:  if let relay = RelayURL(r8.as_str())  { urls.append(relay) }
            case 9:  if let relay = RelayURL(r9.as_str())  { urls.append(relay) }
            case 10: if let relay = RelayURL(r10.as_str()) { urls.append(relay) }
            case 11: if let relay = RelayURL(r11.as_str()) { urls.append(relay) }
            case 12: if let relay = RelayURL(r12.as_str()) { urls.append(relay) }
            case 13: if let relay = RelayURL(r13.as_str()) { urls.append(relay) }
            case 14: if let relay = RelayURL(r14.as_str()) { urls.append(relay) }
            case 15: if let relay = RelayURL(r15.as_str()) { urls.append(relay) }
            case 16: if let relay = RelayURL(r16.as_str()) { urls.append(relay) }
            case 17: if let relay = RelayURL(r17.as_str()) { urls.append(relay) }
            case 18: if let relay = RelayURL(r18.as_str()) { urls.append(relay) }
            case 19: if let relay = RelayURL(r19.as_str()) { urls.append(relay) }
            case 20: if let relay = RelayURL(r20.as_str()) { urls.append(relay) }
            case 21: if let relay = RelayURL(r21.as_str()) { urls.append(relay) }
            case 22: if let relay = RelayURL(r22.as_str()) { urls.append(relay) }
            case 23: if let relay = RelayURL(r23.as_str()) { urls.append(relay) }
            default:
                break
            }
        }

        return urls
    }

}

enum Bech32Object : Equatable, Hashable {
    case nsec(Privkey)
    case npub(Pubkey)
    case note(NoteId)
    case nscript([UInt8])
    case nevent(NEvent)
    case nprofile(NProfile)
    case nrelay(String)
    case naddr(NAddr)

    func pubkey() -> Pubkey? {
        switch self {
        case .nprofile(let nprofile): return nprofile.author
        case .npub(let pubkey): return pubkey
        case .nevent(let ev): return ev.author
        case .naddr(let naddr): return naddr.author
        case .nscript: return nil
        case .nsec: return nil // TODO privkey_to_pubkey ?
        case .note: return nil
        case .nrelay: return nil
        }
    }

    init?(block: ndb_mention_bech32_block) {
        let b32 = block.bech32
        switch block.bech32_type {
        case .note:
            let data = b32.note.event_id.as_data(size: 32)
            self = .note(NoteId(data))
        case .npub:
            let data = b32.npub.pubkey.as_data(size: 32)
            self = .npub(Pubkey(data))
        case .nprofile:
            let pk = b32.nprofile.pubkey.as_data(size: 32)
            let relays = b32.nprofile.relays.as_urls()
            self = .nprofile(NProfile(author: Pubkey(pk), relays: relays))
        case .nevent:
            let nevent = b32.nevent
            let note_id = NoteId(nevent.event_id.as_data(size: 32))
            let relays = nevent.relays.as_urls()
            var author: Pubkey? = nil
            if nevent.pubkey != nil {
                author = Pubkey(nevent.pubkey.as_data(size: 32))
            }
            var kind: UInt32? = nil
            if nevent.has_kind {
                kind = nevent.kind
            }

            self = .nevent(NEvent(noteid: note_id, relays: relays, author: author, kind: kind))
        case .nrelay:
            self = .nrelay(b32.nrelay.relay.as_str())
        case .naddr:
            let identifier = b32.naddr.identifier.as_str()
            let author = Pubkey(b32.naddr.pubkey.as_data(size: 32))
            let relays = b32.naddr.relays.as_urls()
            self = .naddr(NAddr(identifier: identifier, author: author, relays: relays, kind: b32.naddr.kind))
        case .nsec:
            return nil
        case .none:
            return nil
        }
    }

    static func parse(_ str: String) -> Bech32Object? {
        if str.starts(with: "nscript"), let decoded = try? bech32_decode(str) {
            return .nscript(decoded.data.bytes)
        }

        var b: nostr_bech32_t = nostr_bech32()
        var bytes = Data(capacity: str.utf8.count)

        let ok = str.withCString { cstr in
            let ok = bytes.withUnsafeMutableBytes { buffer -> Int32 in
                guard let addr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return parse_nostr_bech32(addr, Int32(buffer.count), cstr, str.utf8.count, &b)
            }

            return ok != 0
        }

        guard ok else { return nil }

        return decodeCBech32(b)
    }
    
    static func encode(_ obj: Bech32Object) -> String {
        switch(obj) {
        case .note(let noteid):
            return bech32_encode(hrp: "note", noteid.bytes)
        case .nevent(let nevent): return bech32EncodeNevent(nevent)
        case .nprofile(let nprofile): return bech32EncodeNprofile(nprofile)
        case .nrelay(let relayURL): return bech32EncodeNrelay(relayURL: relayURL)
        case .naddr(let naddr): return bech32EncodeNaddr(naddr)
        case .npub(let pubkey):
            return bech32_encode(hrp: "npub", pubkey.bytes)
        case .nsec(let privkey):
            guard let pubkey = privkey_to_pubkey(privkey: privkey) else { return "" }
            return bech32_encode(hrp: "npub", pubkey.bytes)
        case .nscript(let data):
            return bech32_encode(hrp: "nscript", data)
        }
    }
    
    func toMentionRef() -> MentionRef? {
        MentionRef(nip19: self)
    }

}

func decodeCBech32(_ b: nostr_bech32_t) -> Bech32Object? {
    switch b.type {
    case NOSTR_BECH32_NOTE:
        let note_id = NoteId(Data(bytes: b.note.event_id, count: 32))
        return .note(note_id)
    case NOSTR_BECH32_NEVENT:
        let note_id = NoteId(Data(bytes: b.nevent.event_id, count: 32))
        let pubkey = b.nevent.pubkey != nil ? Pubkey(Data(bytes: b.nevent.pubkey, count: 32)) : nil
        let kind: UInt32? = !b.nevent.has_kind ? nil : b.nevent.kind
        let relays = b.nevent.relays.as_urls()
        return .nevent(NEvent(noteid: note_id, relays: relays, author: pubkey, kind: kind))
    case NOSTR_BECH32_NPUB:
        let pubkey = Pubkey(Data(bytes: b.npub.pubkey, count: 32))
        return .npub(pubkey)
    case NOSTR_BECH32_NSEC:
        let privkey = Privkey(Data(bytes: b.nsec.nsec, count: 32))
        guard let pubkey = privkey_to_pubkey(privkey: privkey) else { return nil }
        return .npub(pubkey)
    case NOSTR_BECH32_NPROFILE:
        let pubkey = Pubkey(Data(bytes: b.nprofile.pubkey, count: 32))
        return .nprofile(NProfile(author: pubkey, relays: b.nprofile.relays.as_urls()))
    case NOSTR_BECH32_NRELAY:
        return .nrelay(b.nrelay.relay.as_str())
    case NOSTR_BECH32_NADDR:
        let pubkey = Pubkey(Data(bytes: b.naddr.pubkey, count: 32))
        let kind = b.naddr.kind
        let identifier = b.naddr.identifier.as_str()

        return .naddr(NAddr(identifier: identifier, author: pubkey, relays: b.naddr.relays.as_urls(), kind: kind))
    default:
        return nil
    }
}

private enum TLVType: UInt8 {
    case SPECIAL
    case RELAY
    case AUTHOR
    case KIND
}

private func writeBytesList(bytesList: inout [UInt8], tlvType: TLVType, data: [UInt8]){
    bytesList.append(tlvType.rawValue)
    bytesList.append(UInt8(data.bytes.count))
    bytesList.append(contentsOf: data.bytes)
}

private func writeBytesRelays(bytesList: inout [UInt8], relays: [RelayURL]) {
    for relay in relays {
        guard let relayData = relay.url.absoluteString.data(using: .utf8) else {
            continue // skip relay if can't read data
        }
        writeBytesList(bytesList: &bytesList, tlvType: .RELAY, data: relayData.bytes)
    }
}

private func writeBytesKind(bytesList: inout [UInt8], kind: UInt32) {
    bytesList.append(TLVType.KIND.rawValue)
    bytesList.append(UInt8(4))

    var bigEndianBytes = kind.bigEndian
    let data = Data(bytes: &bigEndianBytes, count: MemoryLayout<UInt32>.size)

    bytesList.append(contentsOf: data)
}

private func bech32EncodeNevent(_ nevent: NEvent) -> String {
    var neventBytes = [UInt8]();
    writeBytesList(bytesList: &neventBytes, tlvType: .SPECIAL, data: nevent.noteid.bytes)
    
    writeBytesRelays(bytesList: &neventBytes, relays: nevent.relays)
    
    if let eventPubkey = nevent.author {
        writeBytesList(bytesList: &neventBytes, tlvType: .AUTHOR, data: eventPubkey.bytes)
    }
    
    if let kind = nevent.kind {
        writeBytesKind(bytesList: &neventBytes, kind: kind)
    }
    
    return bech32_encode(hrp: "nevent", neventBytes.bytes)
}

private func bech32EncodeNprofile(_ nprofile: NProfile) -> String {
    var nprofileBytes = [UInt8]();

    writeBytesList(bytesList: &nprofileBytes, tlvType: .SPECIAL, data: nprofile.author.bytes)
    writeBytesRelays(bytesList: &nprofileBytes, relays: nprofile.relays)
    
    return bech32_encode(hrp: "nprofile", nprofileBytes.bytes)
}

private func bech32EncodeNrelay(relayURL: String) -> String {
    var nrelayBytes = [UInt8]();
    
    guard let relayURLBytes = relayURL.data(using: .ascii) else {
        return ""
    }
    
    writeBytesList(bytesList: &nrelayBytes, tlvType: .SPECIAL, data: relayURLBytes.bytes)
    return bech32_encode(hrp: "nrelay", nrelayBytes.bytes)
}

private func bech32EncodeNaddr(_ naddr: NAddr) -> String {
    var naddrBytes = [UInt8]();
    
    guard let identifierBytes = naddr.identifier.data(using: .utf8) else {
        return ""
    }
    
    writeBytesList(bytesList: &naddrBytes, tlvType: .SPECIAL, data: identifierBytes.bytes)
    writeBytesRelays(bytesList: &naddrBytes, relays: naddr.relays)
    writeBytesList(bytesList: &naddrBytes, tlvType: .AUTHOR, data: naddr.author.bytes)
    writeBytesKind(bytesList: &naddrBytes, kind: naddr.kind)
    return bech32_encode(hrp: "naddr", naddrBytes.bytes)
}
