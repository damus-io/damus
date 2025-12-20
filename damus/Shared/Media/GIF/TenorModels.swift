//
//  TenorModels.swift
//  damus
//
//  Created by eric on 12/11/25.
//

import Foundation

struct TenorSearchResponse: Codable {
    let results: [TenorGIFResult]
    let next: String?
}

struct TenorGIFResult: Codable, Identifiable {
    let id: String
    let title: String
    let media_formats: TenorMediaFormats
    let content_description: String?

    var previewURL: URL? {
        URL(string: media_formats.tinygif.url)
    }

    var fullURL: URL? {
        URL(string: media_formats.gif.url)
    }

    var mediumURL: URL? {
        URL(string: media_formats.mediumgif.url)
    }
}

struct TenorMediaFormats: Codable {
    let gif: TenorMediaFormat
    let mediumgif: TenorMediaFormat
    let tinygif: TenorMediaFormat
}

struct TenorMediaFormat: Codable {
    let url: String
    let dims: [Int]
    let duration: Double?
    let size: Int?

    var width: Int? {
        dims.count >= 1 ? dims[0] : nil
    }

    var height: Int? {
        dims.count >= 2 ? dims[1] : nil
    }
}
