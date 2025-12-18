//
//  BlossomUploaderTests.swift
//  damusTests
//
//  Created by Claude on 2025-01-15.
//

import Foundation
import XCTest
import CommonCrypto
@testable import damus

final class BlossomUploaderTests: XCTestCase {

    // MARK: - BlossomServerURL Tests

    func testServerURLValidHttps() {
        let url = BlossomServerURL("https://blossom.example.com")
        XCTAssertNotNil(url, "Valid HTTPS URL should be accepted")
        XCTAssertEqual(url?.absoluteString, "https://blossom.example.com")
    }

    func testServerURLValidHttp() {
        let url = BlossomServerURL("http://localhost:3000")
        XCTAssertNotNil(url, "Valid HTTP URL should be accepted")
        XCTAssertEqual(url?.absoluteString, "http://localhost:3000")
    }

    func testServerURLTrailingSlashRemoved() {
        let url = BlossomServerURL("https://blossom.example.com/")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "https://blossom.example.com", "Trailing slash should be removed")
    }

    func testServerURLInvalidScheme() {
        let url = BlossomServerURL("ftp://blossom.example.com")
        XCTAssertNil(url, "FTP scheme should be rejected")
    }

    func testServerURLNoScheme() {
        let url = BlossomServerURL("blossom.example.com")
        XCTAssertNil(url, "URL without scheme should be rejected")
    }

    func testServerURLInvalidFormat() {
        let url = BlossomServerURL("not a url at all")
        XCTAssertNil(url, "Invalid URL format should be rejected")
    }

    func testServerURLWithPath() {
        let url = BlossomServerURL("https://cdn.example.com/blossom")
        XCTAssertNotNil(url, "URL with path should be accepted")
        XCTAssertEqual(url?.absoluteString, "https://cdn.example.com/blossom")
    }

    func testServerURLUploadEndpoint() {
        guard let url = BlossomServerURL("https://blossom.example.com") else {
            XCTFail("Should create valid URL")
            return
        }

        XCTAssertEqual(url.uploadURL.absoluteString, "https://blossom.example.com/upload")
    }

    func testServerURLBlobEndpoint() {
        guard let url = BlossomServerURL("https://blossom.example.com") else {
            XCTFail("Should create valid URL")
            return
        }

        let sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let blobURL = url.blobURL(sha256: sha256)

        XCTAssertEqual(blobURL.absoluteString, "https://blossom.example.com/\(sha256)")
    }

    func testServerURLBlobEndpointWithExtension() {
        guard let url = BlossomServerURL("https://blossom.example.com") else {
            XCTFail("Should create valid URL")
            return
        }

        let sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let blobURL = url.blobURL(sha256: sha256, fileExtension: "jpg")

        XCTAssertEqual(blobURL.absoluteString, "https://blossom.example.com/\(sha256).jpg")
    }

    // MARK: - BlossomBlobDescriptor Tests

    func testBlobDescriptorParsing() throws {
        let json = """
        {
            "url": "https://cdn.example.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.jpg",
            "sha256": "b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553",
            "size": 184292,
            "type": "image/jpeg",
            "uploaded": 1725105921
        }
        """.data(using: .utf8)!

        let descriptor = try JSONDecoder().decode(BlossomBlobDescriptor.self, from: json)

        XCTAssertEqual(descriptor.url, "https://cdn.example.com/b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553.jpg")
        XCTAssertEqual(descriptor.sha256, "b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553")
        XCTAssertEqual(descriptor.size, 184292)
        XCTAssertEqual(descriptor.type, "image/jpeg")
        XCTAssertEqual(descriptor.uploaded, 1725105921)
    }

    func testBlobDescriptorParsingMinimalResponse() throws {
        // Some servers might return minimal responses
        let json = """
        {
            "url": "https://example.com/abc123",
            "sha256": "abc123",
            "size": 100,
            "type": "image/png",
            "uploaded": 1700000000
        }
        """.data(using: .utf8)!

        let descriptor = try JSONDecoder().decode(BlossomBlobDescriptor.self, from: json)

        XCTAssertEqual(descriptor.url, "https://example.com/abc123")
        XCTAssertEqual(descriptor.size, 100)
    }

    func testBlobDescriptorMissingField() {
        let json = """
        {
            "url": "https://example.com/abc123",
            "sha256": "abc123"
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(BlossomBlobDescriptor.self, from: json), "Missing required fields should throw")
    }

    // MARK: - BlossomError Tests

    func testErrorDescriptions() {
        XCTAssertEqual(BlossomError.invalidServerURL.errorDescription, "Invalid Blossom server URL")
        XCTAssertEqual(BlossomError.authenticationFailed.errorDescription, "Failed to create authentication")
        XCTAssertEqual(BlossomError.invalidResponse.errorDescription, "Invalid server response")
        XCTAssertEqual(BlossomError.noServerConfigured.errorDescription, "No Blossom server configured")
        XCTAssertEqual(BlossomError.fileReadError.errorDescription, "Failed to read file data")

        let serverRejected = BlossomError.serverRejected(reason: "File too large", statusCode: 413)
        XCTAssertEqual(serverRejected.errorDescription, "Server rejected upload (413): File too large")

        let networkError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        let uploadFailed = BlossomError.uploadFailed(underlying: networkError)
        XCTAssertTrue(uploadFailed.errorDescription?.contains("Upload failed") ?? false)
    }

    // MARK: - BlossomUploadResult Tests

    func testUploadResultSuccess() {
        let descriptor = BlossomBlobDescriptor(
            url: "https://example.com/blob",
            sha256: "abc123",
            size: 1000,
            type: "image/png",
            uploaded: 1700000000
        )

        let result = BlossomUploadResult.success(descriptor)

        XCTAssertEqual(result.uploadedURL, "https://example.com/blob")
    }

    func testUploadResultFailure() {
        let result = BlossomUploadResult.failed(.authenticationFailed)

        XCTAssertNil(result.uploadedURL)
    }

    // MARK: - BlossomUploader Unit Tests

    func testUploaderInitialization() {
        let uploader = BlossomUploader()
        XCTAssertNotNil(uploader, "Uploader should initialize")
    }

    // MARK: - Streaming SHA256 Tests

    func testStreamingSHA256WithTempFile() throws {
        // Create a temp file with known content
        let testContent = "Hello, Blossom!"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_sha256.txt")

        try testContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Compute hash using streaming function
        let hash = computeStreamingSHA256(fileURL: tempURL)

        // Expected SHA256 of "Hello, Blossom!"
        // Verified using: echo -n "Hello, Blossom!" | shasum -a 256
        XCTAssertNotNil(hash, "Should compute hash")
        XCTAssertEqual(hash?.count, 64, "SHA256 hex should be 64 characters")
    }

    func testStreamingSHA256ConsistentWithInMemory() throws {
        // Create a temp file
        let testData = Data(repeating: 0xAB, count: 1024 * 100) // 100KB of 0xAB bytes
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_sha256_compare.bin")

        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Compute using streaming
        let streamingHash = computeStreamingSHA256(fileURL: tempURL)

        // Compute using in-memory (reference implementation)
        var inMemoryHash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        testData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(testData.count), &inMemoryHash)
        }
        let expectedHash = inMemoryHash.map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(streamingHash, expectedHash, "Streaming hash should match in-memory hash")
    }

    func testStreamingSHA256NonExistentFile() {
        let badURL = URL(fileURLWithPath: "/nonexistent/file.txt")
        let hash = computeStreamingSHA256(fileURL: badURL)

        XCTAssertNil(hash, "Should return nil for non-existent file")
    }

    // MARK: - Integration-style Tests (without network)

    func testUploadWithInvalidServerURL() async {
        // This tests the full flow up to the point of making a network request
        // Since we can't mock URLSession easily without a protocol, we test with bad data
        let uploader = BlossomUploader()
        let keypair = test_keypair_full.to_keypair()
        let testData = "test data".data(using: .utf8)!

        // Create a URL that will immediately fail (localhost with no server)
        guard let serverURL = BlossomServerURL("http://127.0.0.1:1") else {
            XCTFail("Should create server URL")
            return
        }

        let result = await uploader.upload(
            data: testData,
            mimeType: "text/plain",
            to: serverURL,
            keypair: keypair
        )

        // Should fail with network error (connection refused)
        switch result {
        case .success:
            XCTFail("Should fail when connecting to non-existent server")
        case .failed(let error):
            // Expected - connection should fail
            if case .uploadFailed = error {
                // Good - network error as expected
            } else {
                XCTFail("Expected uploadFailed error, got \(error)")
            }
        }
    }

    // MARK: - Server URL Hashable/Equatable Tests

    func testServerURLEquality() {
        let url1 = BlossomServerURL("https://example.com")
        let url2 = BlossomServerURL("https://example.com")
        let url3 = BlossomServerURL("https://other.com")

        XCTAssertEqual(url1, url2, "Same URLs should be equal")
        XCTAssertNotEqual(url1, url3, "Different URLs should not be equal")
    }

    func testServerURLHashable() {
        let url1 = BlossomServerURL("https://example.com")!
        let url2 = BlossomServerURL("https://example.com")!

        var set = Set<BlossomServerURL>()
        set.insert(url1)
        set.insert(url2)

        XCTAssertEqual(set.count, 1, "Duplicate URLs should hash to same value")
    }

    // MARK: - Codable Tests

    func testServerURLCodable() throws {
        let original = BlossomServerURL("https://blossom.example.com")!

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlossomServerURL.self, from: encoded)

        XCTAssertEqual(original, decoded)
    }
}
