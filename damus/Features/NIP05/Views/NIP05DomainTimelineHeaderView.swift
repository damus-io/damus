//
//  NIP05DomainTimelineHeaderView.swift
//  damus
//
//  Created by Terry Yiu on 5/16/25.
//

import FaviconFinder
import Kingfisher
import SwiftUI

struct NIP05DomainTimelineHeaderView: View {
    let damus_state: DamusState
    @ObservedObject var model: NIP05DomainEventsModel
    let nip05_domain_favicon: FaviconURL?

    @Environment(\.openURL) var openURL

    var Icon: some View {
        ZStack {
            if let nip05_domain_favicon {
                KFImage(nip05_domain_favicon.source)
                    .imageContext(.favicon, disable_animation: true)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipped()
            } else {
                EmptyView()
            }
        }
    }

    var friendsOfFriends: [Pubkey] {
        // Order it such that the pubkeys that have events come first in the array so that their profile pictures
        // show first.
        let pubkeys = model.events.all_events.map { $0.pubkey } + (model.filter.authors ?? [])

        // Filter out duplicates but retain order, and filter out any that do not have a validated NIP-05.
        return (NSMutableOrderedSet(array: pubkeys).array as? [Pubkey] ?? [])
            .filter {
                damus_state.contacts.is_in_friendosphere($0) && damus_state.profiles.is_validated($0) != nil
            }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if nip05_domain_favicon != nil {
                    Icon
                }

                Text(model.domain)
                    .foregroundStyle(DamusLogoGradient.gradient)
                    .font(.title.bold())
                    .onTapGesture {
                        if let url = URL(string: "https://\(model.domain)") {
                            openURL(url)
                        }
                    }
            }

            let friendsOfFriends = friendsOfFriends

            HStack {
                CondensedProfilePicturesView(state: damus_state, pubkeys: friendsOfFriends, maxPictures: 3)
                let friendsOfFriendsString = friendsOfFriendsString(friendsOfFriends, ndb: damus_state.ndb)
                Text(friendsOfFriendsString)
                    .font(.subheadline)
                    .foregroundColor(DamusColors.mediumGrey)
                    .multilineTextAlignment(.leading)
            }
            .onTapGesture {
                if !friendsOfFriends.isEmpty {
                    damus_state.nav.push(route: Route.NIP05DomainPubkeys(domain: model.domain, nip05_domain_favicon: nip05_domain_favicon, pubkeys: friendsOfFriends))
                }
            }
        }
    }
}

func friendsOfFriendsString(_ friendsOfFriends: [Pubkey], ndb: Ndb, locale: Locale = Locale.current) -> String {
    let bundle = bundleForLocale(locale: locale)
    let names: [String] = friendsOfFriends.prefix(3).map { pk in
        let profile = ndb.lookup_profile(pk, borrow: { pr in
            switch pr {
            case .some(let pr): return pr.profile
            case .none: return nil
            }
        })
        return Profile.displayName(profile: profile, pubkey: pk).username.truncate(maxLength: 20)
    }

    switch friendsOfFriends.count {
    case 0:
        return "No one in your trusted network is associated with this domain."
    case 1:
        let format = NSLocalizedString("Notes from %@", bundle: bundle, comment: "Text to indicate that notes from one pubkey in our trusted network are shown below.")
        return String(format: format, locale: locale, names[0])
    case 2:
        let format = NSLocalizedString("Notes from %@ & %@", bundle: bundle, comment: "Text to indicate that notes from two pubkeys in our trusted network are shown below.")
        return String(format: format, locale: locale, names[0], names[1])
    case 3:
        let format = NSLocalizedString("Notes from %@, %@ & %@", bundle: bundle, comment: "Text to indicate that notes from three pubkeys in our trusted network are shown below.")
        return String(format: format, locale: locale, names[0], names[1], names[2])
    default:
        let format = localizedStringFormat(key: "notes_from_three_and_others", locale: locale)
        return String(format: format, locale: locale, friendsOfFriends.count - 3, names[0], names[1], names[2])
    }
}

#Preview {
    let model = NIP05DomainEventsModel(state: test_damus_state, domain: "damus.io")
    let nip05_domain_favicon = FaviconURL(source: URL(string: "https://damus.io/favicon.ico")!, format: .ico, sourceType: .ico)
    NIP05DomainTimelineHeaderView(damus_state: test_damus_state, model: model, nip05_domain_favicon: nip05_domain_favicon)
}
