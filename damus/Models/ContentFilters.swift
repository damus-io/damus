//
//  ContentFilters.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-18.
//

import Foundation

protocol ContentFilter {
    /// Function that implements the content filtering logic
    /// - Parameter ev: The nostr event to be processed
    /// - Returns: Must return `true` to show events, and return `false` to hide/filter events
    func filter(ev: NostrEvent) -> Bool
}

/// Simple filter to determine whether to show posts or all posts and replies.
enum FilterState : Int, ContentFilter {
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
struct NSFWTagFilter: ContentFilter {
    func filter(ev: NostrEvent) -> Bool {
        return ev.referenced_hashtags.first(where: { t in t.hashtag == "nsfw" }) == nil
    }
}

/// Generic filter with various tweakable settings
struct DamusFilter: ContentFilter {
    let hide_nsfw_tagged_content: Bool
    
    func filter(ev: NostrEvent) -> Bool {
        if self.hide_nsfw_tagged_content {
            return NSFWTagFilter().filter(ev: ev)
        }
        else {
            return true
        }
    }
    
    func get_filter(_ filter_state: FilterState) -> ((NostrEvent) -> Bool) {
        return { ev in
            return filter_state.filter(ev: ev) && self.filter(ev: ev)
        }
    }
    
}
