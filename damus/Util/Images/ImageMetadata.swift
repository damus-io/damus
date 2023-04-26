//
//  ImageMetadata.swift
//  damus
//
//  Created by William Casarin on 2023-04-25.
//

import Foundation
import UIKit

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
    
    let width: Int
    let height: Int
    
    
}

struct ImageMetadata: Equatable {
    let url: URL
    let blurhash: String
    let dim: ImageMetaDim
    
    init(url: URL, blurhash: String, dim: ImageMetaDim) {
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

func image_metadata_to_tag(_ meta: ImageMetadata) -> [String] {
    return ["imeta", "url \(meta.url.absoluteString)", "blurhash \(meta.blurhash)", "dim \(meta.dim.to_string())"]
}

func decode_image_metadata(_ parts: [String]) -> ImageMetadata? {
    var url: URL? = nil
    var blurhash: String? = nil
    var dim: ImageMetaDim? = nil
    
    for part in parts {
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
    
    guard let blurhash, let dim, let url else {
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

func calculate_blurhash(img: UIImage) async -> String? {
    guard img.size.height > 0 else {
        return nil
    }
    
    let res = Task.init {
        let sw: Double = 100
        let sh: Double = (100.0/img.size.width) * img.size.height
        
        let smaller = img.resized(to: CGSize(width: sw, height: sh))
        
        guard let blurhash = smaller.blurHash(numberOfComponents: (5,5)) else {
            let meta: String? = nil
            return meta
        }

        return blurhash
    }
    
    return await res.value
}

func calculate_image_metadata(url: URL, img: UIImage, blurhash: String) -> ImageMetadata {
    let width = Int(round(img.size.width * img.scale))
    let height = Int(round(img.size.height * img.scale))
    let dim = ImageMetaDim(width: width, height: height)
    
    return ImageMetadata(url: url, blurhash: blurhash, dim: dim)
}
