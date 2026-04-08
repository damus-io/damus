//
//  StarterSpells.swift
//  damus
//
//  Hardcoded starter spell feeds seeded on first launch.
//

import Foundation

struct StarterSpells {
    /// Starter feeds seeded into FeedTabStore on first launch.
    static let feeds: [SavedSpellFeed] = buildStarterFeeds()

    private static func buildStarterFeeds() -> [SavedSpellFeed] {
        let kp = generate_new_keypair().to_keypair()
        var result: [SavedSpellFeed] = []

        // Global notes: kind:1 from the last 24 hours
        if let ev = NdbNote(
            content: "Global notes from the last 24 hours",
            keypair: kp,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["since", "-24h"]]
        ) {
            result.append(SavedSpellFeed(
                id: "starter_global_notes",
                name: "Global",
                spellEventJSON: event_to_json(ev: ev)
            ))
        }

        // Images: kind:20 (NIP-68 picture events)
        if let ev = NdbNote(
            content: "Picture posts",
            keypair: kp,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "20"], ["since", "-24h"]]
        ) {
            result.append(SavedSpellFeed(
                id: "starter_images",
                name: "Images",
                spellEventJSON: event_to_json(ev: ev)
            ))
        }

        return result
    }
}
