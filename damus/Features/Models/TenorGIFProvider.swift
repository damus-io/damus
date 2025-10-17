//
//  TenorGIFProvider.swift
//  damus
//
//  Lightweight wrapper that converts Tenor API responses into picker items.
//

import Foundation

@MainActor
final class TenorGIFProvider {
    private let api: TenorAPI

    init(api: TenorAPI = .shared) {
        self.api = api
    }

    func featured(limit: Int = 30) async throws -> [GIFPickerItem] {
        let gifs = try await api.featured(limit: limit)
        return gifs.compactMap(makeItem(from:))
    }

    func search(query: String, limit: Int = 30) async throws -> [GIFPickerItem] {
        let gifs = try await api.search(query: query, limit: limit)
        return gifs.compactMap(makeItem(from:))
    }

    private func makeItem(from gif: TenorGIF) -> GIFPickerItem? {
        guard let metadata = gif.toFileMetadata() else {
            return nil
        }

        return GIFPickerItem(
            id: gif.id,
            title: gif.title,
            description: gif.content_description,
            metadata: metadata,
            previewURL: gif.previewURL,
            provider: .tenor,
            attribution: "Tenor"
        )
    }
}
