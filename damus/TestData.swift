//
//  TestData.swift
//  damus
//
//  Created by William Casarin on 2023-07-13.
//

import Foundation


let test_event_holder = EventHolder(events: [], incoming: [test_event])

let test_event =
        NostrEvent(
            content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jpg cool",
            pubkey: "pk",
            createdAt: Int64(Date().timeIntervalSince1970 - 100)
        )

func test_damus_state() -> DamusState {
    let pubkey = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
    let damus = DamusState.empty

    let prof = Profile(name: "damus", display_name: "damus", about: "iOS app!", picture: "https://damus.io/img/logo.png", banner: "", website: "https://damus.io", lud06: nil, lud16: "jb55@sendsats.lol", nip05: "damus.io", damus_donation: nil)
    let tsprof = TimestampedProfile(profile: prof, timestamp: 0, event: test_event)
    damus.profiles.add(id: pubkey, profile: tsprof)
    return damus
}

