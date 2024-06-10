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
            return ev.known_kind == .boost || !ev.is_reply()
        case .posts_and_replies:
            return true
        }
    }
}

/// Simple filter to determine whether to show posts with #nsfw tags
func nsfw_tag_filter(ev: NostrEvent) -> Bool {
    return ev.referenced_hashtags.first(where: { t in t.hashtag == "nsfw" }) == nil
}

func get_repost_of_muted_user_filter(damus_state: DamusState) -> ((_ ev: NostrEvent) -> Bool) {
    return { ev in
        guard ev.known_kind == .boost else { return true }
        // This needs to use cached because it can be way too slow otherwise
        guard let inner_ev = ev.get_cached_inner_event(cache: damus_state.events) else { return true }
        return should_show_event(state: damus_state, ev: inner_ev)
    }
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
    static func default_filters(damus_state: DamusState) -> ContentFilters {
        return ContentFilters(filters: ContentFilters.defaults(damus_state: damus_state))
    }

    static func defaults(damus_state: DamusState) -> [(NostrEvent) -> Bool] {
        var filters = Array<(NostrEvent) -> Bool>()
        if damus_state.settings.hide_nsfw_tagged_content {
            filters.append(nsfw_tag_filter)
        }
        filters.append(get_repost_of_muted_user_filter(damus_state: damus_state))
        return filters
    }
}
