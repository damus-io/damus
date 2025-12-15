//
//  ImageMetadata.swift
//  damus
//
//  Created by William Casarin on 2023-04-25.
//

import Foundation
import UIKit
import Kingfisher

struct ImageMetaDim: Equatable, StringCodable {
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
    
    init?(from string: String) {
        guard let dim = parse_image_meta_dim(string) else {
            return nil
        }
        self = dim
    }
    
    func to_string() -> String {
        "\(width)x\(height)"
    }
    
    var size: CGSize {
        return CGSize(width: CGFloat(self.width), height: CGFloat(self.height))
    }
    
    let width: Int
    let height: Int
}

struct ImageMetadata: Equatable {
    let url: URL
    let blurhash: String?
    let thumbhash: String?  // ThumbHash: better detail, aspect ratio, alpha support
    let dim: ImageMetaDim?

    init(url: URL, blurhash: String? = nil, thumbhash: String? = nil, dim: ImageMetaDim? = nil) {
        self.url = url
        self.blurhash = blurhash
        self.thumbhash = thumbhash
        self.dim = dim
    }

    init?(tag: [String]) {
        guard let meta = decode_image_metadata(tag) else {
            return nil
        }

        self = meta
    }

    func to_tag() -> [String] {
        return image_metadata_to_tag(self)
    }

    /// Returns true if we have any placeholder hash (thumbhash preferred over blurhash)
    var hasPlaceholder: Bool {
        thumbhash != nil || blurhash != nil
    }
}

func process_blurhash(blurhash: String, size: CGSize?) async -> UIImage? {
    let res = Task.detached(priority: .low) {
        let default_size = CGSize(width: 100.0, height: 100.0)
        let size = get_blurhash_size(img_size: size ?? default_size) ?? default_size
        guard let img = UIImage.init(blurHash: blurhash, size: size) else {
            let noimg: UIImage? = nil
            return noimg
        }
        return img
    }

    return await res.value
}

/// Decodes a base64-encoded ThumbHash string into a UIImage placeholder.
/// ThumbHash produces better quality placeholders than BlurHash with embedded aspect ratio.
func process_thumbhash(thumbhash: String, size: CGSize?) async -> UIImage? {
    let res = Task.detached(priority: .low) { () -> UIImage? in
        // ThumbHash is stored as base64-encoded data
        guard let hashData = Data(base64Encoded: thumbhash) else {
            return nil
        }
        // thumbHashToImage handles aspect ratio internally, returns ~32x32 image
        return thumbHashToImage(hash: hashData)
    }
    return await res.value
}

/// Processes a placeholder hash, preferring thumbhash over blurhash.
/// Returns a UIImage suitable for display while the full image loads.
func process_placeholder(meta: ImageMetadata) async -> UIImage? {
    // Prefer thumbhash: better quality, embedded aspect ratio, alpha support
    if let thumbhash = meta.thumbhash {
        return await process_thumbhash(thumbhash: thumbhash, size: meta.dim?.size)
    }
    // Fall back to blurhash for interoperability with other Nostr clients
    if let blurhash = meta.blurhash {
        return await process_blurhash(blurhash: blurhash, size: meta.dim?.size)
    }
    return nil
}

func image_metadata_to_tag(_ meta: ImageMetadata) -> [String] {
    var tags = ["imeta", "url \(meta.url.absoluteString)"]
    // Include thumbhash if available (preferred placeholder format)
    if let thumbhash = meta.thumbhash {
        tags.append("thumbhash \(thumbhash)")
    }
    // Also include blurhash for backwards compatibility with older clients
    if let blurhash = meta.blurhash {
        tags.append("blurhash \(blurhash)")
    }
    if let dim = meta.dim {
        tags.append("dim \(dim.to_string())")
    }
    return tags
}

func decode_image_metadata(_ parts: [String]) -> ImageMetadata? {
    var url: URL? = nil
    var blurhash: String? = nil
    var thumbhash: String? = nil
    var dim: ImageMetaDim? = nil

    for part in parts {
        // Skip the "imeta" tag identifier
        if part == "imeta" {
            continue
        }

        let ps = part.split(separator: " ")

        guard ps.count == 2 else {
            return nil
        }
        let pname = ps[0]
        let pval = ps[1]

        switch pname {
        case "thumbhash":
            thumbhash = String(pval)
        case "blurhash":
            blurhash = String(pval)
        case "dim":
            dim = parse_image_meta_dim(String(pval))
        case "url":
            url = URL(string: String(pval))
        default:
            // Ignore unknown fields for forward compatibility
            break
        }
    }

    guard let url else {
        return nil
    }

    return ImageMetadata(url: url, blurhash: blurhash, thumbhash: thumbhash, dim: dim)
}

func parse_image_meta_dim(_ pval: String) -> ImageMetaDim? {
    let parts = pval.split(separator: "x")
    guard parts.count == 2,
          let width = Int(parts[0]),
          let height = Int(parts[1]) else {
        return nil
    }
    
    return ImageMetaDim(width: width, height: height)
}

extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

func get_blurhash_size(img_size: CGSize) -> CGSize? {
    guard img_size.width > 0 && img_size.height > 0 else { return nil }
    return CGSize(width: 100.0, height: (100.0/img_size.width) * img_size.height)
}

func calculate_blurhash(img: UIImage) async -> String? {
    guard img.size.height > 0 else {
        return nil
    }
    
    let res = Task.detached(priority: .low) {
        let bhs = get_blurhash_size(img_size: img.size) ?? CGSize(width: 100.0, height: 100.0)
        let smaller = img.resized(to: bhs)
        
        guard let blurhash = smaller.blurHash(numberOfComponents: (5,5)) else {
            let meta: String? = nil
            return meta
        }

        return blurhash
    }
    
    return await res.value
}

func calculate_image_metadata(url: URL, img: UIImage, blurhash: String) -> ImageMetadata {
    let width = Int(img.size.width)
    let height = Int(img.size.height)
    let dim = ImageMetaDim(width: width, height: height)
    
    return ImageMetadata(url: url, blurhash: blurhash, dim: dim)
}


func event_image_metadata(ev: NostrEvent) -> [ImageMetadata] {
    return ev.tags.reduce(into: [ImageMetadata]()) { meta, tag in
        guard tag.count >= 2, tag[0].matches_str("imeta"),
              let data = ImageMetadata(tag: tag.strings()) else {
            return
        }
        
        meta.append(data)
    }
}

func process_image_metadatas(cache: EventCache, ev: NostrEvent) {
    for meta in event_image_metadata(ev: ev) {
        // Skip if already cached
        guard cache.lookup_img_metadata(url: meta.url) == nil else {
            continue
        }

        // Skip placeholder processing if the source image is already cached
        if ImageCache.default.isCached(forKey: meta.url.absoluteString) {
            continue
        }

        // Determine initial state based on whether we have any placeholder hash
        let needsProcessing = meta.hasPlaceholder
        let initialState: ImageMetadataProcessState = needsProcessing ? .processing : .not_needed
        let state = ImageMetadataState(state: initialState, meta: meta)
        cache.store_img_metadata(url: meta.url, meta: state)

        // Skip async processing if no placeholder hash is available
        guard needsProcessing else {
            continue
        }

        // Process placeholder asynchronously (thumbhash preferred, blurhash fallback)
        Task {
            let img = await process_placeholder(meta: state.meta)

            Task { @MainActor in
                if let img {
                    state.state = .processed(img)
                } else {
                    state.state = .failed
                }
            }
        }
    }
}
