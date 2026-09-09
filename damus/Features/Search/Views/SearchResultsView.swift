//
//  SearchResultsView.swift
//  damus
//
//  Created by William Casarin on 2022-06-06.
//

import SwiftUI

struct MultiSearch {
    let text: String
    let hashtag: String
    let profiles: [Pubkey]
}

enum Search: Identifiable {
    case profiles([Pubkey])
    case hashtag(String)
    case profile(Pubkey)
    case note(NoteId)
    case nip05(String)
    case hex(Data)
    case multi(MultiSearch)
    case nevent(NEvent)
    case naddr(NAddr)
    case nprofile(NProfile)
    
    var id: String {
        switch self {
        case .profiles: return "profiles"
        case .hashtag: return "hashtag"
        case .profile: return "profile"
        case .note: return "note"
        case .nip05: return "nip05"
        case .hex: return "hex"
        case .multi: return "multi"
        case .nevent: return "nevent"
        case .naddr: return "naddr"
        case .nprofile: return "nprofile"
        }
    }
}

/// The pill every tappable row on the search pane wears.
private extension View {
    func searchChip() -> some View {
        self
            .padding(.horizontal, 15)
            .padding(.vertical, 5)
            .background(DamusColors.neutral1)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(DamusColors.neutral3, lineWidth: 1)
            )
    }
}

struct InnerSearchResults: View {
    let damus_state: DamusState
    let search: Search?

    func ProfileSearchResult(pk: Pubkey) -> some View {
        FollowUserView(target: .pubkey(pk), damus_state: damus_state)
    }

    func HashtagSearch(_ ht: String) -> some View {
        let search_model = SearchModel(state: damus_state, search: .filter_hashtag([ht]))
        return NavigationLink(value: Route.Search(search: search_model)) {
            HStack {
                Text(verbatim: "#\(ht)")
            }
            .searchChip()
        }
    }

    /// Parses the typed text into the query the results screen will run.
    ///
    /// A full DSL parse rather than a bag of literal keywords. The plain-word row
    /// and the old "Advanced search" row now lead to the same screen, so anything
    /// the parser understands has to be understood *here* or typing it would
    /// quietly stop working: `from:`, `since:`, `kind:` and quoted phrases all keep
    /// their meaning, and somebody who wants the literal text still has the DSL's
    /// own escape hatch — quoting it.
    ///
    /// `#foo` becoming a tag axis rather than a keyword is the one collision worth
    /// naming. ``search_for_string`` already routes a *leading* `#` to the hashtag
    /// timeline before this view is reached, so it only applies to a tag written
    /// mid-query — where the tag index is what was meant anyway.
    private func parse(_ text: String) -> AdvancedSearchQueryDSL.ParseResult {
        AdvancedSearchQueryDSL.parse(text, resolveAuthor: { name in
            search_profiles(profiles: damus_state.profiles, contacts: damus_state.contacts, search: name).first
        })
    }

    /// The one row that runs the typed text against the note index.
    ///
    /// One row, not the "Search word:" and "Advanced search" pair it replaces:
    /// those led to two different result screens, and now that they lead to the
    /// same one a second chip has nothing left to offer. Only the label still
    /// varies, because "Search word: from:jb55 dog" would misdescribe the query.
    ///
    /// A `Button` rather than a `NavigationLink(value:)` because the route carries
    /// a model, and a link's value is rebuilt on every render of a view that
    /// re-renders on every keystroke.
    private func NoteSearch(_ parsed: AdvancedSearchQueryDSL.ParseResult, text: String) -> some View {
        Button(action: {
            damus_state.nav.push(route: .AdvancedSearch(model: AdvancedSearchModel(damus_state: damus_state, query: parsed.query)))
        }) {
            HStack {
                if parsed.usedAdvancedSyntax {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Advanced search", comment: "Navigation link to run the typed query as an advanced search.")
                } else {
                    Text("Search word: \(text)", comment: "Navigation link to search for a word.")
                }
            }
            .searchChip()
        }
        .buttonStyle(.plain)
    }

    /// Names a `from:` that matched nobody on this device.
    ///
    /// The DSL neither drops such an author nor degrades it to a keyword, because
    /// both would silently change what the query means — dropping it widens the
    /// search to everybody, and keeping it as a keyword searches note text for
    /// "from:jb55". So it reports it instead and leaves somebody to say so, and
    /// this is where the question comes up.
    private func UnresolvedAuthors(_ names: [String]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
            Text("No profile found for \(names.joined(separator: ", "))", comment: "Warning that an author named in a search query matches nobody known to this device.")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    func ProfilesSearch(_ results: [Pubkey]) -> some View {
        return LazyVStack {
            ForEach(results, id: \.id) { pk in
                ProfileSearchResult(pk: pk)
            }
        }
    }

    /// Everything a free-text query offers: the tag timeline, the note search, and
    /// the profiles whose names match.
    @ViewBuilder
    private func MultiSearch(_ multi: MultiSearch) -> some View {
        let parsed = parse(multi.text)

        VStack(alignment: .leading) {
            HStack(spacing: 20) {
                HashtagSearch(multi.hashtag)
                NoteSearch(parsed, text: multi.text)
            }

            if !parsed.unresolvedAuthors.isEmpty {
                UnresolvedAuthors(parsed.unresolvedAuthors)
                    .padding(.top, 10)
            }

            Spacer()
                .frame(height: 10)

            ProfilesSearch(multi.profiles)
        }
    }

    var body: some View {
        Group {
            switch search {
            case .profiles(let results):
                ProfilesSearch(results)
            case .hashtag(let ht):
                HashtagSearch(ht)
            case .nip05(let addr):
                SearchingEventView(state: damus_state, search_type: .nip05(addr))
            case .profile(let pubkey):
                SearchingEventView(state: damus_state, search_type: .profile(pubkey, relays: []))
            case .hex(let h):
                VStack(spacing: 10) {
                    SearchingEventView(state: damus_state, search_type: .event(NoteId(h), relays: []))
                    SearchingEventView(state: damus_state, search_type: .profile(Pubkey(h), relays: []))
                }
            case .note(let nid):
                SearchingEventView(state: damus_state, search_type: .event(nid, relays: []))
            case .nevent(let nevent):
                SearchingEventView(state: damus_state, search_type: .event(nevent.noteid, relays: nevent.relays))
            case .nprofile(let nprofile):
                SearchingEventView(state: damus_state, search_type: .profile(nprofile.author, relays: nprofile.relays))
            case .naddr(let naddr):
                SearchingEventView(state: damus_state, search_type: .naddr(naddr))
            case .multi(let multi):
                MultiSearch(multi)
            case .none:
                Text("none", comment: "No search results.")
            }
        }
    }
}

/// The search pane: what the typed string could mean, as a list of ways in.
///
/// Nothing is searched from here. Note results live on ``AdvancedSearchView``,
/// behind ``InnerSearchResults``'s note-search row, which is also what makes the
/// mute list this view's non-problem: the results screen re-runs its own query
/// when the mute list changes.
struct SearchResultsView: View {
    let damus_state: DamusState
    @Binding var search: String
    @State var result: Search? = nil

    var body: some View {
        ScrollView {
            InnerSearchResults(damus_state: damus_state, search: result)
                .padding()
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            self.result = search_for_string(profiles: damus_state.profiles, contacts: damus_state.contacts, search: search)
        }
        .onChange(of: search) { _ in
            self.result = search_for_string(profiles: damus_state.profiles, contacts: damus_state.contacts, search: search)
        }
    }
}

/// Interprets a raw search string and maps it to an appropriate `Search` case.
/// - Parameters:
///   - profiles: Profile index used when resolving profile-lookups from the query.
///   - contacts: Contact list used to prioritize or resolve profile-lookups.
///   - search new: The raw user-provided search string to interpret.
/// - Returns: A `Search` value representing the parsed query (e.g., `.nip05`, `.hashtag`, `.hex`, `.profile`, `.note`, `.nevent`, `.nprofile`, `.naddr`, or `.multi`), or `nil` if the input string is empty.

@MainActor
func search_for_string(profiles: Profiles, contacts: Contacts, search new: String) -> Search? {
    guard new.count != 0 else {
        return nil
    }
    
    let splitted = new.split(separator: "@")
    
    if splitted.count == 2 {
        return .nip05(new)
    }
    
    if new.first! == "#" {
        return .hashtag(make_hashtagable(new))
    }
    
    let searchQuery = remove_nostr_uri_prefix(new)
    
    if let new = hex_decode_id(searchQuery) {
        return .hex(new)
    }

    if searchQuery.starts(with: "npub") {
        if let decoded = bech32_pubkey_decode(searchQuery) {
            return .profile(decoded)
        }
    }
    
    if searchQuery.starts(with: "note"), let decoded = try? bech32_decode(searchQuery) {
        return .note(NoteId(decoded.data))
    }
    
    if searchQuery.starts(with: "nevent"), case let .nevent(nevent) = Bech32Object.parse(searchQuery) {
        #if DEBUG
        print("[nevent] Parsed note ID: \(nevent.noteid.hex())")
        print("[nevent] Parsed \(nevent.relays.count) relay hints: \(nevent.relays.map { $0.absoluteString })")
        #endif
        return .nevent(nevent)
    }
    
    if searchQuery.starts(with: "nprofile"), case let .nprofile(nprofile) = Bech32Object.parse(searchQuery) {
        return .nprofile(nprofile)
    }
    
    if searchQuery.starts(with: "naddr"), case let .naddr(naddr) = Bech32Object.parse(searchQuery) {
        return .naddr(naddr)
    }
    
    let multisearch = MultiSearch(text: new, hashtag: make_hashtagable(searchQuery), profiles: search_profiles(profiles: profiles, contacts: contacts, search: new))
    return .multi(multisearch)
}

func make_hashtagable(_ str: String) -> String {
    var new = str
    guard str.utf8.count > 0 else {
        return str
    }
    
    if new.hasPrefix("#") {
        new = String(new.dropFirst())
    }
    
    return String(new.filter{$0 != " "})
}

/// Query the existing nostrdb profile index; asynchronous callers run this off the main actor.
func search_profile_ids(profiles: Profiles, search: String) -> [Pubkey] {
    if let pubkey = hex_decode_pubkey(search),
       (try? profiles.lookup_key_by_pubkey(pubkey)) != nil {
        return [pubkey]
    }
    if search.starts(with: "npub"),
       let bech32_key = decode_bech32_key(search),
       case Bech32Key.pub(let pubkey) = bech32_key,
       (try? profiles.lookup_key_by_pubkey(pubkey)) != nil {
        return [pubkey]
    }
    return (try? profiles.search(search, limit: 128)) ?? []
}

@MainActor
func search_profiles(profiles: Profiles, contacts: Contacts, search: String) -> [Pubkey] {
    search_profile_ids(profiles: profiles, search: search).sorted { a, b in
        (get_friend_type(contacts: contacts, pubkey: a)?.priority ?? 0) >
            (get_friend_type(contacts: contacts, pubkey: b)?.priority ?? 0)
    }
}
