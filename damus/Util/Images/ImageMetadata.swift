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
    let dim: ImageMetaDim?
    
    init(url: URL, blurhash: String? = nil, dim: ImageMetaDim? = nil) {
        self.url = url
        self.blurhash = blurhash
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
}

func process_blurhash(blurhash: String, size: CGSize?) async -> UIImage? {
    let res = Task.detached(priority: .low) {
        let size = get_blurhash_size(img_size: size ?? CGSize(width: 100.0, height: 100.0))
        guard let img = UIImage.init(blurHash: blurhash, size: size) else {
            let noimg: UIImage? = nil
            return noimg
        }
        return img
    }
    
    return await res.value
}

func image_metadata_to_tag(_ meta: ImageMetadata) -> [String] {
    var tags = ["imeta", "url \(meta.url.absoluteString)"]
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
    var dim: ImageMetaDim? = nil
    
    for part in parts {
        if part == "imeta" {
            continue
        }
        
        let ps = part.split(separator: " ")
        
        guard ps.count == 2 else {
            return nil
        }
        let pname = ps[0]
        let pval = ps[1]
        
        if pname == "blurhash" {
            blurhash = String(pval)
        } else if pname == "dim" {
            dim = parse_image_meta_dim(String(pval))
        } else if pname == "url" {
            url = URL(string: String(pval))
        }
    }
    
    guard let url else {
        return nil
    }

    return ImageMetadata(url: url, blurhash: blurhash, dim: dim)
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

func get_blurhash_size(img_size: CGSize) -> CGSize {
    return CGSize(width: 100.0, height: (100.0/img_size.width) * img_size.height)
}

func calculate_blurhash(img: UIImage) async -> String? {
    guard img.size.height > 0 else {
        return nil
    }
    
    let res = Task.detached(priority: .low) {
        let bhs = get_blurhash_size(img_size: img.size)
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
        guard cache.lookup_img_metadata(url: meta.url) == nil else {
            continue
        }
        
        // We don't need blurhash if we already have the source image cached
        if ImageCache.default.isCached(forKey: meta.url.absoluteString) {
            continue
        }
        
        let state = ImageMetadataState(state: meta.blurhash == nil ? .not_needed : .processing, meta: meta)
        cache.store_img_metadata(url: meta.url, meta: state)
        
        guard let blurhash = state.meta.blurhash else {
            return
        }
        
        Task {
            let img = await process_blurhash(blurhash: blurhash, size: state.meta.dim?.size)
            
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

