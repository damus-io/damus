//
//  GIFModels.swift
//  damus
//

import Foundation

struct GIFSearchResponse: Decodable {
    let results: [GIFResult]
    let next: String?

    /// Decodes GIF payloads from both featured and search endpoints.
    ///
    /// Featured returns a Tenor-style payload with top-level `results` and `next`.
    /// Search returns a KLIPY payload with a nested `data.data` array plus paging metadata.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let results = try container.decodeIfPresent([GIFResult].self, forKey: .results) {
            self.results = results
            self.next = try container.decodeIfPresent(String.self, forKey: .next)
            return
        }

        if let searchPayload = try container.decodeIfPresent(KLIPYSearchPayload.self, forKey: .data) {
            self.results = searchPayload.data
            self.next = searchPayload.has_next ? String(searchPayload.current_page + 1) : nil
            return
        }

        throw DecodingError.keyNotFound(
            CodingKeys.results,
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "No supported GIF results payload was found. Expected either top-level results or nested data.data."
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case results
        case next
        case data
    }

    private struct KLIPYSearchPayload: Decodable {
        let data: [GIFResult]
        let current_page: Int
        let per_page: Int
        let has_next: Bool
    }
}

struct GIFResult: Decodable, Identifiable {
    let id: String
    let title: String?
    let media_formats: GIFMediaFormats?
    let content_description: String?
    let slug: String?

    /// Decodes either featured-style or KLIPY search-style GIF payloads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try GIFResult.decodeID(from: container)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.media_formats = try GIFResult.decodeMediaFormats(from: container)
        self.content_description = try container.decodeIfPresent(String.self, forKey: .content_description)
        self.slug = try container.decodeIfPresent(String.self, forKey: .slug)
    }

    var previewURL: URL? {
        guard let url = media_formats?.preview?.url else { return nil }
        return URL(string: url)
    }

    var fullURL: URL? {
        guard let url = media_formats?.primary?.url else { return nil }
        return URL(string: url)
    }

    var mediumURL: URL? {
        guard let url = media_formats?.medium?.url else { return nil }
        return URL(string: url)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case media_formats
        case content_description
        case slug
        case file
    }

    /// Decodes GIF IDs that may arrive as strings or numbers.
    private static func decodeID(from container: KeyedDecodingContainer<CodingKeys>) throws -> String {
        if let stringID = try? container.decode(String.self, forKey: .id) {
            return stringID
        }

        if let intID = try? container.decode(Int.self, forKey: .id) {
            return String(intID)
        }

        if let int64ID = try? container.decode(Int64.self, forKey: .id) {
            return String(int64ID)
        }

        if let uint64ID = try? container.decode(UInt64.self, forKey: .id) {
            return String(uint64ID)
        }

        if let doubleID = try? container.decode(Double.self, forKey: .id) {
            guard doubleID.isFinite, !doubleID.isNaN else {
                throw DecodingError.dataCorruptedError(
                    forKey: .id,
                    in: container,
                    debugDescription: "GIF id must be a finite number."
                )
            }

            guard doubleID.rounded() == doubleID else {
                throw DecodingError.dataCorruptedError(
                    forKey: .id,
                    in: container,
                    debugDescription: "GIF id numeric value must be integral."
                )
            }

            if let exactInt64 = Int64(exactly: doubleID) {
                return String(exactInt64)
            }

            if let exactUInt64 = UInt64(exactly: doubleID) {
                return String(exactUInt64)
            }

            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "GIF id numeric value is out of supported range."
            )
        }

        throw DecodingError.dataCorruptedError(
            forKey: .id,
            in: container,
            debugDescription: "No supported GIF id value was found."
        )
    }

    /// Decodes either shared media formats or KLIPY's nested file formats.
    private static func decodeMediaFormats(from container: KeyedDecodingContainer<CodingKeys>) throws -> GIFMediaFormats? {
        if let mediaFormats = try container.decodeIfPresent(GIFMediaFormats.self, forKey: .media_formats) {
            return mediaFormats
        }

        if let klipyFile = try container.decodeIfPresent(KLIPYFileFormats.self, forKey: .file) {
            return klipyFile.asMediaFormats
        }

        return nil
    }
}

struct GIFMediaFormats: Decodable {
    let gif: GIFMediaFormat?
    let webp: GIFMediaFormat?
    let jpg: GIFMediaFormat?
    let mp4: GIFMediaFormat?
    let webm: GIFMediaFormat?
    let tinygif: GIFMediaFormat?
    let tinymp4: GIFMediaFormat?
    let tinywebm: GIFMediaFormat?

    var preview: GIFMediaFormat? {
        tinygif ?? tinymp4 ?? tinywebm ?? gif ?? webp ?? jpg ?? mp4 ?? webm
    }

    var medium: GIFMediaFormat? {
        gif ?? webp ?? mp4 ?? webm ?? jpg
    }

    var primary: GIFMediaFormat? {
        gif ?? webp ?? mp4 ?? webm ?? jpg
    }
}

struct GIFMediaFormat: Decodable {
    let url: String
    let dims: [Int]?
    let duration: Double?
    let size: Int?

    /// Decodes either shared Damus media format fields or KLIPY width/height fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        self.size = try container.decodeIfPresent(Int.self, forKey: .size)

        if let dims = try container.decodeIfPresent([Int].self, forKey: .dims) {
            self.dims = dims
            return
        }

        let width = try GIFMediaFormat.decodeIntegerValue(forKey: .width, from: container)
        let height = try GIFMediaFormat.decodeIntegerValue(forKey: .height, from: container)
        if let width, let height {
            self.dims = [width, height]
            return
        }

        self.dims = nil
    }

    var width: Int? {
        dims?.count ?? 0 >= 1 ? dims?[0] : nil
    }

    var height: Int? {
        dims?.count ?? 0 >= 2 ? dims?[1] : nil
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case dims
        case duration
        case size
        case width
        case height
    }

    /// Decodes integer-like numeric fields that may be emitted as either integers or doubles.
    private static func decodeIntegerValue(forKey key: CodingKeys, from container: KeyedDecodingContainer<CodingKeys>) throws -> Int? {
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue
        }

        guard let doubleValue = try? container.decode(Double.self, forKey: key) else {
            return nil
        }

        guard doubleValue.isFinite, !doubleValue.isNaN else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "GIF numeric field must be a finite number."
            )
        }

        guard doubleValue.rounded() == doubleValue else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "GIF numeric field must be an integral value."
            )
        }

        guard let exactInt = Int(exactly: doubleValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "GIF numeric field is out of supported range."
            )
        }

        return exactInt
    }
}

private struct KLIPYFileFormats: Decodable {
    let hd: GIFMediaFormats?
    let md: GIFMediaFormats?
    let sm: GIFMediaFormats?
    let xs: GIFMediaFormats?

    var asMediaFormats: GIFMediaFormats {
        sm ?? md ?? hd ?? xs ?? GIFMediaFormats(
            gif: nil,
            webp: nil,
            jpg: nil,
            mp4: nil,
            webm: nil,
            tinygif: nil,
            tinymp4: nil,
            tinywebm: nil
        )
    }
}
