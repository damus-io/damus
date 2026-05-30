//
//  CreateAccountTests.swift
//  damusTests
//

import XCTest
@testable import damus

final class CreateAccountTests: XCTestCase {

    // MARK: - containsPrivateKeyMaterial

    func test_nsec_key_detected() {
        // A valid bech32-encoded private key should be flagged.
        let keypair = generate_new_keypair()
        let nsec = bech32_privkey(keypair.privkey)
        XCTAssertTrue(containsPrivateKeyMaterial(nsec), "An nsec1 key must be detected as private key material")
    }

    func test_hex_private_key_detected() {
        // A raw 64-character hex string should be flagged.
        let keypair = generate_new_keypair()
        let hexKey = keypair.privkey.hex()
        XCTAssertTrue(containsPrivateKeyMaterial(hexKey), "A 64-char hex string must be detected as private key material")
    }

    func test_plain_name_not_detected() {
        // Ordinary names should never be flagged.
        XCTAssertFalse(containsPrivateKeyMaterial("Satoshi Nakamoto"))
        XCTAssertFalse(containsPrivateKeyMaterial("Alice"))
        XCTAssertFalse(containsPrivateKeyMaterial(""))
    }

    func test_npub_not_detected() {
        // Public keys (npub) should NOT be flagged — they are meant to be shared.
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let npub = bech32_pubkey(pubkey)
        XCTAssertFalse(containsPrivateKeyMaterial(npub), "An npub must not be flagged as private key material")
    }

    func test_short_hex_not_detected() {
        // Hex strings shorter than 64 characters should not be flagged.
        XCTAssertFalse(containsPrivateKeyMaterial("deadbeef"))
        XCTAssertFalse(containsPrivateKeyMaterial(String(repeating: "a", count: 63)))
    }
}
