import Foundation

class ContactCardManagerMock: ContactCard  {
    var event: NostrEvent?
    var favorites: Set<Pubkey> = []

    func isFavorite(_ pubkey: Pubkey) -> Bool {
       favorites.contains(pubkey)
    }

    func toggleFavorite(_ pubkey: Pubkey, postbox: PostBox, keyPair: FullKeypair?) {
        if favorites.contains(pubkey) {
            favorites.remove(pubkey)
        } else {
            favorites.insert(pubkey)
        }
    }

    func loadEvent(_ ev: NostrEvent, pubkey: Pubkey) {
        event = ev
    }

    var filter: ((_ ev: NostrEvent) -> Bool) {
        { ev in self.favorites.contains(ev.pubkey) }
    }
}
