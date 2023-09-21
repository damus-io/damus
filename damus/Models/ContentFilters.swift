//
//  ContentFilters.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-18.
//

import Foundation


/// Simple filter to determine whether to show posts or all posts and replies.
enum FilterState : Int {
    case posts_and_replies = 1
    case posts = 0

    func filter(ev: NostrEvent) -> Bool {
        switch self {
        case .posts:
            return ev.known_kind == .boost || !ev.is_reply(.empty)
        case .posts_and_replies:
            return true
        }
    }
}

/// Simple filter to determine whether to show posts with #nsfw tags
func nsfw_tag_filter(ev: NostrEvent) -> Bool {
        return ev.referenced_hashtags.first(where: { t in t.hashtag == "nsfw" }) == nil
}

/// Generic filter with various tweakable settings
struct ContentFilters {
    var filters: [(NostrEvent) -> Bool]

    func filter(ev: NostrEvent) -> Bool {
        for filter in filters {
            if !filter(ev) {
                return false
            }
        }

        return true
    }
}

extension ContentFilters {
    static func defaults(_ settings: UserSettingsStore) -> [(NostrEvent) -> Bool] {
        var filters = Array<(NostrEvent) -> Bool>()
        if settings.hide_nsfw_tagged_content {
            filters.append(nsfw_tag_filter)
        }
        return filters
    }
}
