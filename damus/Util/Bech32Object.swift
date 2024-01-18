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
        let len = s.end - s.start
        let bytes = Data(bytes: s.start, count: len)
        self.init(bytes: bytes, encoding: .utf8)
    }
}

struct NEvent : Equatable, Hashable {
    let noteid: NoteId
    let relays: [String]
    let author: Pubkey?
    let kind: UInt32?
    
    init(noteid: NoteId, relays: [String]) {
        self.noteid = noteid
        self.relays = relays
        self.author = nil
        self.kind = nil
    }
    
    init(noteid: NoteId, relays: [String], author: Pubkey?) {
        self.noteid = noteid
        self.relays = relays
        self.author = author
        self.kind = nil
    }
    init(noteid: NoteId, relays: [String], kind: UInt32?) {
        self.noteid = noteid
        self.relays = relays
        self.author = nil
        self.kind = kind
    }
    init(noteid: NoteId, relays: [String], author: Pubkey?, kind: UInt32?) {
        self.noteid = noteid
        self.relays = relays
        self.author = author
        self.kind = kind
    }
}

struct NProfile : Equatable, Hashable {
    let author: Pubkey
    let relays: [String]
}

struct NAddr : Equatable, Hashable {
    let identifier: String
    let author: Pubkey
    let relays: [String]
    let kind: UInt32
}

enum Bech32Object : Equatable {
    case nsec(Privkey)
    case npub(Pubkey)
    case note(NoteId)
    case nscript([UInt8])
    case nevent(NEvent)
    case nprofile(NProfile)
    case nrelay(String)
    case naddr(NAddr)
    
    static func parse(_ str: String) -> Bech32Object? {
        var b: nostr_bech32_t = nostr_bech32()
        
        let bytes = Array(str.utf8)
        
        bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            
            var cursorInstance = cursor()
            cursorInstance.start = UnsafeMutablePointer(mutating: baseAddress)
            cursorInstance.p = UnsafeMutablePointer(mutating: baseAddress)
            cursorInstance.end = cursorInstance.start.advanced(by: buffer.count)
            
            parse_nostr_bech32(&cursorInstance, &b)
        }
        
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
        switch self {
        case .nsec(let privkey):
            guard let pubkey = privkey_to_pubkey(privkey: privkey) else { return nil }
            return .pubkey(pubkey)
        case .npub(let pubkey):
            return .pubkey(pubkey)
        case .note(let noteid):
            return .note(noteid)
        case .nscript(_):
            return nil
        case .nevent(let nevent):
            return .nevent(nevent)
        case .nprofile(let nprofile):
            return .nprofile(nprofile)
        case .nrelay(let relayURL):
            return .nrelay(relayURL)
        case .naddr(let naddr):
            return .naddr(naddr)
        }
    }

}

func decodeCBech32(_ b: nostr_bech32_t) -> Bech32Object? {
    switch b.type {
    case NOSTR_BECH32_NOTE:
        let note = b.data.note;
        let note_id = NoteId(Data(bytes: note.event_id, count: 32))
        return .note(note_id)
    case NOSTR_BECH32_NEVENT:
        let nevent = b.data.nevent;
        let note_id = NoteId(Data(bytes: nevent.event_id, count: 32))
        let pubkey = nevent.pubkey != nil ? Pubkey(Data(bytes: nevent.pubkey, count: 32)) : nil
        let kind: UInt32? = nevent.has_kind ? nevent.kind : nil
        let relays = getRelayStrings(from: nevent.relays)
        return .nevent(NEvent(noteid: note_id, relays: relays, author: pubkey, kind: kind))
    case NOSTR_BECH32_NPUB:
        let npub = b.data.npub
        let pubkey = Pubkey(Data(bytes: npub.pubkey, count: 32))
        return .npub(pubkey)
    case NOSTR_BECH32_NSEC:
        let nsec = b.data.nsec
        let privkey = Privkey(Data(bytes: nsec.nsec, count: 32))
        guard let pubkey = privkey_to_pubkey(privkey: privkey) else { return nil }
        return .npub(pubkey)
    case NOSTR_BECH32_NPROFILE:
        let nprofile = b.data.nprofile
        let pubkey = Pubkey(Data(bytes: nprofile.pubkey, count: 32))
        return .nprofile(NProfile(author: pubkey, relays: getRelayStrings(from: nprofile.relays)))
    case NOSTR_BECH32_NRELAY:
        let nrelay = b.data.nrelay
        let str_relay: str_block = nrelay.relay
        guard let relay_str = String(str_relay) else {
            return nil
        }
        return .nrelay(relay_str)
    case NOSTR_BECH32_NADDR:
        let naddr = b.data.naddr
        guard let identifier = String(naddr.identifier) else {
            return nil
        }
        let pubkey = Pubkey(Data(bytes: naddr.pubkey, count: 32))
        let kind = naddr.kind
        
        return .naddr(NAddr(identifier: identifier, author: pubkey, relays: getRelayStrings(from: naddr.relays), kind: kind))
    default:
        return nil
    }
}

private func getRelayStrings(from relays: relays) -> [String] {
    var result = [String]()
    let numRelays = Int(relays.num_relays)

    func processRelay(_ relay: str_block) {
        if let string = String(relay) {
            result.append(string)
        }
    }

    // Since relays is a C tuple, the indexes can't be iterated through so they need to be manually processed
    if numRelays > 0 { processRelay(relays.relays.0) }
    if numRelays > 1 { processRelay(relays.relays.1) }
    if numRelays > 2 { processRelay(relays.relays.2) }
    if numRelays > 3 { processRelay(relays.relays.3) }
    if numRelays > 4 { processRelay(relays.relays.4) }
    if numRelays > 5 { processRelay(relays.relays.5) }
    if numRelays > 6 { processRelay(relays.relays.6) }
    if numRelays > 7 { processRelay(relays.relays.7) }
    if numRelays > 8 { processRelay(relays.relays.8) }
    if numRelays > 9 { processRelay(relays.relays.9) }

    return result
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

private func writeBytesRelays(bytesList: inout [UInt8], relays: [String]) {
    for relay in relays where !relay.isEmpty {
        guard let relayData = relay.data(using: .utf8) else {
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
