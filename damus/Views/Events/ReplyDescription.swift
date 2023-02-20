//
//  ReplyDescription.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

// jb55 - TODO: this could be a lot better
struct ReplyDescription: View {
    let event: NostrEvent
    let profiles: Profiles
    
    var body: some View {
        Text(verbatim: "\(reply_desc(profiles: profiles, event: event))")
            .font(.footnote)
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReplyDescription_Previews: PreviewProvider {
    static var previews: some View {
        ReplyDescription(event: test_event, profiles: test_damus_state().profiles)
    }
}

func reply_desc(profiles: Profiles, event: NostrEvent) -> String {
    let desc = make_reply_description(event.tags)
    let pubkeys = desc.pubkeys
    let n = desc.others

    if desc.pubkeys.count == 0 {
        return NSLocalizedString("Replying to self", comment: "Label to indicate that the user is replying to themself.")
    }

    let names: [String] = pubkeys.map {
        let prof = profiles.lookup(id: $0)
        return Profile.displayName(profile: prof, pubkey: $0)
    }

    let othersCount = n - pubkeys.count
    if names.count > 1 {
        if othersCount == 0 {
            return String(format: "Replying to %@ & %@", names[0], names[1])
        } else {
            return String(format: "Replying to %@, %@ & %d others", names[0], names[1], othersCount)
        }
    }

    if othersCount == 0 {
        return String(format: "Replying to %@", names[0])
    } else {
        return String(format: "Replying to %@ & %d others", names[0], othersCount)
    }
}


