//
//  InterestList.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-06-23.
//
//  Some text excerpts taken from the Nostr Protocol itself (which are public domain)

import Foundation

/// Includes models and functions for working with NIP-51
struct NIP51: Sendable {}

extension NIP51 {
    /// An error thrown when decoding an item into a NIP-51 list
    enum NIP51DecodingError: Error {
        /// The Nostr event being converted is not a NIP-51 interest list
        case notInterestList
    }
}

extension NIP51 {
    /// Models a NIP-51 Interest List (kind:10015)
    struct InterestList: NostrEventConvertible, Sendable {
        typealias E = NIP51DecodingError
        
        enum InterestItem: Sendable, Hashable {
            case hashtag(String)
            case interestSet(String, String, String) // a-tag: kind, pubkey, identifier
            
            var tag: [String] {
                switch self {
                case .hashtag(let tag):
                    return ["t", tag]
                case .interestSet(let kind, let pubkey, let identifier):
                    var tag = ["a", "\(kind):\(pubkey):\(identifier)"]
                    return tag
                }
            }
            
            static func fromTag(tag: TagSequence) -> InterestItem? {
                var i = tag.makeIterator()
                
                guard let t0 = i.next(),
                      let t1 = i.next() else { return nil }
                
                let tagName = t0.string()
                
                if tagName == "t" {
                    return .hashtag(t1.string())
                } else if tagName == "a" {
                    let components = t1.string().split(separator: ":")
                    guard components.count > 2 else { return nil }
                    
                    let kind = String(components[0])
                    let pubkey = String(components[1])
                    let identifier = String(components[2])
                    
                    return .interestSet(kind, pubkey, identifier)
                }
                
                return nil
            }
        }
        
        let interests: [InterestItem]
        
        // MARK: - Initialization
        
        @NdbActor
        init(event: NdbNote) throws(E) {
            try self.init(event: UnownedNdbNote(event))
        }
        
        @NdbActor
        init(event: borrowing UnownedNdbNote) throws(E) {
            guard event.known_kind == .interest_list else {
                throw E.notInterestList
            }
            
            var interests: [InterestItem] = []
            
            for tag in event.tags {
                if let interest = InterestItem.fromTag(tag: tag) {
                    interests.append(interest)
                }
            }
            
            self.interests = interests
        }
        
        @NdbActor
        init?(event: NdbNote?) throws(E) {
            guard let event else { return nil }
            try self.init(event: event)
        }
        
        init(interests: [InterestItem]) {
            self.interests = interests
        }
        
        // MARK: - Conversion to a Nostr Event
        
        func toNostrEvent(keypair: FullKeypair, timestamp: UInt32? = nil) -> NostrEvent? {
            return NdbNote(
                content: "",
                keypair: keypair.to_keypair(),
                kind: NostrKind.interest_list.rawValue,
                tags: self.interests.map { $0.tag },
                createdAt: timestamp ?? UInt32(Date.now.timeIntervalSince1970)
            )
        }
    }
}
