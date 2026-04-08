//
//  FilterBuilderModel.swift
//  damus
//
//  Observable model backing the visual filter builder form.
//

import Foundation

/// Common kind presets for quick selection in the filter builder.
struct KindPreset: Identifiable, Hashable {
    let kind: UInt32
    let label: String

    var id: UInt32 { kind }

    static let presets: [KindPreset] = [
        KindPreset(kind: 1, label: NSLocalizedString("Notes", comment: "Kind 1 label")),
        KindPreset(kind: 6, label: NSLocalizedString("Reposts", comment: "Kind 6 label")),
        KindPreset(kind: 7, label: NSLocalizedString("Reactions", comment: "Kind 7 label")),
        KindPreset(kind: 30023, label: NSLocalizedString("Long-form", comment: "Kind 30023 label")),
        KindPreset(kind: 9735, label: NSLocalizedString("Zaps", comment: "Kind 9735 label")),
        KindPreset(kind: 9802, label: NSLocalizedString("Highlights", comment: "Kind 9802 label")),
    ]
}

/// Relative time presets for the "since" selector.
struct TimePreset: Identifiable, Hashable {
    let tag: String
    let label: String

    var id: String { tag }

    static let presets: [TimePreset] = [
        TimePreset(tag: "1h", label: NSLocalizedString("1 hour", comment: "Time preset")),
        TimePreset(tag: "6h", label: NSLocalizedString("6 hours", comment: "Time preset")),
        TimePreset(tag: "24h", label: NSLocalizedString("24 hours", comment: "Time preset")),
        TimePreset(tag: "7d", label: NSLocalizedString("7 days", comment: "Time preset")),
        TimePreset(tag: "30d", label: NSLocalizedString("30 days", comment: "Time preset")),
    ]
}

/// The author scope for a spell feed.
enum AuthorScope: Hashable {
    /// No author filter — global feed.
    case anyone
    /// Only the user's own events.
    case me
    /// Only events from people the user follows.
    case contacts
}

/// Observable state for the filter builder form.
///
/// Collects user selections and synthesizes a kind:777 spell event on save.
@MainActor
class FilterBuilderModel: ObservableObject {
    /// Display name for the feed tab.
    @Published var feedName: String = ""
    /// Description shown in the spell content.
    @Published var feedDescription: String = ""
    /// Which kind presets are selected.
    @Published var selectedKinds: Set<UInt32> = [1]
    /// Custom kind number entered by user.
    @Published var customKindText: String = ""
    /// The author scope.
    @Published var authorScope: AuthorScope = .anyone
    /// The selected time preset tag (e.g. "24h"), or empty for no since filter.
    @Published var sincePreset: String = "24h"
    /// Optional search text.
    @Published var searchText: String = ""
    /// Optional hashtag filter.
    @Published var hashtagText: String = ""
    /// Result limit.
    @Published var limit: Int = 100

    /// Whether the form is valid for saving.
    var isValid: Bool {
        !feedName.trimmingCharacters(in: .whitespaces).isEmpty && !selectedKinds.isEmpty
    }

    /// Build the NIP-A7 tags from form state.
    func buildTags() -> [[String]] {
        var tags: [[String]] = []

        tags.append(["cmd", "REQ"])

        for kind in selectedKinds.sorted() {
            tags.append(["k", "\(kind)"])
        }

        if let customKind = UInt32(customKindText.trimmingCharacters(in: .whitespaces)), customKind > 0 {
            if !selectedKinds.contains(customKind) {
                tags.append(["k", "\(customKind)"])
            }
        }

        switch authorScope {
        case .anyone:
            break
        case .me:
            tags.append(["authors", "$me"])
        case .contacts:
            tags.append(["authors", "$contacts"])
        }

        if !sincePreset.isEmpty {
            tags.append(["since", "-\(sincePreset)"])
        }

        let search = searchText.trimmingCharacters(in: .whitespaces)
        if !search.isEmpty {
            tags.append(["search", search])
        }

        let hashtag = hashtagText.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if !hashtag.isEmpty {
            tags.append(["tag", "t", hashtag])
        }

        tags.append(["limit", "\(limit)"])

        let name = feedName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            tags.append(["name", name])
        }

        return tags
    }

    /// Build and return a SavedSpellFeed, or nil if invalid.
    func buildSavedFeed() -> SavedSpellFeed? {
        guard isValid else { return nil }

        let kp = generate_new_keypair().to_keypair()
        let tags = buildTags()
        let content = feedDescription.trimmingCharacters(in: .whitespaces)

        guard let ev = NdbNote(
            content: content,
            keypair: kp,
            kind: 777,
            tags: tags
        ) else {
            return nil
        }

        let name = feedName.trimmingCharacters(in: .whitespaces)
        let json = event_to_json(ev: ev)
        return SavedSpellFeed(
            id: UUID().uuidString,
            name: name,
            spellEventJSON: json
        )
    }
}
