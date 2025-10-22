import XCTest
@testable import damus

final class ContactCardManagerTests: XCTestCase {

    func testInitialization() {
        // Given: The shared ContactCardManager instance
        let manager = ContactCardManager()

        // Then: It should have an empty favorites set
        XCTAssertTrue(manager.favorites.isEmpty)
    }

    func testIsFavorite_WhenEmpty_ReturnsFalse() {
        // Given: An empty favorites manager
        let sut = ContactCardManager()
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        
        // When: Checking if a pubkey is favorite
        let result = sut.isFavorite(pubkey)
        
        // Then: Should return false
        XCTAssertFalse(result)
    }
    
    func testIsFavorite_WhenPubkeyExists_ReturnsTrue() {
        // Given: A pubkey added to favorites
        let sut = ContactCardManager()
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        sut.toggleFavorite(pubkey, postbox: test_damus_state.nostrNetwork.postbox, keyPair: generate_new_keypair())
        
        // When: Checking if the pubkey is favorite
        let result = sut.isFavorite(pubkey)
        
        // Then: Should return true
        XCTAssertTrue(result)
    }
    
    func testIsFavorite_WhenPubkeyDoesNotExist_ReturnsFalse() {
        // Given: A different pubkey added to favorites
        let sut = ContactCardManager()
        let expected = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let differentPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        sut.toggleFavorite(expected, postbox: test_damus_state.nostrNetwork.postbox, keyPair: generate_new_keypair())
        
        // When: Checking if a different pubkey is favorite
        let result = sut.isFavorite(differentPubkey)
        
        // Then: Should return false
        XCTAssertFalse(result)
    }

    func testToggleFavorite_WhenNotFavorite_AddsToFavorites() {
        // Given: A pubkey not in favorites
        let sut = ContactCardManager()
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        XCTAssertFalse(sut.isFavorite(pubkey))
        
        // When: Toggling the pubkey
        sut.toggleFavorite(pubkey, postbox: test_damus_state.nostrNetwork.postbox, keyPair: generate_new_keypair())
        
        // Then: Should be added to favorites
        XCTAssertTrue(sut.isFavorite(pubkey))
        XCTAssertEqual(sut.favorites.count, 1)
    }
    
    func testToggleFavorite_WhenAlreadyFavorite_RemovesFromFavorites() {
        // Given: A pubkey already in favorites
        let sut = ContactCardManager()
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let keypair = generate_new_keypair()
        sut.toggleFavorite(pubkey, postbox: test_damus_state.nostrNetwork.postbox, keyPair: keypair)
        XCTAssertTrue(sut.isFavorite(pubkey))
        
        // When: Toggling the pubkey again
        sut.toggleFavorite(pubkey, postbox: test_damus_state.nostrNetwork.postbox, keyPair: keypair)
        
        // Then: Should be removed from favorites
        XCTAssertFalse(sut.isFavorite(pubkey))
        XCTAssertEqual(sut.favorites.count, 0)
    }

    func testloadEvent_WithContactCard_AddsToFavorites() {
        // Given: A contact card event for favorites
        let sut = ContactCardManager()
        let targetPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let userPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!

        let tags = [
            [ContactCardManager.TARGET_PUBLIC_KEY, targetPubkey.hex()],
            [ContactCardManager.CONTACT_SET, ContactCardManager.FAVORITE_TAG]
        ]

        let event = NostrEvent(
            content: "",
            keypair: Keypair(pubkey: userPubkey, privkey: nil),
            kind: NostrKind.contact_card.rawValue,
            tags: tags
        )!

        // When: Handling the contact card event
        sut.loadEvent(event, pubkey: userPubkey)

        // Then: Should add the target pubkey to favorites
        XCTAssertTrue(sut.isFavorite(targetPubkey))
    }

    func testloadEvent_WithContactCard_RemovesFromFavorites() {
        // Given: A contact card event without favorite tag (unfavorite)
        let sut = ContactCardManager()
        let targetPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let userPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!

        // First add to favorites
        sut.toggleFavorite(targetPubkey, postbox: test_damus_state.nostrNetwork.postbox, keyPair: generate_new_keypair())
        XCTAssertTrue(sut.isFavorite(targetPubkey))

        // Create unfavorite contact card (only target public key tag, no contact set tag)
        let tags = [
            [ContactCardManager.TARGET_PUBLIC_KEY, targetPubkey.hex()]
        ]

        let event = NostrEvent(
            content: "",
            keypair: Keypair(pubkey: userPubkey, privkey: nil),
            kind: NostrKind.contact_card.rawValue,
            tags: tags,
            createdAt: UInt32(Date().timeIntervalSince1970) + 1
        )!

        // When: Handling the unfavorite contact card event
        sut.loadEvent(event, pubkey: userPubkey)

        // Then: Should remove the target pubkey from favorites
        XCTAssertFalse(sut.isFavorite(targetPubkey))
    }

    func testloadEvent_WithMissingTargetPubkey_ReturnsEarly() {
        // Given: A contact card event without d tag (missing target pubkey)
        let sut = ContactCardManager()
        let userPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        let initialFavoritesCount = sut.favorites.count
        let tags = [
            [ContactCardManager.CONTACT_SET, ContactCardManager.FAVORITE_TAG]
        ]
        let event = NostrEvent(
            content: "",
            keypair: Keypair(pubkey: userPubkey, privkey: nil),
            kind: NostrKind.contact_card.rawValue,
            tags: tags
        )!

        // When: Handling the event with missing target pubkey
        sut.loadEvent(event, pubkey: userPubkey)

        // Then: Should return early without changing favorites
        XCTAssertEqual(sut.favorites.count, initialFavoritesCount)
    }

    func testloadEvent_WithInvalidTargetPubkey_ReturnsEarly() {
        // Given: A contact card event with invalid d tag (invalid pubkey hex)
        let sut = ContactCardManager()
        let userPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        let initialFavoritesCount = sut.favorites.count
        // Create contact card with invalid pubkey hex
        let tags = [
            [ContactCardManager.TARGET_PUBLIC_KEY, "invalid_hex"],
            [ContactCardManager.CONTACT_SET, ContactCardManager.FAVORITE_TAG]
        ]
        let event = NostrEvent(
            content: "",
            keypair: Keypair(pubkey: userPubkey, privkey: nil),
            kind: NostrKind.contact_card.rawValue,
            tags: tags
        )!

        // When: Handling the event with invalid target pubkey
        sut.loadEvent(event, pubkey: userPubkey)

        // Then: Should return early without changing favorites
        XCTAssertEqual(sut.favorites.count, initialFavoritesCount)
    }

    func testloadEvent_WithOlderEvent_ReturnsEarly() {
        // Given: An existing newer contact card event
        let sut = ContactCardManager()
        let targetPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let userPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        // Create newer favorite event first
        let newerTags = [
            [ContactCardManager.TARGET_PUBLIC_KEY, targetPubkey.hex()],
            [ContactCardManager.CONTACT_SET, ContactCardManager.FAVORITE_TAG]
        ]
        let newerEvent = NostrEvent(
            content: "",
            keypair: Keypair(pubkey: userPubkey, privkey: nil),
            kind: NostrKind.contact_card.rawValue,
            tags: newerTags,
            createdAt: 1000
        )!
        sut.loadEvent(newerEvent, pubkey: userPubkey)
        XCTAssertTrue(sut.isFavorite(targetPubkey))
        // Create older unfavorite event
        let olderTags = [
            [ContactCardManager.TARGET_PUBLIC_KEY, targetPubkey.hex()]
        ]
        let olderEvent = NostrEvent(
            content: "",
            keypair: Keypair(pubkey: userPubkey, privkey: nil),
            kind: NostrKind.contact_card.rawValue,
            tags: olderTags,
            createdAt: 500  // Older timestamp
        )!

        // When: Handling the older event
        sut.loadEvent(olderEvent, pubkey: userPubkey)

        // Then: Should ignore the older event and keep the favorite status
        XCTAssertTrue(sut.isFavorite(targetPubkey))
    }

    func testFilter_WithFavoritePubkey_ReturnsTrue() {
        // Given: A pubkey in favorites
        let sut = ContactCardManager()
        let favoritePubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let otherPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        sut.toggleFavorite(favoritePubkey, postbox: test_damus_state.nostrNetwork.postbox, keyPair: generate_new_keypair())
        // Create events from both pubkeys
        let favoriteEvent = NostrEvent(
            content: "Hello from favorite",
            keypair: Keypair(pubkey: favoritePubkey, privkey: nil),
            kind: NostrKind.text.rawValue,
            tags: []
        )!
        let otherEvent = NostrEvent(
            content: "Hello from other",
            keypair: Keypair(pubkey: otherPubkey, privkey: nil),
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        // When: Using the filter
        let filter = sut.filter

        // Then: Should return true for favorite, false for other
        XCTAssertTrue(filter(favoriteEvent))
        XCTAssertFalse(filter(otherEvent))
    }
}
