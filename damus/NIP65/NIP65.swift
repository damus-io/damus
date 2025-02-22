//
//  NIP65.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-21.
//
//  Some text excerpts taken from the Nostr Protocol itself (which are public domain)

import OrderedCollections

struct NIP65: Sendable {}

extension NIP65 {
    struct RelayList {
        let relays: OrderedDictionary<RelayURL, RelayItem>

        init(event: NdbNote) throws(NIP65Error) {
            guard event.known_kind == .relay_list else { throw .notRelayList }
            var relays: [RelayItem] = []
            for tag in event.tags {
                guard let relay = try RelayItem.fromTag(tag: tag) else { continue }
                relays.append(relay)
            }
            self.relays = Self.relayOrderedDictionary(from: relays)
        }
        
        init?(event: NdbNote?) throws(NIP65Error) {
            guard let event else { return nil }
            try self.init(event: event)
        }
        
        init(relays: [RelayItem]) {
            self.relays = Self.relayOrderedDictionary(from: relays)
        }
        
        init(relays: [RelayURL]) {
            let relayItemList = relays.map({ RelayItem(url: $0, rwConfiguration: .readWrite) })
            self.relays = Self.relayOrderedDictionary(from: relayItemList)
        }
        
        private static func relayOrderedDictionary(from relayList: [RelayItem]) -> OrderedDictionary<RelayURL, RelayItem> {
            OrderedDictionary(uniqueKeysWithValues: relayList.map({ ($0.url, $0) }))
        }
    }
}

extension NIP65 {
    enum NIP65Error: Error {
        case notRelayList
        case invalidRelayURL
        case invalidRelayMarker
    }
}

extension NIP65.RelayList {
    struct RelayItem: ThrowingTagConvertible {
        typealias E = NIP65.NIP65Error
        
        let url: RelayURL
        let rwConfiguration: RWConfiguration

        var tag: [String] {
            var tag = ["r", url.absoluteString]
            if let rwMarker = rwConfiguration.tagItem { tag.append(rwMarker) }
            return tag
        }

        static func fromTag(tag: TagSequence) throws(E) -> NIP65.RelayList.RelayItem? {
            var i = tag.makeIterator()

            guard tag.count >= 2,
                  let t0 = i.next(),
                  let key = t0.single_char,
                  let rkey = RefId.RefKey(rawValue: key),
                  let t1 = i.next()
            else { return nil }
            
            let t2 = i.next()

            switch rkey {
            case .r: return try self.fromRawInfo(urlString: t1.string(), rwMarker: t2?.string())
            // Keep options explicit to make compiler prompt developer on whether to ignore or handle new future options
            case .e, .p, .q, .t, .d, .a: return nil
            }
        }

        static func fromRawInfo(urlString: String, rwMarker: String?) throws(NIP65.NIP65Error) -> NIP65.RelayList.RelayItem? {
            guard let relayUrl = RelayURL(urlString) else { throw .invalidRelayURL }
            guard let rwConfiguration = RWConfiguration.fromTagItem(rwMarker) else { throw .invalidRelayMarker }
            return NIP65.RelayList.RelayItem(url: relayUrl, rwConfiguration: rwConfiguration)
        }
    }
}

extension NIP65.RelayList.RelayItem {
    enum RWConfiguration: TagItemConvertible {
        case read
        case write
        case readWrite
        
        static let READ_MARKER: String = "read"
        static let WRITE_MARKER: String = "write"
        
        var tagItem: String? {
            switch self {
            case .read: Self.READ_MARKER
            case .write: Self.WRITE_MARKER
            case .readWrite: nil
            }
        }
        
        static func fromTagItem(_ item: String?) -> Self? {
            if item == READ_MARKER { return .read }
            if item == WRITE_MARKER { return .write }
            return .readWrite
        }
    }
}
