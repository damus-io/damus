//
//  TenorGIF.swift
//  damus
//
//  Tenor API models for GIF search
//

import Foundation

/// Represents a GIF from Tenor API
struct TenorGIF: Identifiable, Codable {
    let id: String
    let title: String
    let media_formats: MediaFormats
    let created: Double?
    let content_description: String
    let itemurl: String
    let url: String
    let tags: [String]
    let hasaudio: Bool

    struct MediaFormats: Codable {
        let gif: MediaFormat?
        let tinygif: MediaFormat?
        let nanogif: MediaFormat?
        let mediumgif: MediaFormat?

        struct MediaFormat: Codable {
            let url: String
            let duration: Double?
            let preview: String?
            let dims: [Int]?
            let size: Int?
        }
    }

    /// Get the best quality GIF URL
    var fullURL: URL? {
        if let mediumgif = media_formats.mediumgif {
            return URL(string: mediumgif.url)
        }
        if let gif = media_formats.gif {
            return URL(string: gif.url)
        }
        return nil
    }

    /// Get the preview/thumbnail URL
    var previewURL: URL? {
        if let preview = media_formats.tinygif?.url {
            return URL(string: preview)
        }
        if let preview = media_formats.nanogif?.url {
            return URL(string: preview)
        }
        return fullURL
    }

    /// Get dimensions if available
    var dimensions: ImageMetaDim? {
        if let dims = media_formats.mediumgif?.dims ?? media_formats.gif?.dims,
           dims.count >= 2 {
            return ImageMetaDim(width: dims[0], height: dims[1])
        }
        return nil
    }

    /// Convert to FileMetadata
    func toFileMetadata() -> FileMetadata? {
        guard let url = fullURL else { return nil }

        let preview = previewURL
        let thumbnailResource = preview.map { FileMetadata.RemoteResource(url: $0, sha256: nil) }
        let summaryText = title.isEmpty ? nil : title
        let altText: String?
        if content_description.isEmpty {
            altText = summaryText
        } else {
            altText = content_description
        }
        return FileMetadata(
            url: url,
            mimeType: "image/gif",
            size: media_formats.mediumgif?.size ?? media_formats.gif?.size,
            dimensions: dimensions,
            thumbnail: thumbnailResource,
            image: nil,
            summary: summaryText,
            alt: altText,
            service: "tenor"
        )
    }
}

/// Tenor API response wrapper
struct TenorResponse: Codable {
    let results: [TenorGIF]
    let next: String?
}
