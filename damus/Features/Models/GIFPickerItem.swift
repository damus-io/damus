//
//  GIFPickerItem.swift
//  damus
//
//  Represents a unified GIF item surfaced in the picker, regardless of source.
//

import Foundation

struct GIFPickerItem: Identifiable {
    enum ProviderSource: String {
        case nostr
        case tenor
    }

    let id: String
    let title: String
    let description: String?
    let metadata: FileMetadata
    let previewURL: URL?
    let provider: ProviderSource
    let attribution: String?

    init(
        id: String,
        title: String,
        description: String? = nil,
        metadata: FileMetadata,
        previewURL: URL?,
        provider: ProviderSource,
        attribution: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.metadata = metadata
        self.previewURL = previewURL
        self.provider = provider
        self.attribution = attribution
    }

    var displayTitle: String {
        if !title.isEmpty {
            return title
        }
        if let description, !description.isEmpty {
            return description
        }
        if let alt = metadata.alt, !alt.isEmpty {
            return alt
        }
        return metadata.url.lastPathComponent
    }

    var fallbackAlt: String? {
        return metadata.alt ?? description ?? title
    }
}
