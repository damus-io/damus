import XCTest
@testable import damus

final class FavoritesManagerTests: XCTestCase {

    func testInitialization() {
        // Given: The shared FavoritesManager instance
        let manager = FavoritesManager.shared

        // Then: It should have an empty favorites set
        XCTAssertTrue(manager.favorites.isEmpty)
    }

    func testSingletonPattern() {
        // Given: Two references to the shared instance
        let instance1 = FavoritesManager.shared
        let instance2 = FavoritesManager.shared
        
        // Then: They should be the same instance
        XCTAssertTrue(instance1 === instance2)
    }

    func testIsFavorite_WhenEmpty_ReturnsFalse() {
        // Given: An empty favorites manager
        let sut = FavoritesManager.shared
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        
        // When: Checking if a pubkey is favorite
        let result = sut.isFavorite(pubkey)
        
        // Then: Should return false
        XCTAssertFalse(result)
    }
    
    func testIsFavorite_WhenPubkeyExists_ReturnsTrue() {
        // Given: A pubkey added to favorites
        let sut = FavoritesManager.shared
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        sut.toggleFavorite(pubkey)
        
        // When: Checking if the pubkey is favorite
        let result = sut.isFavorite(pubkey)
        
        // Then: Should return true
        XCTAssertTrue(result)
    }
    
    func testIsFavorite_WhenPubkeyDoesNotExist_ReturnsFalse() {
        // Given: A different pubkey added to favorites
        let sut = FavoritesManager.shared
        let expected = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let differentPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        sut.toggleFavorite(expected)
        
        // When: Checking if a different pubkey is favorite
        let result = sut.isFavorite(differentPubkey)
        
        // Then: Should return false
        XCTAssertFalse(result)
    }

    func testToggleFavorite_WhenNotFavorite_AddsToFavorites() {
        // Given: A pubkey not in favorites
        let sut = FavoritesManager.shared
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        XCTAssertFalse(sut.isFavorite(pubkey))
        
        // When: Toggling the pubkey
        sut.toggleFavorite(pubkey)
        
        // Then: Should be added to favorites
        XCTAssertTrue(sut.isFavorite(pubkey))
        XCTAssertEqual(sut.favorites.count, 1)
    }
    
    func testToggleFavorite_WhenAlreadyFavorite_RemovesFromFavorites() {
        // Given: A pubkey already in favorites
        let sut = FavoritesManager.shared
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        sut.toggleFavorite(pubkey)
        XCTAssertTrue(sut.isFavorite(pubkey))
        
        // When: Toggling the pubkey again
        sut.toggleFavorite(pubkey)
        
        // Then: Should be removed from favorites
        XCTAssertFalse(sut.isFavorite(pubkey))
        XCTAssertEqual(sut.favorites.count, 0)
    }

    override func setUp() {
        super.setUp()
        FavoritesManager.shared.resetForTesting()
    }
}
