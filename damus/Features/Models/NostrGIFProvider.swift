//
//  NostrGIFProvider.swift
//  damus
//
//  Fetches GIF metadata from Nostr relays (NIP-94, kind 1063).
//

import Foundation

final class NostrGIFProvider {
    private let damusState: DamusState

    init(damusState: DamusState) {
        self.damusState = damusState
    }

    func featured(limit: Int = 30) async throws -> [GIFPickerItem] {
        await fetch(limit: limit, query: nil)
    }

    func search(query: String, limit: Int = 30) async throws -> [GIFPickerItem] {
        await fetch(limit: limit, query: query)
    }

    private func fetch(limit: Int, query: String?) async -> [GIFPickerItem] {
        var items: [GIFPickerItem] = []
        var seenIdentifiers: Set<String> = []
        let filters = [makeFilter(limit: limit, query: query)]
        let stream = damusState.nostrNetwork.pool.subscribe(filters: filters, eoseTimeout: 6)

        for await item in stream {
            switch item {
            case .event(let event):
                guard let metadata = FileMetadata.from(event: event) else {
                    continue
                }

                let mime = metadata.mimeType.lowercased()
                guard mime == "image/gif" || mime.hasSuffix("+gif") else {
                    continue
                }

                if let query, !matches(query: query, event: event, metadata: metadata) {
                    continue
                }

                let identifier = metadata.eventId?.hex() ?? metadata.url.absoluteString
                guard !seenIdentifiers.contains(identifier) else {
                    continue
                }

                let pickerItem = GIFPickerItem(
                    id: identifier,
                    title: event.content,
                    description: metadata.summary ?? metadata.alt,
                    metadata: metadata,
                    previewURL: metadata.previewURL,
                    provider: .nostr,
                    attribution: "Nostr"
                )

                items.append(pickerItem)
                seenIdentifiers.insert(identifier)

                if items.count >= limit {
                    return items
                }
            case .eose:
                return items
            }
        }

        return items
    }

    private func makeFilter(limit: Int, query: String?) -> NostrFilter {
        var effectiveLimit = limit
        if let query, !query.isEmpty {
            // Grab a few extra results when searching so we can filter client-side.
            effectiveLimit = limit * 3
        }
        return NostrFilter(kinds: [.file_metadata], limit: UInt32(effectiveLimit))
    }

    private func matches(query: String, event: NostrEvent, metadata: FileMetadata) -> Bool {
        let needles = query.lowercased().split(separator: " ").map(String.init)
        guard !needles.isEmpty else { return true }

        var haystack: [String] = []
        if !event.content.isEmpty { haystack.append(event.content.lowercased()) }
        if let alt = metadata.alt?.lowercased() { haystack.append(alt) }
        if let summary = metadata.summary?.lowercased() { haystack.append(summary) }
        if let title = metadata.url.lastPathComponent.lowercased() as String? {
            haystack.append(title)
        }

        let tagStrings: [String] = event.tags.reduce(into: []) { acc, tag in
            for component in tag.strings().dropFirst() {
                acc.append(component.lowercased())
            }
        }
        haystack.append(contentsOf: tagStrings)

        return needles.allSatisfy { needle in
            haystack.contains(where: { $0.contains(needle) })
        }
    }
}
