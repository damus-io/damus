//
//  BlossomTests.swift
//  damusTests
//
//  Created by Claude on 2026-03-18.
//

import XCTest
@testable import damus

final class BlossomTests: XCTestCase {

    // MARK: - BlossomServerURL

    func testValidHTTPSURL() {
        let server = BlossomServerURL(string: "https://blossom.example.com")
        XCTAssertNotNil(server)
        XCTAssertEqual(server?.url.absoluteString, "https://blossom.example.com")
    }

    func testRejectsHTTPURL() {
        let server = BlossomServerURL(string: "http://blossom.example.com")
        XCTAssertNil(server, "HTTP URLs must be rejected")
    }

    func testRejectsEmptyString() {
        let server = BlossomServerURL(string: "")
        XCTAssertNil(server)
    }

    func testRejectsNonURL() {
        let server = BlossomServerURL(string: "not a url")
        XCTAssertNil(server)
    }

    func testRejectsFTPScheme() {
        let server = BlossomServerURL(string: "ftp://blossom.example.com")
        XCTAssertNil(server)
    }

    func testUploadURL() {
        let server = BlossomServerURL(string: "https://blossom.example.com")!
        XCTAssertEqual(server.uploadURL.absoluteString, "https://blossom.example.com/upload")
    }

    func testMediaURL() {
        let server = BlossomServerURL(string: "https://blossom.example.com")!
        XCTAssertEqual(server.mediaURL.absoluteString, "https://blossom.example.com/media")
    }

    func testMirrorURL() {
        let server = BlossomServerURL(string: "https://blossom.example.com")!
        XCTAssertEqual(server.mirrorURL.absoluteString, "https://blossom.example.com/mirror")
    }

    func testBlobURLWithExtension() {
        let server = BlossomServerURL(string: "https://blossom.example.com")!
        let hash = "abc123def456"
        let url = server.blobURL(sha256: hash, fileExtension: "gif")
        XCTAssertEqual(url.absoluteString, "https://blossom.example.com/\(hash).gif")
    }

    func testBlobURLWithoutExtension() {
        let server = BlossomServerURL(string: "https://blossom.example.com")!
        let hash = "abc123def456"
        let url = server.blobURL(sha256: hash)
        XCTAssertEqual(url.absoluteString, "https://blossom.example.com/\(hash)")
    }

    func testServerURLEquality() {
        let a = BlossomServerURL(string: "https://blossom.example.com")
        let b = BlossomServerURL(string: "https://blossom.example.com")
        XCTAssertEqual(a, b)
    }

    func testTrailingSlashURL() {
        let server = BlossomServerURL(string: "https://blossom.example.com/")
        XCTAssertNotNil(server)
    }

    // MARK: - BlossomBlobDescriptor

    func testBlobDescriptorDecoding() throws {
        let json = """
        {
            "url": "https://blossom.example.com/abc123.gif",
            "sha256": "abc123",
            "size": 1024,
            "type": "image/gif",
            "uploaded": 1700000000
        }
        """
        let data = json.data(using: .utf8)!
        let descriptor = try JSONDecoder().decode(BlossomBlobDescriptor.self, from: data)

        XCTAssertEqual(descriptor.url, "https://blossom.example.com/abc123.gif")
        XCTAssertEqual(descriptor.sha256, "abc123")
        XCTAssertEqual(descriptor.size, 1024)
        XCTAssertEqual(descriptor.type, "image/gif")
        XCTAssertEqual(descriptor.uploaded, 1700000000)
    }

    func testBlobDescriptorDecodingWithoutOptionals() throws {
        let json = """
        {
            "url": "https://blossom.example.com/abc123",
            "sha256": "abc123",
            "size": 512
        }
        """
        let data = json.data(using: .utf8)!
        let descriptor = try JSONDecoder().decode(BlossomBlobDescriptor.self, from: data)

        XCTAssertEqual(descriptor.sha256, "abc123")
        XCTAssertNil(descriptor.type)
        XCTAssertNil(descriptor.uploaded)
    }

    // MARK: - SHA256

    func testSHA256HexKnownValue() {
        // SHA-256 of empty string is well-known
        let empty = Data()
        let hash = sha256_hex(empty)
        XCTAssertEqual(hash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testSHA256HexConsistency() {
        let testData = "hello blossom".data(using: .utf8)!
        let hash1 = sha256_hex(testData)
        let hash2 = sha256_hex(testData)
        XCTAssertEqual(hash1, hash2, "Same input must produce same hash")
    }

    func testSHA256HexDifferentInputs() {
        let data1 = "hello".data(using: .utf8)!
        let data2 = "world".data(using: .utf8)!
        let hash1 = sha256_hex(data1)
        let hash2 = sha256_hex(data2)
        XCTAssertNotEqual(hash1, hash2, "Different inputs must produce different hashes")
    }

    func testSHA256HexMatchesExistingImpl() {
        // Verify streaming sha256_hex matches the existing sha256() + hex_encode()
        let testData = "test data for hash comparison".data(using: .utf8)!
        let streamingResult = sha256_hex(testData)
        let existingResult = hex_encode(sha256(testData))
        XCTAssertEqual(streamingResult, existingResult, "Streaming hash must match existing implementation")
    }

    func testSHA256HexLength() {
        let data = "any data".data(using: .utf8)!
        let hash = sha256_hex(data)
        XCTAssertEqual(hash.count, 64, "SHA-256 hex string must be 64 characters")
    }

    // MARK: - BlossomAuth

    func testBlossomAuthCreation() {
        let keypair = test_keypair
        let auth = create_blossom_auth(
            keypair: keypair,
            action: "upload",
            sha256hex: "abc123"
        )

        XCTAssertNotNil(auth, "Auth creation must succeed with valid keypair")
        XCTAssertTrue(auth!.hasPrefix("Nostr "), "Auth header must start with 'Nostr '")
    }

    func testBlossomAuthContainsRequiredTags() throws {
        let keypair = test_keypair
        guard let auth = create_blossom_auth(
            keypair: keypair,
            action: "upload",
            sha256hex: "abc123",
            fileSize: 1024,
            serverURL: BlossomServerURL(string: "https://blossom.example.com")
        ) else {
            XCTFail("Auth creation failed")
            return
        }

        // Decode the base64 payload to verify tags
        let base64Part = String(auth.dropFirst("Nostr ".count))
        guard let jsonBytes = base64_decode(base64Part) else {
            XCTFail("Failed to decode base64 auth")
            return
        }
        let jsonString = String(bytes: jsonBytes, encoding: .utf8)!
        let jsonData = jsonString.data(using: .utf8)!

        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let kind = json["kind"] as? Int,
              let tags = json["tags"] as? [[String]]
        else {
            XCTFail("Failed to parse auth event JSON")
            return
        }

        XCTAssertEqual(kind, 24242, "Auth event must be kind 24242")

        let tagNames = tags.map { $0[0] }
        XCTAssertTrue(tagNames.contains("t"), "Must contain action tag")
        XCTAssertTrue(tagNames.contains("expiration"), "Must contain expiration tag")
        XCTAssertTrue(tagNames.contains("x"), "Must contain hash tag for upload")
        XCTAssertTrue(tagNames.contains("size"), "Must contain size tag when provided")
        XCTAssertTrue(tagNames.contains("server"), "Must contain server tag when provided")

        // Verify action value
        let actionTag = tags.first { $0[0] == "t" }
        XCTAssertEqual(actionTag?[1], "upload")

        // Verify hash value
        let hashTag = tags.first { $0[0] == "x" }
        XCTAssertEqual(hashTag?[1], "abc123")
    }

    func testBlossomAuthWithoutOptionalFields() {
        let keypair = test_keypair
        let auth = create_blossom_auth(
            keypair: keypair,
            action: "delete"
        )

        XCTAssertNotNil(auth)

        // Decode and verify no optional tags
        let base64Part = String(auth!.dropFirst("Nostr ".count))
        guard let jsonBytes = base64_decode(base64Part),
              let jsonString = String(bytes: jsonBytes, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let tags = json["tags"] as? [[String]]
        else {
            XCTFail("Failed to parse auth event")
            return
        }

        let tagNames = tags.map { $0[0] }
        XCTAssertFalse(tagNames.contains("x"), "No hash tag without sha256hex")
        XCTAssertFalse(tagNames.contains("size"), "No size tag without fileSize")
        XCTAssertFalse(tagNames.contains("server"), "No server tag without serverURL")
    }

    // MARK: - NostrKind

    func testBlossomKindValues() {
        XCTAssertEqual(NostrKind.blossom_auth.rawValue, 24242)
        XCTAssertEqual(NostrKind.blossom_server_list.rawValue, 10063)
        XCTAssertEqual(NostrKind.file_metadata.rawValue, 1063)
    }
}
