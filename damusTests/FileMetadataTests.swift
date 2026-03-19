//
//  FileMetadataTests.swift
//  damusTests
//
//  NIP-94 FileMetadata tests
//

import XCTest
@testable import damus

final class FileMetadataTests: XCTestCase {

    // MARK: - FileMetadata struct

    func testIsGIF() {
        let meta = FileMetadata(
            url: URL(string: "https://example.com/cat.gif")!,
            mimeType: "image/gif",
            sha256hex: nil, originalSHA256hex: nil, size: nil,
            dim: nil, blurhash: nil, thumbURL: nil, imageURL: nil,
            summary: nil, alt: nil
        )
        XCTAssertTrue(meta.isGIF)
    }

    func testIsNotGIF() {
        let meta = FileMetadata(
            url: URL(string: "https://example.com/photo.jpg")!,
            mimeType: "image/jpeg",
            sha256hex: nil, originalSHA256hex: nil, size: nil,
            dim: nil, blurhash: nil, thumbURL: nil, imageURL: nil,
            summary: nil, alt: nil
        )
        XCTAssertFalse(meta.isGIF)
    }

    func testNilMimeTypeIsNotGIF() {
        let meta = FileMetadata(
            url: URL(string: "https://example.com/cat.gif")!,
            mimeType: nil,
            sha256hex: nil, originalSHA256hex: nil, size: nil,
            dim: nil, blurhash: nil, thumbURL: nil, imageURL: nil,
            summary: nil, alt: nil
        )
        XCTAssertFalse(meta.isGIF)
    }

    // MARK: - Tag generation

    func testFileMetadataTagsMinimal() {
        let meta = FileMetadata(
            url: URL(string: "https://example.com/cat.gif")!,
            mimeType: nil, sha256hex: nil, originalSHA256hex: nil,
            size: nil, dim: nil, blurhash: nil, thumbURL: nil,
            imageURL: nil, summary: nil, alt: nil
        )
        let tags = file_metadata_tags(meta)
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0], ["url", "https://example.com/cat.gif"])
    }

    func testFileMetadataTagsFull() {
        let meta = FileMetadata(
            url: URL(string: "https://example.com/cat.gif")!,
            mimeType: "image/gif",
            sha256hex: "abc123",
            originalSHA256hex: "def456",
            size: 98765,
            dim: ImageMetaDim(width: 320, height: 240),
            blurhash: "LEHV6nWB2yk8",
            thumbURL: URL(string: "https://example.com/thumb.jpg"),
            imageURL: URL(string: "https://example.com/preview.jpg"),
            summary: "A funny cat",
            alt: "Cat dancing"
        )
        let tags = file_metadata_tags(meta)
        XCTAssertEqual(tags.count, 11)
        XCTAssertTrue(tags.contains(["url", "https://example.com/cat.gif"]))
        XCTAssertTrue(tags.contains(["m", "image/gif"]))
        XCTAssertTrue(tags.contains(["x", "abc123"]))
        XCTAssertTrue(tags.contains(["ox", "def456"]))
        XCTAssertTrue(tags.contains(["size", "98765"]))
        XCTAssertTrue(tags.contains(["dim", "320x240"]))
        XCTAssertTrue(tags.contains(["blurhash", "LEHV6nWB2yk8"]))
        XCTAssertTrue(tags.contains(["thumb", "https://example.com/thumb.jpg"]))
        XCTAssertTrue(tags.contains(["image", "https://example.com/preview.jpg"]))
        XCTAssertTrue(tags.contains(["summary", "A funny cat"]))
        XCTAssertTrue(tags.contains(["alt", "Cat dancing"]))
    }

    // MARK: - Event creation

    func testMakeFileMetadataEvent() {
        let meta = FileMetadata(
            url: URL(string: "https://example.com/cat.gif")!,
            mimeType: "image/gif",
            sha256hex: "abc123",
            originalSHA256hex: nil,
            size: 12345,
            dim: nil, blurhash: nil, thumbURL: nil, imageURL: nil,
            summary: nil, alt: "A dancing cat"
        )
        let ev = make_file_metadata_event(keypair: test_keypair, metadata: meta, content: "")
        XCTAssertNotNil(ev)
        XCTAssertEqual(ev?.kind, NostrKind.file_metadata.rawValue)
    }

    func testMakeFileMetadataEventHasCorrectTags() {
        let meta = FileMetadata(
            url: URL(string: "https://example.com/cat.gif")!,
            mimeType: "image/gif",
            sha256hex: "abc123",
            originalSHA256hex: nil,
            size: nil, dim: nil, blurhash: nil, thumbURL: nil,
            imageURL: nil, summary: nil, alt: nil
        )
        let ev = make_file_metadata_event(keypair: test_keypair, metadata: meta)
        XCTAssertNotNil(ev)
        guard let ev else { return }

        var foundURL = false
        var foundMime = false
        var foundHash = false
        for tag in ev.tags {
            let strs = tag.strings()
            if strs.count >= 2 {
                if strs[0] == "url" && strs[1] == "https://example.com/cat.gif" { foundURL = true }
                if strs[0] == "m" && strs[1] == "image/gif" { foundMime = true }
                if strs[0] == "x" && strs[1] == "abc123" { foundHash = true }
            }
        }
        XCTAssertTrue(foundURL, "Event must have url tag")
        XCTAssertTrue(foundMime, "Event must have m tag")
        XCTAssertTrue(foundHash, "Event must have x tag")
    }

    // MARK: - Parsing from event

    func testDecodeFileMetadataFromEvent() {
        let meta = FileMetadata(
            url: URL(string: "https://example.com/dance.gif")!,
            mimeType: "image/gif",
            sha256hex: "deadbeef",
            originalSHA256hex: nil,
            size: 54321,
            dim: ImageMetaDim(width: 400, height: 300),
            blurhash: "LKO2:N%2Tw=w]~RBVZRi};RPxuwH",
            thumbURL: nil, imageURL: nil,
            summary: "Dance moves",
            alt: nil
        )
        guard let ev = make_file_metadata_event(keypair: test_keypair, metadata: meta) else {
            XCTFail("Failed to create event")
            return
        }
        let decoded = decode_file_metadata(from: ev)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.url.absoluteString, "https://example.com/dance.gif")
        XCTAssertEqual(decoded?.mimeType, "image/gif")
        XCTAssertEqual(decoded?.sha256hex, "deadbeef")
        XCTAssertEqual(decoded?.size, 54321)
        XCTAssertEqual(decoded?.dim?.width, 400)
        XCTAssertEqual(decoded?.dim?.height, 300)
        XCTAssertEqual(decoded?.summary, "Dance moves")
        XCTAssertTrue(decoded?.isGIF == true)
    }

    // MARK: - Blossom integration

    func testFileMetadataFromBlossom() {
        let descriptor = BlossomBlobDescriptor(
            url: "https://blossom.example.com/abc123.gif",
            sha256: "abc123def456",
            size: 99999,
            type: "image/gif",
            uploaded: 1700000000
        )
        let media = MediaUpload.image(URL(fileURLWithPath: "/tmp/test.gif"))
        let meta = file_metadata_from_blossom(descriptor: descriptor, media: media)
        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.url.absoluteString, "https://blossom.example.com/abc123.gif")
        XCTAssertEqual(meta?.sha256hex, "abc123def456")
        XCTAssertEqual(meta?.size, 99999)
        XCTAssertEqual(meta?.mimeType, "image/gif")
        XCTAssertTrue(meta?.isGIF == true)
    }

    func testFileMetadataFromBlossomFallsMimeType() {
        let descriptor = BlossomBlobDescriptor(
            url: "https://blossom.example.com/abc123",
            sha256: "abc123",
            size: 5000,
            type: nil,
            uploaded: nil
        )
        let media = MediaUpload.image(URL(fileURLWithPath: "/tmp/test.png"))
        let meta = file_metadata_from_blossom(descriptor: descriptor, media: media)
        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.mimeType, "image/png")
    }

    func testFileMetadataFromBlossomInvalidURL() {
        let descriptor = BlossomBlobDescriptor(
            url: "",
            sha256: "abc",
            size: 0,
            type: nil,
            uploaded: nil
        )
        let media = MediaUpload.image(URL(fileURLWithPath: "/tmp/test.gif"))
        let meta = file_metadata_from_blossom(descriptor: descriptor, media: media)
        XCTAssertNil(meta)
    }

    // MARK: - Equatable

    func testFileMetadataEquatable() {
        let a = FileMetadata(
            url: URL(string: "https://example.com/a.gif")!,
            mimeType: "image/gif", sha256hex: "abc",
            originalSHA256hex: nil, size: 100,
            dim: nil, blurhash: nil, thumbURL: nil, imageURL: nil,
            summary: nil, alt: nil
        )
        let b = FileMetadata(
            url: URL(string: "https://example.com/a.gif")!,
            mimeType: "image/gif", sha256hex: "abc",
            originalSHA256hex: nil, size: 100,
            dim: nil, blurhash: nil, thumbURL: nil, imageURL: nil,
            summary: nil, alt: nil
        )
        XCTAssertEqual(a, b)
    }
}
