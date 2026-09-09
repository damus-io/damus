import Foundation
import UIKit
import ImageIO

/// Preparing images runs off the main actor and creates only composition-owned files.
actor VoicePhotoFiles {
    static let shared = VoicePhotoFiles()

    struct Prepared: @unchecked Sendable {
        let preview: UIImage
        let dim: String
        let blurhash: String?
    }

    /// Re-encode as JPEG to avoid copying the source photo's location metadata.
    func prepare(_ data: Data, to file: URL) async throws -> Prepared {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 40_000_000,
              let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.9),
              jpeg.count <= 20 * 1024 * 1024 else {
            throw VoiceFailure("This photo could not be prepared. Choose an image under 20 MiB and 40 megapixels.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw VoiceFailure("The photo preview could not be created.")
        }
        let preview = UIImage(cgImage: thumbnail)
        let blurhash = await calculate_blurhash(img: preview)
        // The event describes the encoded pixels, including orientation normalization.
        guard let encoded = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let output = CGImageSourceCopyPropertiesAtIndex(encoded, 0, nil) as? [CFString: Any],
              let outputWidth = output[kCGImagePropertyPixelWidth] as? NSNumber,
              let outputHeight = output[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw VoiceFailure("The encoded photo dimensions could not be read.")
        }
        try Task.checkCancellation()
        try jpeg.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return Prepared(preview: preview, dim: "\(outputWidth.intValue)x\(outputHeight.intValue)", blurhash: blurhash)
    }
}
