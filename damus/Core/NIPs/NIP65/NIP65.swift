//
//  NIP65.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-21.
//
//  Some text excerpts taken from the Nostr Protocol itself (which are public domain)

import OrderedCollections
import Foundation

/// Includes models and functions for working with NIP-65
struct NIP65: Sendable {}

extension NIP65 {
    /// Models a NIP-65 relay list
    struct RelayList: NostrEventConvertible, Sendable {
        let relays: OrderedDictionary<RelayURL, RelayItem>

        // MARK: - Initialization

        init(event: NdbNote) throws(NIP65DecodingError) {
            try self.init(event: UnownedNdbNote(event))
        }
        
        init(event: borrowing UnownedNdbNote) throws(NIP65DecodingError) {
            guard event.known_kind == .relay_list else { throw .notRelayList }
            var relays: [RelayItem] = []
            for tag in event.tags {
                guard let relay = try RelayItem.fromTag(tag: tag) else { continue }
                relays.append(relay)
            }
            self.relays = Self.relayOrderedDictionary(from: relays)
        }
        
        init?(event: NdbNote?) throws(NIP65DecodingError) {
            guard let event else { return nil }
            try self.init(event: event)
        }
        
        init(relays: [RelayItem]) {
            self.relays = Self.relayOrderedDictionary(from: relays)
        }
        
        init() {
            self.relays = Self.relayOrderedDictionary(from: [])
        }
        
        init(relays: [RelayURL]) {
            let relayItemList = relays.map({ RelayItem(url: $0, rwConfiguration: .readWrite) })
            self.relays = Self.relayOrderedDictionary(from: relayItemList)
        }
        
        private static func relayOrderedDictionary(from relayList: [RelayItem]) -> OrderedDictionary<RelayURL, RelayItem> {
            var seenUrls: Set<RelayURL> = []
            return OrderedDictionary(uniqueKeysWithValues: relayList.compactMap({
                // We need to ensure the keys are unique to avoid assertion errors from OrderedDictionary
                guard !seenUrls.contains($0.url) else { return nil }
                seenUrls.insert($0.url)
                return ($0.url, $0)
            }))
        }
        
        
        // MARK: - Conversion to a Nostr Event
        
        func toNostrEvent(keypair: FullKeypair, timestamp: UInt32? = nil) -> NostrEvent? {
            return NdbNote(
                content: "",
                keypair: keypair.to_keypair(),
                kind: NostrKind.relay_list.rawValue,
                tags: self.relays.values.map({ $0.tag }),
                createdAt: timestamp ?? UInt32(Date.now.timeIntervalSince1970)
            )
        }
    }
}

extension NIP65 {
    /// An error thrown when decoding an item into a NIP-65 relay list
    enum NIP65DecodingError: Error {
        /// The Nostr event being converted is not a NIP-65 relay list
        case notRelayList
        /// The relay URL is invalid
        case invalidRelayURL
        ///The relay RW marker is invalid
        case invalidRelayMarker
    }
}

extension NIP65.RelayList {
    /// An item referencing a relay and its configuration inside a relay list
    struct RelayItem: ThrowingTagConvertible, Sendable {
        typealias E = NIP65.NIP65DecodingError
        
        let url: RelayURL
        let rwConfiguration: RWConfiguration

        /// The raw tag sequence in a Nostr event
        var tag: [String] {
            var tag = ["r", url.absoluteString]
            if let rwMarker = rwConfiguration.tagItem { tag.append(rwMarker) }
            return tag
        }

        /// Initialize a new relay item from a Nostr event's tag sequence
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

        /// Initializes a Relay Item based on raw information
        static func fromRawInfo(urlString: String, rwMarker: String?) throws(NIP65.NIP65DecodingError) -> NIP65.RelayList.RelayItem? {
            guard let relayUrl = RelayURL(urlString) else { throw .invalidRelayURL }
            guard let rwConfiguration = RWConfiguration.fromTagItem(rwMarker) else { throw .invalidRelayMarker }
            return NIP65.RelayList.RelayItem(url: relayUrl, rwConfiguration: rwConfiguration)
        }
    }
}

extension NIP65.RelayList.RelayItem {
    /// The read/write configuration for a relay item
    enum RWConfiguration: TagItemConvertible {
        case read
        case write
        case readWrite
        
        static let READ_MARKER: String = "read"
        static let WRITE_MARKER: String = "write"
        
        var canRead: Bool {
            switch self {
            case .read, .readWrite: return true
            case .write: return false
            }
        }
        
        var canWrite: Bool {
            switch self {
            case .write, .readWrite: return true
            case .read: return false
            }
        }
        
        /// A raw Nostr Event tag item
        var tagItem: String? {
            switch self {
            case .read: Self.READ_MARKER
            case .write: Self.WRITE_MARKER
            case .readWrite: nil
            }
        }
        
        /// Initialize this from a raw Nostr Event tag item
        static func fromTagItem(_ item: String?) -> Self? {
            if item == READ_MARKER { return .read }
            if item == WRITE_MARKER { return .write }
            return .readWrite
        }
    }
}
