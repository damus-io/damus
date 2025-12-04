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
        // Order with authors that already have events first to make the header feel responsive.
        let pubkeys = model.events.all_events.map { $0.pubkey } + (model.filter.authors ?? [])
        let orderedUnique = NSMutableOrderedSet(array: pubkeys).array as? [Pubkey] ?? []

        // Only keep pubkeys that match the domain; use nip05 host (validated or not) so we surface everyone in scope.
        let matching = orderedUnique.filter { pk in
            let validated = damus_state.profiles.is_validated(pk)
            if let host = validated?.host {
                return host.caseInsensitiveCompare(model.domain) == .orderedSame
            }
            let profile = damus_state.profiles.lookup(id: pk)?.unsafeUnownedValue
            guard let nip05_str = profile?.nip05,
                  let nip05 = NIP05.parse(nip05_str) else {
                return false
            }
            return nip05.host.caseInsensitiveCompare(model.domain) == .orderedSame
        }

        if friend_filter == .friends_of_friends {
            return matching.filter { damus_state.contacts.is_in_friendosphere($0) }
        }

        return matching
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
                let description = friendsOfFriendsString(authors, ndb: damus_state.ndb)
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

func friendsOfFriendsString(_ friendsOfFriends: [Pubkey], ndb: Ndb, locale: Locale = Locale.current) -> String {
    let bundle = bundleForLocale(locale: locale)
    let names: [String] = friendsOfFriends.prefix(3).map { pk in
        let profile = ndb.lookup_profile(pk)?.unsafeUnownedValue?.profile
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
