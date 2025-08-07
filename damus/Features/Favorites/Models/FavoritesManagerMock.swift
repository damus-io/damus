import Foundation
import SwiftUI

class FavoritesManagerMock: Favorites  {
    var event: NostrEvent?
    var favorites: Set<Pubkey> = []

    func isFavorite(_ pubkey: Pubkey) -> Bool {
       favorites.contains(pubkey)
    }

    func toggleFavorite(_ pubkey: Pubkey) {
        if favorites.contains(pubkey) {
            favorites.remove(pubkey)
        } else {
            favorites.insert(pubkey)
        }
    }

    func handleEvent(_ ev: NostrEvent, pubkey: Pubkey) {
        var new_favorites: Set<Pubkey> = []
        for tag in ev.tags {
            guard tag.count >= 2 && tag[0].string() == "p" else { continue }
            if let pubkey = Pubkey(hex: tag[1].string()) {
                new_favorites.insert(pubkey)
            }
        }
        favorites = new_favorites
        event = ev
    }

    private func handle_favorite_action(state: DamusState, target: Pubkey, is_favorite: Bool) {
        if is_favorite {
            favorites.insert(target)
        } else {
            favorites.remove(target)
        }
    }

    func handle_favorite(state: DamusState, target: Pubkey) {
        handle_favorite_action(state: state, target: target, is_favorite: true)
    }

    func handle_unfavorite(state: DamusState, target: Pubkey) {
        handle_favorite_action(state: state, target: target, is_favorite: false)
    }

    var filter: ((_ ev: NostrEvent) -> Bool) {
        { ev in self.favorites.contains(ev.pubkey) }
    }
}
