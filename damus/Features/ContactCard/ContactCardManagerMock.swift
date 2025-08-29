import Foundation

class ContactCardManagerMock: ContactCard  {
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

    func loadEvent(_ ev: NostrEvent, pubkey: Pubkey) {
        event = ev
    }

    private func handle_favorite_action(state: DamusState, target: Pubkey, is_favorite: Bool) {
        if is_favorite {
            favorites.insert(target)
        } else {
            favorites.remove(target)
        }
    }

    func handleFavorite(state: DamusState, target: Pubkey) {
        handle_favorite_action(state: state, target: target, is_favorite: true)
    }

    func handleUnfavorite(state: DamusState, target: Pubkey) {
        handle_favorite_action(state: state, target: target, is_favorite: false)
    }

    var filter: ((_ ev: NostrEvent) -> Bool) {
        { ev in self.favorites.contains(ev.pubkey) }
    }
}
