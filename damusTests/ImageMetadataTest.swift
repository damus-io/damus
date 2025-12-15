//
//  LocationStrippingTest.swift
//  damusTests
//
//  Created by KernelKind on 2/8/24.
//

import XCTest
@testable import damus

final class ImageMetadataTest : XCTestCase {

    // MARK: - ThumbHash Tests

    /// Test that ThumbHash encode/decode roundtrip produces a valid image
    func testThumbHashEncodeDecodeRoundtrip() {
        // Create a simple test image (red square)
        let size = CGSize(width: 64, height: 64)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        guard let testImage = UIGraphicsGetImageFromCurrentImageContext() else {
            XCTFail("Failed to create test image")
            return
        }
        UIGraphicsEndImageContext()

        // Encode to thumbhash
        let hashData = imageToThumbHash(image: testImage)
        XCTAssertFalse(hashData.isEmpty, "ThumbHash should not be empty")
        XCTAssertLessThanOrEqual(hashData.count, 30, "ThumbHash should be compact (~25 bytes)")

        // Decode back to image
        let decodedImage = thumbHashToImage(hash: hashData)
        XCTAssertGreaterThan(decodedImage.size.width, 0, "Decoded image should have valid width")
        XCTAssertGreaterThan(decodedImage.size.height, 0, "Decoded image should have valid height")
    }

    /// Test that base64 encoding/decoding works for storage in imeta tags
    func testThumbHashBase64Roundtrip() {
        // Create test image
        let size = CGSize(width: 32, height: 32)
        UIGraphicsBeginImageContext(size)
        UIColor.blue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        guard let testImage = UIGraphicsGetImageFromCurrentImageContext() else {
            XCTFail("Failed to create test image")
            return
        }
        UIGraphicsEndImageContext()

        // Encode to thumbhash, then to base64 (as stored in Nostr events)
        let hashData = imageToThumbHash(image: testImage)
        let base64String = hashData.base64EncodedString()

        // Decode from base64 back to image
        guard let decodedData = Data(base64Encoded: base64String) else {
            XCTFail("Failed to decode base64 thumbhash")
            return
        }
        let decodedImage = thumbHashToImage(hash: decodedData)
        XCTAssertGreaterThan(decodedImage.size.width, 0)
    }

    /// Test ImageMetadata parsing with thumbhash in imeta tag
    func testImageMetadataWithThumbHash() {
        let thumbhashValue = "1QcSHQRnh493V4dIh4eXh1h4kJUI"
        let tag = [
            "imeta",
            "url https://example.com/image.jpg",
            "thumbhash \(thumbhashValue)",
            "dim 800x600"
        ]

        guard let meta = ImageMetadata(tag: tag) else {
            XCTFail("Failed to parse ImageMetadata with thumbhash")
            return
        }

        XCTAssertEqual(meta.url.absoluteString, "https://example.com/image.jpg")
        XCTAssertEqual(meta.thumbhash, thumbhashValue)
        XCTAssertEqual(meta.dim?.width, 800)
        XCTAssertEqual(meta.dim?.height, 600)
        XCTAssertNil(meta.blurhash, "blurhash should be nil when not provided")
    }

    /// Test ImageMetadata parsing with both thumbhash and blurhash (backwards compat)
    func testImageMetadataWithBothHashes() {
        let tag = [
            "imeta",
            "url https://example.com/image.jpg",
            "thumbhash 1QcSHQRnh493V4dIh4eXh1h4kJUI",
            "blurhash LEHV6nWB2yk8pyo0adR*.7kCMdnj",
            "dim 800x600"
        ]

        guard let meta = ImageMetadata(tag: tag) else {
            XCTFail("Failed to parse ImageMetadata")
            return
        }

        XCTAssertNotNil(meta.thumbhash, "thumbhash should be present")
        XCTAssertNotNil(meta.blurhash, "blurhash should be present")
        XCTAssertTrue(meta.hasPlaceholder, "hasPlaceholder should be true")
    }

    /// Test that image_metadata_to_tag includes thumbhash
    func testImageMetadataToTagWithThumbHash() {
        let meta = ImageMetadata(
            url: URL(string: "https://example.com/test.jpg")!,
            blurhash: nil,
            thumbhash: "1QcSHQRnh493V4dIh4eXh1h4kJUI",
            dim: ImageMetaDim(width: 100, height: 100)
        )

        let tag = meta.to_tag()

        XCTAssertTrue(tag.contains("thumbhash 1QcSHQRnh493V4dIh4eXh1h4kJUI"))
        XCTAssertEqual(tag[0], "imeta")
    }

    // MARK: - GPS Data Tests

    func testRemoveGPSData() {
        let bundle = Bundle(for: type(of: self))
        guard let imageURL = bundle.url(forResource: "img_with_location", withExtension: "jpeg"),
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first 
        else {
            XCTFail("Failed to load test image from bundle")
            return
        }

        let testOutputURL = documentsDirectory.appendingPathComponent("img_with_location.jpeg")
        do {
            if FileManager.default.fileExists(atPath: testOutputURL.path) {
                try FileManager.default.removeItem(at: testOutputURL)
            }
            try FileManager.default.copyItem(at: imageURL, to: testOutputURL)
        } catch {
            XCTFail("Setup failed: Unable to copy test image to documents directory - \(error)")
            return
        }

        let removalSuccess = removeGPSDataFromImageAndWrite(fromImageURL: testOutputURL)

        XCTAssertTrue(removalSuccess, "GPS data removal was not successful")

        guard let sourceAfterRemoval = CGImageSourceCreateWithURL(testOutputURL as CFURL, nil),
              let imagePropertiesAfterRemoval = CGImageSourceCopyPropertiesAtIndex(sourceAfterRemoval, 0, nil) as? [String: Any],
              imagePropertiesAfterRemoval[kCGImagePropertyGPSDictionary as String] == nil else {
            XCTFail("GPS data was not removed from the image")
            return
        }
    }
}
