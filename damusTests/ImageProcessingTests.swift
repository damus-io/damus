//
//  ImageProcessingTests.swift
//  damusTests
//
//  Tests for image processing, particularly iOS 18 HEIC handling.
//

import XCTest
import UniformTypeIdentifiers
@testable import damus

final class ImageProcessingTests: XCTestCase {

    // MARK: - HEIC Processing Tests (iOS 18 crash fix)

    /// Tests that HEIC images can be processed without crashing.
    ///
    /// This test verifies the iOS 18 workaround in `removeGPSDataFromImage` which uses
    /// `CGImageSourceCreateImageAtIndex` + `CGImageDestinationAddImage` instead of
    /// `CGImageDestinationAddImageFromSource` (which crashes on iOS 18 with HEIC).
    func testProcessHEICImageDoesNotCrash() throws {
        // Create a test HEIC image
        let heicURL = try createTestHEICImage()
        defer { try? FileManager.default.removeItem(at: heicURL) }

        // Process the image - this would crash on iOS 18 before the fix
        let resultURL = processImage(url: heicURL)

        // Verify processing succeeded
        XCTAssertNotNil(resultURL, "HEIC image processing should succeed")

        // Clean up result
        if let resultURL {
            try? FileManager.default.removeItem(at: resultURL)
        }
    }

    /// Tests that HEIC processing correctly removes GPS metadata.
    func testProcessHEICImageRemovesGPSData() throws {
        // Create a test HEIC image with GPS data
        let heicURL = try createTestHEICImage(withGPSData: true)
        defer { try? FileManager.default.removeItem(at: heicURL) }

        // Process the image
        let resultURL = processImage(url: heicURL)
        XCTAssertNotNil(resultURL, "HEIC image processing should succeed")

        guard let resultURL else { return }
        defer { try? FileManager.default.removeItem(at: resultURL) }

        // Verify GPS data was removed
        guard let source = CGImageSourceCreateWithURL(resultURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            XCTFail("Failed to read processed image properties")
            return
        }

        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String],
                     "GPS data should be removed from processed image")
    }

    /// Tests that HEIC processing preserves image dimensions.
    func testProcessHEICImagePreservesDimensions() throws {
        let testWidth = 100
        let testHeight = 100

        let heicURL = try createTestHEICImage(width: testWidth, height: testHeight)
        defer { try? FileManager.default.removeItem(at: heicURL) }

        let resultURL = processImage(url: heicURL)
        XCTAssertNotNil(resultURL, "HEIC image processing should succeed")

        guard let resultURL else { return }
        defer { try? FileManager.default.removeItem(at: resultURL) }

        // Verify dimensions are preserved
        guard let source = CGImageSourceCreateWithURL(resultURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else {
            XCTFail("Failed to read processed image dimensions")
            return
        }

        XCTAssertEqual(width, testWidth, "Image width should be preserved")
        XCTAssertEqual(height, testHeight, "Image height should be preserved")
    }

    /// Tests that multi-frame HEIC images are handled correctly.
    func testProcessMultiFrameHEICImage() throws {
        // Create a multi-frame HEIC (like burst photos or live photos)
        let heicURL = try createTestHEICImage(frameCount: 3)
        defer { try? FileManager.default.removeItem(at: heicURL) }

        let resultURL = processImage(url: heicURL)
        XCTAssertNotNil(resultURL, "Multi-frame HEIC processing should succeed")

        if let resultURL {
            try? FileManager.default.removeItem(at: resultURL)
        }
    }

    // MARK: - JPEG Processing Tests (baseline)

    /// Tests that JPEG images still process correctly after the HEIC fix.
    func testProcessJPEGImageStillWorks() throws {
        let jpegURL = try createTestJPEGImage()
        defer { try? FileManager.default.removeItem(at: jpegURL) }

        let resultURL = processImage(url: jpegURL)
        XCTAssertNotNil(resultURL, "JPEG image processing should succeed")

        if let resultURL {
            try? FileManager.default.removeItem(at: resultURL)
        }
    }

    /// Tests that PNG images still process correctly.
    func testProcessPNGImageStillWorks() throws {
        let pngURL = try createTestPNGImage()
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let resultURL = processImage(url: pngURL)
        XCTAssertNotNil(resultURL, "PNG image processing should succeed")

        if let resultURL {
            try? FileManager.default.removeItem(at: resultURL)
        }
    }

    // MARK: - Helpers

    /// Creates a test HEIC image file.
    private func createTestHEICImage(
        width: Int = 100,
        height: Int = 100,
        frameCount: Int = 1,
        withGPSData: Bool = false
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("heic")

        // Create a simple test image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.failedToCreateContext
        }

        // Draw a gradient for visual verification if needed
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            throw TestError.failedToCreateImage
        }

        // Create HEIC destination
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.heic.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw TestError.failedToCreateDestination
        }

        // Build properties
        var properties: [CFString: Any] = [:]
        if withGPSData {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 37.7749,
                kCGImagePropertyGPSLongitude: -122.4194,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitudeRef: "W"
            ] as [CFString: Any]
        }

        // Add frames
        for _ in 0..<frameCount {
            CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw TestError.failedToFinalizeImage
        }

        return url
    }

    /// Creates a test JPEG image file.
    private func createTestJPEGImage(width: Int = 100, height: Int = 100) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpeg")

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let cgImage = context.makeImage() else {
            throw TestError.failedToCreateImage
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw TestError.failedToCreateDestination
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw TestError.failedToFinalizeImage
        }

        return url
    }

    /// Creates a test PNG image file.
    private func createTestPNGImage(width: Int = 100, height: Int = 100) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let cgImage = context.makeImage() else {
            throw TestError.failedToCreateImage
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw TestError.failedToCreateDestination
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw TestError.failedToFinalizeImage
        }

        return url
    }

    enum TestError: Error {
        case failedToCreateContext
        case failedToCreateImage
        case failedToCreateDestination
        case failedToFinalizeImage
    }
}
