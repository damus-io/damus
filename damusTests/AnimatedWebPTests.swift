//
//  AnimatedWebPTests.swift
//  damusTests
//

import XCTest
import Kingfisher
@testable import damus

final class AnimatedWebPTests: XCTestCase {
    /// 2x2 lossless WebP with two frames (200ms and 300ms)
    let animated_webp = Data(base64Encoded: "UklGRoQAAABXRUJQVlA4WAoAAAACAAAAAQAAAQAAQU5JTQYAAAAAAAAAAABBTk1GKAAAAAAAAAAAAAEAAAEAAMgAAAJWUDhMDwAAAC8BQAAABxD9j/4HIqL/AQBBTk1GKAAAAAAAAAAAAAEAAAEAACwBAABWUDhMDwAAAC8BQAAABxDR//4HIqL/AQA=")!

    /// 2x2 lossless single frame WebP
    let static_webp = Data(base64Encoded: "UklGRhwAAABXRUJQVlA4TA8AAAAvAUAAAAcQ/Y/+ByKi/wEA")!

    func testIsWebPData() {
        XCTAssertTrue(is_webp_data(animated_webp))
        XCTAssertTrue(is_webp_data(static_webp))
        XCTAssertFalse(is_webp_data(Data("GIF89a".utf8)))
        XCTAssertFalse(is_webp_data(Data()))
        // Works on slices that don't start at index 0
        XCTAssertTrue(is_webp_data((Data([0]) + animated_webp).dropFirst()))
    }

    func testIsAnimatedImageIncludesWebP() {
        XCTAssertTrue(is_animated_image(url: URL(string: "https://image.nostr.build/abc.webp")!))
        XCTAssertTrue(is_animated_image(url: URL(string: "https://image.nostr.build/abc.WEBP")!))
        XCTAssertTrue(is_animated_image(url: URL(string: "https://example.com/abc.gif")!))
        XCTAssertFalse(is_animated_image(url: URL(string: "https://example.com/abc.png")!))
    }

    func testWebPFrameSourceReadsFrameDurations() throws {
        let source = try XCTUnwrap(WebPFrameSource(data: animated_webp))
        XCTAssertEqual(source.frameCount, 2)
        XCTAssertEqual(source.duration(at: 0), 0.2, accuracy: 0.001)
        XCTAssertEqual(source.duration(at: 1), 0.3, accuracy: 0.001)
        XCTAssertNotNil(source.frame(at: 1))
    }

    func testProcessorCreatesAnimatedImageFromAnimatedWebP() throws {
        let processor = CustomImageProcessor(maxSize: ImageContext.note.maxMebibyteSize(), downsampleSize: ImageContext.note.downsampleSize())
        let options = KingfisherParsedOptionsInfo(nil)

        let image = try XCTUnwrap(processor.process(item: .data(animated_webp), options: options))
        XCTAssertEqual(image.kf.imageFrameCount, 2)
    }

    func testProcessorKeepsStaticWebPStatic() throws {
        let processor = CustomImageProcessor(maxSize: ImageContext.note.maxMebibyteSize(), downsampleSize: ImageContext.note.downsampleSize())
        let options = KingfisherParsedOptionsInfo(nil)

        let image = try XCTUnwrap(processor.process(item: .data(static_webp), options: options))
        XCTAssertNil(image.kf.imageFrameCount)
    }

    func testProcessorRespectsDisabledAnimation() throws {
        let processor = CustomImageProcessor(maxSize: ImageContext.note.maxMebibyteSize(), downsampleSize: ImageContext.note.downsampleSize())
        let options = KingfisherParsedOptionsInfo([.onlyLoadFirstFrame])

        let image = try XCTUnwrap(processor.process(item: .data(animated_webp), options: options))
        XCTAssertNil(image.kf.imageFrameCount)
    }

    func testCacheSerializerRoundTripsAnimatedWebP() throws {
        let serializer = CustomCacheSerializer(maxSize: ImageContext.note.maxMebibyteSize(), downsampleSize: ImageContext.note.downsampleSize())
        let options = KingfisherParsedOptionsInfo(nil)
        let image = try XCTUnwrap(UIImage(data: animated_webp))

        // The original bytes must be stored, otherwise Kingfisher re-encodes the image as a static PNG
        let stored = try XCTUnwrap(serializer.data(with: image, original: animated_webp))
        XCTAssertEqual(stored, animated_webp)

        let restored = try XCTUnwrap(serializer.image(with: stored, options: options))
        XCTAssertEqual(restored.kf.imageFrameCount, 2)
    }
}
