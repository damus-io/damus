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

func reply_desc(profiles: Profiles, event: NostrEvent, locale: Locale = Locale.current) -> String {
    let desc = make_reply_description(event.tags)
    let pubkeys = desc.pubkeys
    let n = desc.others

    let bundle = bundleForLocale(locale: locale)

    if desc.pubkeys.count == 0 {
        return NSLocalizedString("Replying to self", bundle: bundle, comment: "Label to indicate that the user is replying to themself.")
    }

    let names: [String] = pubkeys.map {
        let prof = profiles.lookup(id: $0)
        return Profile.displayName(profile: prof, pubkey: $0).username
    }
    
    let uniqueNames = NSOrderedSet(array: names).array as! [String]

    if uniqueNames.count > 1 {
        let othersCount = n - pubkeys.count
        if othersCount == 0 {
            return String(format: NSLocalizedString("Replying to %@ & %@", bundle: bundle, comment: "Label to indicate that the user is replying to 2 users."), locale: locale, uniqueNames[0], uniqueNames[1])
        } else {
            return String(format: localizedStringFormat(key: "replying_to_two_and_others", locale: locale), locale: locale, othersCount, uniqueNames[0], uniqueNames[1])
        }
    }

    return String(format: NSLocalizedString("Replying to %@", bundle: bundle, comment: "Label to indicate that the user is replying to 1 user."), locale: locale, uniqueNames[0])
}


