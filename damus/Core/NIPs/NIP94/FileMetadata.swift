//
//  FileMetadata.swift
//  damus
//
//  NIP-94: File Metadata (kind 1063)
//

import Foundation

/// NIP-94 file metadata parsed from a kind 1063 event's tags.
struct FileMetadata: Equatable {
    let url: URL
    let mimeType: String?
    let sha256hex: String?
    let originalSHA256hex: String?
    let size: Int64?
    let dim: ImageMetaDim?
    let blurhash: String?
    let thumbURL: URL?
    let imageURL: URL?
    let summary: String?
    let alt: String?

    var isGIF: Bool {
        mimeType == "image/gif"
    }
}

// MARK: - Parsing from kind 1063 event tags

func decode_file_metadata(from ev: NostrEvent) -> FileMetadata? {
    guard ev.known_kind == .file_metadata else { return nil }

    var url: URL?
    var mimeType: String?
    var sha256hex: String?
    var originalSHA256hex: String?
    var size: Int64?
    var dim: ImageMetaDim?
    var blurhash: String?
    var thumbURL: URL?
    var imageURL: URL?
    var summary: String?
    var alt: String?

    for tag in ev.tags {
        guard tag.count >= 2 else { continue }
        let key = tag[0].string()
        let val = tag[1].string()

        switch key {
        case "url":
            url = URL(string: val)
        case "m":
            mimeType = val
        case "x":
            sha256hex = val
        case "ox":
            originalSHA256hex = val
        case "size":
            size = Int64(val)
        case "dim":
            dim = parse_image_meta_dim(val)
        case "blurhash":
            blurhash = val
        case "thumb":
            thumbURL = URL(string: val)
        case "image":
            imageURL = URL(string: val)
        case "summary":
            summary = val
        case "alt":
            alt = val
        default:
            break
        }
    }

    guard let url else { return nil }

    return FileMetadata(
        url: url,
        mimeType: mimeType,
        sha256hex: sha256hex,
        originalSHA256hex: originalSHA256hex,
        size: size,
        dim: dim,
        blurhash: blurhash,
        thumbURL: thumbURL,
        imageURL: imageURL,
        summary: summary,
        alt: alt
    )
}

// MARK: - Creating kind 1063 events

func file_metadata_tags(_ meta: FileMetadata) -> [[String]] {
    var tags = [[String]]()
    tags.append(["url", meta.url.absoluteString])
    if let m = meta.mimeType { tags.append(["m", m]) }
    if let x = meta.sha256hex { tags.append(["x", x]) }
    if let ox = meta.originalSHA256hex { tags.append(["ox", ox]) }
    if let size = meta.size { tags.append(["size", String(size)]) }
    if let dim = meta.dim { tags.append(["dim", dim.to_string()]) }
    if let bh = meta.blurhash { tags.append(["blurhash", bh]) }
    if let thumb = meta.thumbURL { tags.append(["thumb", thumb.absoluteString]) }
    if let img = meta.imageURL { tags.append(["image", img.absoluteString]) }
    if let s = meta.summary { tags.append(["summary", s]) }
    if let a = meta.alt { tags.append(["alt", a]) }
    return tags
}

func make_file_metadata_event(keypair: Keypair, metadata: FileMetadata, content: String = "") -> NostrEvent? {
    let tags = file_metadata_tags(metadata)
    return NostrEvent(content: content, keypair: keypair, kind: NostrKind.file_metadata.rawValue, tags: tags)
}

/// Build a FileMetadata from a Blossom upload result plus local media info.
func file_metadata_from_blossom(descriptor: BlossomBlobDescriptor, media: MediaUpload, dim: ImageMetaDim? = nil, blurhash: String? = nil) -> FileMetadata? {
    guard let url = URL(string: descriptor.url) else { return nil }

    return FileMetadata(
        url: url,
        mimeType: descriptor.type ?? media.mime_type,
        sha256hex: descriptor.sha256,
        originalSHA256hex: nil,
        size: descriptor.size,
        dim: dim,
        blurhash: blurhash,
        thumbURL: nil,
        imageURL: nil,
        summary: nil,
        alt: nil
    )
}
