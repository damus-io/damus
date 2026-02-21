//
//  NIP05DomainTimelineHeaderView.swift
//  damus
//
//  Created by Terry Yiu on 5/16/25.
//

import FaviconFinder
import Kingfisher
import SwiftUI

// MARK: - Domain Title View

/// Displays the NIP-05 domain name with its favicon as a tappable link.
/// Tapping opens the domain's website in the browser.
struct NIP05DomainTitleView: View {
    @ObservedObject var model: NIP05DomainEventsModel
    let nip05_domain_favicon: FaviconURL?

    @Environment(\.openURL) var openURL

    var body: some View {
        Button {
            guard let url = URL(string: "https://\(model.domain)") else { return }
            openURL(url)
        } label: {
            HStack(spacing: 6) {
                if let nip05_domain_favicon {
                    KFImage(nip05_domain_favicon.source)
                        .imageContext(.favicon, disable_animation: true)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .clipped()
                }

                Text(model.domain)
                    .foregroundStyle(DamusLogoGradient.gradient)
                    .font(.title2.bold())
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friends View

/// Displays a summary of authors posting from this NIP-05 domain.
/// Shows stacked profile pictures with a text description below.
/// Tapping navigates to the full list of domain members.
struct NIP05DomainFriendsView: View {
    let damus_state: DamusState
    @ObservedObject var model: NIP05DomainEventsModel
    let nip05_domain_favicon: FaviconURL?

    /// Collects all unique authors from both loaded events and the subscription filter.
    /// Preserves order with most active authors (by event recency) appearing first.
    private var allAuthors: [Pubkey] {
        let eventAuthors = model.events.all_events.map { $0.pubkey }
        let filterAuthors = model.filter.authors ?? []

        var seen = Set<Pubkey>()
        return (eventAuthors + filterAuthors).filter { seen.insert($0).inserted }
    }

    var body: some View {
        let authors = allAuthors

        Button {
            guard !authors.isEmpty else { return }
            damus_state.nav.push(route: Route.NIP05DomainPubkeys(
                domain: model.domain,
                nip05_domain_favicon: nip05_domain_favicon,
                pubkeys: authors
            ))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Smaller avatars (24pt) stacked horizontally
                CondensedProfilePicturesView(state: damus_state, pubkeys: authors, maxPictures: 4, size: 24)

                // Description text below avatars, allowing 2 lines for longer lists
                Text(notesFromAuthorsString(authors, ndb: damus_state.ndb))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Author String Generation

/// Generates a localized "Notes from X, Y & Z others" string for the given authors.
///
/// Examples:
/// - 0 authors: "No notes yet"
/// - 1 author: "Notes from Alice"
/// - 2 authors: "Notes from Alice & Bob"
/// - 3 authors: "Notes from Alice, Bob & Carol"
/// - 4+ authors: "Notes from Alice, Bob, Carol & 2 others"
func notesFromAuthorsString(_ authors: [Pubkey], ndb: Ndb, locale: Locale = Locale.current) -> String {
    let bundle = bundleForLocale(locale: locale)

    // Get display names for up to the first 3 authors
    let names: [String] = authors.prefix(3).map { pk in
        let profile = try? ndb.lookup_profile_and_copy(pk)
        return Profile.displayName(profile: profile, pubkey: pk).username.truncate(maxLength: 20)
    }

    switch authors.count {
    case 0:
        return NSLocalizedString("No notes yet", bundle: bundle, comment: "Text when no notes are available from this domain")
    case 1:
        let format = NSLocalizedString("Notes from %@", bundle: bundle, comment: "Text showing notes from one author")
        return String(format: format, locale: locale, names[0])
    case 2:
        let format = NSLocalizedString("Notes from %@ & %@", bundle: bundle, comment: "Text showing notes from two authors")
        return String(format: format, locale: locale, names[0], names[1])
    case 3:
        let format = NSLocalizedString("Notes from %@, %@ & %@", bundle: bundle, comment: "Text showing notes from three authors")
        return String(format: format, locale: locale, names[0], names[1], names[2])
    default:
        let format = localizedStringFormat(key: "notes_from_three_and_others", locale: locale)
        return String(format: format, locale: locale, authors.count - 3, names[0], names[1], names[2])
    }
}

// MARK: - Legacy Header View

/// Full header view combining title and friends sections.
/// Kept for backwards compatibility with existing usages.
struct NIP05DomainTimelineHeaderView: View {
    let damus_state: DamusState
    @ObservedObject var model: NIP05DomainEventsModel
    let nip05_domain_favicon: FaviconURL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NIP05DomainTitleView(model: model, nip05_domain_favicon: nip05_domain_favicon)
            NIP05DomainFriendsView(damus_state: damus_state, model: model, nip05_domain_favicon: nip05_domain_favicon)
        }
    }
}

// MARK: - Friends of Friends String (Legacy)

/// Generates a localized string for friends-of-friends in the trusted network.
/// Similar to notesFromAuthorsString but with different context in comments.
func friendsOfFriendsString(_ friendsOfFriends: [Pubkey], ndb: Ndb, locale: Locale = Locale.current) -> String {
    let bundle = bundleForLocale(locale: locale)
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
        return NSLocalizedString("No one in your trusted network is associated with this domain.", bundle: bundle, comment: "Text when no friends-of-friends are associated with this NIP-05 domain")
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

// MARK: - Preview

#Preview {
    let model = NIP05DomainEventsModel(state: test_damus_state, domain: "damus.io")
    let nip05_domain_favicon = FaviconURL(source: URL(string: "https://damus.io/favicon.ico")!, format: .ico, sourceType: .ico)
    NIP05DomainTimelineHeaderView(damus_state: test_damus_state, model: model, nip05_domain_favicon: nip05_domain_favicon)
}
