//
//  BlossomAuthTests.swift
//  damusTests
//
//  Created by Claude on 2025-01-15.
//

import Foundation
import XCTest
@testable import damus

final class BlossomAuthTests: XCTestCase {

    // MARK: - Upload Auth Tests

    func testCreateBlossomUploadAuthReturnsNonNil() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" // SHA256 of empty string

        let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex)

        XCTAssertNotNil(auth, "Should return non-nil auth string")
    }

    func testCreateBlossomUploadAuthIsBase64Encoded() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        guard let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex) else {
            XCTFail("Auth should not be nil")
            return
        }

        // Should be valid base64 that decodes to JSON
        guard let decoded = Data(base64Encoded: auth) else {
            XCTFail("Auth string should be valid base64")
            return
        }

        // Should decode to valid JSON
        guard let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
            XCTFail("Decoded base64 should be valid JSON")
            return
        }

        XCTAssertNotNil(json["id"], "Event should have an id")
        XCTAssertNotNil(json["sig"], "Event should have a signature")
    }

    func testCreateBlossomUploadAuthHasCorrectKind() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        guard let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex),
              let decoded = Data(base64Encoded: auth),
              let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let kind = json["kind"] as? Int else {
            XCTFail("Failed to decode auth event")
            return
        }

        XCTAssertEqual(kind, 24242, "Blossom auth events must be kind 24242")
    }

    func testCreateBlossomUploadAuthHasRequiredTags() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        guard let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex),
              let decoded = Data(base64Encoded: auth),
              let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let tags = json["tags"] as? [[String]] else {
            XCTFail("Failed to decode auth event tags")
            return
        }

        // Per BUD-01, must have: ["t", action], ["expiration", timestamp], ["x", sha256]
        let tagDict = Dictionary(grouping: tags, by: { $0.first ?? "" })

        // Check "t" tag (action)
        guard let tTag = tagDict["t"]?.first, tTag.count >= 2 else {
            XCTFail("Missing 't' (action) tag")
            return
        }
        XCTAssertEqual(tTag[1], "upload", "Action tag should be 'upload' for upload auth")

        // Check "x" tag (sha256 hash)
        guard let xTag = tagDict["x"]?.first, xTag.count >= 2 else {
            XCTFail("Missing 'x' (hash) tag")
            return
        }
        XCTAssertEqual(xTag[1], sha256Hex, "Hash tag should contain the provided SHA256 hex")

        // Check "expiration" tag
        guard let expTag = tagDict["expiration"]?.first, expTag.count >= 2 else {
            XCTFail("Missing 'expiration' tag")
            return
        }
        guard let expTimestamp = Int(expTag[1]) else {
            XCTFail("Expiration should be a valid integer timestamp")
            return
        }
        let now = Int(Date().timeIntervalSince1970)
        XCTAssertGreaterThan(expTimestamp, now, "Expiration should be in the future")
    }

    func testCreateBlossomUploadAuthDefaultExpiration() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        guard let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex),
              let decoded = Data(base64Encoded: auth),
              let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let tags = json["tags"] as? [[String]] else {
            XCTFail("Failed to decode auth event")
            return
        }

        let expTag = tags.first { $0.first == "expiration" }
        guard let expTimestamp = expTag.flatMap({ Int($0[1]) }) else {
            XCTFail("Missing expiration tag")
            return
        }

        let now = Int(Date().timeIntervalSince1970)
        // Default is 300 seconds (5 minutes), allow some tolerance
        let expectedExpiration = now + 300
        XCTAssertLessThanOrEqual(abs(expTimestamp - expectedExpiration), 5, "Default expiration should be ~5 minutes from now")
    }

    func testCreateBlossomUploadAuthCustomExpiration() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let customExpiration: TimeInterval = 600 // 10 minutes

        guard let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex, expirationSeconds: customExpiration),
              let decoded = Data(base64Encoded: auth),
              let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let tags = json["tags"] as? [[String]] else {
            XCTFail("Failed to decode auth event")
            return
        }

        let expTag = tags.first { $0.first == "expiration" }
        guard let expTimestamp = expTag.flatMap({ Int($0[1]) }) else {
            XCTFail("Missing expiration tag")
            return
        }

        let now = Int(Date().timeIntervalSince1970)
        let expectedExpiration = now + Int(customExpiration)
        XCTAssertLessThanOrEqual(abs(expTimestamp - expectedExpiration), 5, "Custom expiration should be ~10 minutes from now")
    }

    // MARK: - Delete Auth Tests

    func testCreateBlossomDeleteAuthHasDeleteAction() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        guard let auth = create_blossom_delete_auth(keypair: keypair, sha256Hex: sha256Hex),
              let decoded = Data(base64Encoded: auth),
              let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let tags = json["tags"] as? [[String]] else {
            XCTFail("Failed to decode auth event")
            return
        }

        let tTag = tags.first { $0.first == "t" }
        guard let action = tTag?[safe: 1] else {
            XCTFail("Missing 't' tag")
            return
        }

        XCTAssertEqual(action, "delete", "Delete auth should have 'delete' action")
    }

    // MARK: - Authorization Header Tests

    func testBlossomAuthorizationHeaderFormat() {
        let testAuth = "dGVzdA==" // base64 of "test"
        let header = blossom_authorization_header(testAuth)

        XCTAssertEqual(header, "Nostr dGVzdA==", "Header should be 'Nostr ' prefix + base64 auth")
    }

    func testBlossomAuthorizationHeaderWithRealAuth() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        guard let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex) else {
            XCTFail("Auth should not be nil")
            return
        }

        let header = blossom_authorization_header(auth)

        XCTAssertTrue(header.hasPrefix("Nostr "), "Header should start with 'Nostr '")
        XCTAssertEqual(header, "Nostr " + auth, "Header should be prefix + auth")
    }

    // MARK: - Event Signing Tests

    func testAuthEventIsSigned() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        guard let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex),
              let decoded = Data(base64Encoded: auth),
              let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
            XCTFail("Failed to decode auth event")
            return
        }

        guard let sig = json["sig"] as? String else {
            XCTFail("Event should have signature")
            return
        }

        // Signature should be 128 hex chars (64 bytes)
        XCTAssertEqual(sig.count, 128, "Signature should be 128 hex characters")
        XCTAssertTrue(sig.allSatisfy { $0.isHexDigit }, "Signature should be valid hex")
    }

    func testAuthEventHasCorrectPubkey() throws {
        let keypair = test_keypair_full.to_keypair()
        let sha256Hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

        guard let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex),
              let decoded = Data(base64Encoded: auth),
              let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let pubkey = json["pubkey"] as? String else {
            XCTFail("Failed to decode auth event pubkey")
            return
        }

        XCTAssertEqual(pubkey, keypair.pubkey.hex(), "Event pubkey should match keypair pubkey")
    }
}

// MARK: - Helper Extensions

private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
