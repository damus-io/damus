//
//  ContentFilters.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-18.
//

import Foundation

/// Timeline source determines whether to show content from follows or favorites
enum TimelineSource: CustomStringConvertible {
    case follows
    case favorites

    var description: String {
        switch self {
        case .follows:
            return NSLocalizedString("Follows", comment: "Show Notes from your following")
        case .favorites:
            return NSLocalizedString("Favorites", comment: "Show Notes from your favorites")
        }
    }
}

/// Simple filter to determine whether to show posts or all posts and replies.
enum FilterState : Int {
    case posts = 0
    case posts_and_replies = 1
    case conversations = 2
    case follow_list = 3

    func filter(ev: NostrEvent) -> Bool {
        switch self {
        case .posts:
            return ev.known_kind == .boost || ev.known_kind == .highlight || !ev.is_reply()
        case .posts_and_replies:
            return true
        case .conversations:
            return true
        case .follow_list:
            return ev.known_kind == .follow_list
        }
    }
}

/// Returns true when an event is tagged with #nsfw (case-insensitive).
func event_has_nsfw_tag(_ ev: NostrEvent) -> Bool {
    return ev.referenced_hashtags.contains { tag in
        tag.hashtag.caseInsensitiveCompare("nsfw") == .orderedSame
    }
}

/// Simple filter to determine whether to show posts with #nsfw tags
func nsfw_tag_filter(ev: NostrEvent) -> Bool {
    return !event_has_nsfw_tag(ev)
}

func get_repost_of_muted_user_filter(damus_state: DamusState) -> ((_ ev: NostrEvent) -> Bool) {
    return { ev in
        guard ev.known_kind == .boost else { return true }
        // This needs to use cached because it can be way too slow otherwise
        guard let inner_ev = ev.get_cached_inner_event(cache: damus_state.events) else { return true }
        return should_show_event(state: damus_state, ev: inner_ev)
    }
}

func timestamp_filter(ev: NostrEvent) -> Bool {
    // Allow notes that are created no more than 3 seconds in the future
    // to account for natural clock skew between sender and receiver.
    ev.age >= -3
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
        filters.append(timestamp_filter)
        return filters
    }
}
