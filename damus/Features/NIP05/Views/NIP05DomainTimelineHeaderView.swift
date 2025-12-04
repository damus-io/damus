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
    let friend_filter: FriendFilter

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

    private func domainAuthors() -> [Pubkey] {
        NIP05DomainHelpers.ordered_domain_authors(
            domain: model.domain,
            friend_filter: friend_filter,
            contacts: damus_state.contacts,
            profiles: damus_state.profiles,
            eventPubkeys: model.events.all_events.map { $0.pubkey },
            filterAuthors: model.filter.authors
        )
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

            let authors = domainAuthors()

            HStack {
                CondensedProfilePicturesView(state: damus_state, pubkeys: authors, maxPictures: 3)
                let description = friendsOfFriendsString(authors, ndb: damus_state.ndb, wotEnabled: friend_filter == .friends_of_friends)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
            }
            .onTapGesture {
                if !authors.isEmpty {
                    damus_state.nav.push(route: Route.NIP05DomainPubkeys(domain: model.domain, nip05_domain_favicon: nip05_domain_favicon, pubkeys: authors))
                }
            }
        }
    }
}

/// Generates a localized string describing which authors' notes are shown in the feed
///
/// Formats the display text based on how many authors have notes:
/// - 0 authors: Shows empty state message (different for WOT on/off)
/// - 1-3 authors: Lists names explicitly ("Notes from Alice", "Notes from Alice & Bob", etc.)
/// - 4+ authors: Shows first 3 names plus count of others
///
/// - Parameters:
///   - friendsOfFriends: Array of pubkeys with notes in this feed
///   - ndb: Nostrdb instance for profile lookups
///   - locale: Locale for string formatting
///   - wotEnabled: Whether Web-of-Trust filtering is active
/// - Returns: Localized description string
func friendsOfFriendsString(_ friendsOfFriends: [Pubkey], ndb: Ndb, locale: Locale = Locale.current, wotEnabled: Bool = true) -> String {
    let bundle = bundleForLocale(locale: locale)

    // Get display names for up to 3 authors
    let names: [String] = friendsOfFriends.prefix(3).map { pk in
        let profile = try? ndb.lookup_profile(pk, borrow: { pr in
            switch pr {
            case .some(let pr): return pr.profile
            case .none: return nil
            }
        })
        return Profile.displayName(profile: profile, pubkey: pk).username.truncate(maxLength: 20)
    }

    switch friendsOfFriends.count {
    case 0:
        // Different empty state messaging based on WOT mode
        if wotEnabled {
            return "No one in your trusted network is associated with this domain."
        } else {
            return "No cached profiles found for this domain. Try following users from this domain to see their notes."
        }
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
    NIP05DomainTimelineHeaderView(damus_state: test_damus_state, model: model, nip05_domain_favicon: nip05_domain_favicon, friend_filter: .friends_of_friends)
}
