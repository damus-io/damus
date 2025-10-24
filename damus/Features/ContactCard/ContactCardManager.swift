import Foundation
import SwiftUI

/// Manages user's favorites using NIP-81 contact cards
class ContactCardManager: ContactCard {
    private(set) var favorites: Set<Pubkey> = []
    private var latestContactCardEvents: [Pubkey: NostrEvent] = [:]
    public static let FAVORITE_TAG = "favorite"
    public static let CONTACT_SET = "n"
    public static let TARGET_PUBLIC_KEY = "d"

    public init() {}

    func isFavorite(_ pubkey: Pubkey) -> Bool {
        favorites.contains(pubkey)
    }

    func toggleFavorite(_ pubkey: Pubkey, postbox: PostBox, keyPair: FullKeypair?) {
        if favorites.contains(pubkey) {
            favorites.remove(pubkey)
            handleFavorite(target: pubkey, favorite: false, postbox: postbox, keypair: keyPair)
        } else {
            favorites.insert(pubkey)
            handleFavorite(target: pubkey, favorite: true, postbox: postbox, keypair: keyPair)
        }
    }

    func loadEvent(_ ev: NostrEvent, pubkey: Pubkey) {
        guard let kind = ev.known_kind, kind == .contact_card else {
            return
        }
        // we only care about our contact cards
        guard ev.pubkey == pubkey else {
            return
        }

        var targetPubkey: Pubkey?
        var isFavorite = false
        for tag in ev.tags {
            guard tag.count >= 2 else { continue }
            let tagType = tag[0].string()
            let tagValue = tag[1].string()
            if tagType == Self.TARGET_PUBLIC_KEY {
                targetPubkey = Pubkey(hex: tagValue)
            } else if tagType == Self.CONTACT_SET && tagValue == Self.FAVORITE_TAG {
                isFavorite = true
            }
        }

        guard let targetPubkey else {
            return
        }

        // Only process if this event is new
        if let existingEvent = latestContactCardEvents[targetPubkey] {
            guard ev.created_at > existingEvent.created_at else {
                return
            }
        }

        if isFavorite {
            favorites.insert(targetPubkey)
        } else {
            favorites.remove(targetPubkey)
        }

        latestContactCardEvents[targetPubkey] = ev
        notify(.favoriteUpdated())
    }

    var filter: (NostrEvent) -> Bool {
        { [weak self] ev in
            guard let self else { return false }
            return self.isFavorite(ev.pubkey)
        }
    }

    private func createFavoriteContactCard(keypair: FullKeypair, target: Pubkey) -> NostrEvent? {
        let kind = NostrKind.contact_card.rawValue
        let tags = [
            [Self.TARGET_PUBLIC_KEY, target.hex()],
            [Self.CONTACT_SET, Self.FAVORITE_TAG]
        ]
        return NostrEvent(content: "", keypair: keypair.to_keypair(), kind: kind, tags: tags)
    }

    private func createUnfavoriteContactCard(keypair: FullKeypair, target: Pubkey) -> NostrEvent? {
        let kind = NostrKind.contact_card.rawValue
        let tags = [
            [Self.TARGET_PUBLIC_KEY, target.hex()]
        ]
        return NostrEvent(content: "", keypair: keypair.to_keypair(), kind: kind, tags: tags)
    }

    private func handleFavorite(target: Pubkey, favorite: Bool, postbox: PostBox, keypair: FullKeypair?) {
        guard let keypair else {
            return
        }
        let ev: NostrEvent?
        if favorite {
            ev = createFavoriteContactCard(keypair: keypair, target: target)
        } else {
            ev = createUnfavoriteContactCard(keypair: keypair, target: target)
        }

        guard let ev else {
            return
        }

        if favorite {
            favorites.insert(target)
        } else {
            favorites.remove(target)
        }

        Task { await postbox.send(ev) }
        latestContactCardEvents[target] = ev
        notify(.favoriteUpdated())
    }
}

protocol ContactCard {
    func isFavorite(_ pubkey: Pubkey) -> Bool
    func toggleFavorite(_ pubkey: Pubkey, postbox: PostBox, keyPair: FullKeypair?)
    func loadEvent(_ ev: NostrEvent, pubkey: Pubkey)
    var filter: (NostrEvent) -> Bool { get }
    var favorites: Set<Pubkey> { get }
}
