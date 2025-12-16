//
//  Reposted.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import SwiftUI

struct Reposted: View {
    let damus: DamusState
    let pubkey: Pubkey
    let target: NostrEvent
    @State var reposts: Int

    init(damus: DamusState, pubkey: Pubkey, target: NostrEvent) {
        self.damus = damus
        self.pubkey = pubkey
        self.target = target
        self.reposts = damus.boosts.counts[target.id] ?? 1
    }

    var body: some View {
        HStack(alignment: .center) {
            Image("repost")
                .foregroundColor(Color.gray)

            // Show profile picture of the reposter only if the reposter is not the author of the reposted note.
            if pubkey != target.pubkey {
                ProfilePicView(pubkey: pubkey, size: eventview_pfp_size(.small), highlight: .none, profiles: damus.profiles, disable_animation: damus.settings.disable_animation, damusState: damus)
                    .onTapGesture {
                        show_profile_action_sheet_if_enabled(damus_state: damus, pubkey: pubkey)
                    }
                    .onLongPressGesture(minimumDuration: 0.1) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        damus.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                    }
            }

            NavigationLink(value: Route.Reposts(reposts: .reposts(state: damus, target: target.id))) {
                Text(people_reposted_text(profiles: damus.profiles, pubkey: pubkey, reposts: reposts))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .onReceive(handle_notify(.update_stats), perform: { note_id in
            guard note_id == target.id else { return }
            let repost_count = damus.boosts.counts[target.id]
            if let repost_count, reposts != repost_count {
                reposts = repost_count
            }
        })
    }
}

@NdbActor
func people_reposted_text(profiles: Profiles, pubkey: Pubkey, reposts: Int, locale: Locale = Locale.current) -> String {
    guard reposts > 0 else {
        return ""
    }

    let bundle = bundleForLocale(locale: locale)
    let other_reposts = reposts - 1
    let display_name = event_author_name(profiles: profiles, pubkey: pubkey)

    if other_reposts == 0 {
        return String(format: NSLocalizedString("%@ reposted", bundle: bundle, comment: "Text indicating that the note was reposted (i.e. re-shared)."), locale: locale, display_name)
    } else {
        return String(format: localizedStringFormat(key: "people_reposted_count", locale: locale), locale: locale, other_reposts, display_name)
    }
}

struct Reposted_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state
        Reposted(damus: test_state, pubkey: test_state.pubkey, target: test_note)
    }
}
