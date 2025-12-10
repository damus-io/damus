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

struct InnerSearchResults: View {
    let damus_state: DamusState
    let search: Search?
    @Binding var results: [NostrEvent]
    @Binding var is_loading: Bool
    @Binding var relay_result_count: Int
    @Binding var relay_search_attempted: Bool
    
    func ProfileSearchResult(pk: Pubkey) -> some View {
        FollowUserView(target: .pubkey(pk), damus_state: damus_state)
    }
    
    func HashtagSearch(_ ht: String) -> some View {
        let search_model = SearchModel(state: damus_state, search: .filter_hashtag([ht]))
        return NavigationLink(value: Route.Search(search: search_model)) {
            HStack {
                Text("#\(ht)", comment: "Navigation link to search hashtag.")
            }
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
    
    func TextSearch(_ txt: String) -> some View {
        return NavigationLink(value: Route.NDBSearch(
            results: $results,
            isLoading: $is_loading,
            relayCount: $relay_result_count,
            relayAttempted: $relay_search_attempted
        )) {
            HStack {
                Text("Search word: \(txt)", comment: "Navigation link to search for a word.")
            }
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
    
    func ProfilesSearch(_ results: [Pubkey]) -> some View {
        return LazyVStack {
            ForEach(results, id: \.id) { pk in
                ProfileSearchResult(pk: pk)
            }
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
                SearchingEventView(state: damus_state, search_type: .profile(pubkey))
            case .hex(let h):
                VStack(spacing: 10) {
                    SearchingEventView(state: damus_state, search_type: .event(NoteId(h)))
                    SearchingEventView(state: damus_state, search_type: .profile(Pubkey(h)))
                } 
            case .note(let nid):
                SearchingEventView(state: damus_state, search_type: .event(nid))
            case .nevent(let nevent):
                SearchingEventView(state: damus_state, search_type: .event(nevent.noteid))
            case .nprofile(let nprofile):
                SearchingEventView(state: damus_state, search_type: .profile(nprofile.author))
            case .naddr(let naddr):
                SearchingEventView(state: damus_state, search_type: .naddr(naddr))
            case .multi(let multi):
                VStack(alignment: .leading) {
                    HStack(spacing: 20) {
                        HashtagSearch(multi.hashtag)
                        TextSearch(multi.text)
                    }
                    .padding(.bottom, 10)
                    
                    ProfilesSearch(multi.profiles)
                }
                
            case .none:
                Text("none", comment: "No search results.")
            }
        }
    }
}

struct SearchResultsView: View {
    let damus_state: DamusState
    @Binding var search: String
    @State var result: Search? = nil
    @State var results: [NostrEvent] = []
    @State private var relay_result_count: Int = 0
    @State private var is_search_loading: Bool = false
    @State private var relay_search_attempted: Bool = false
    let debouncer: Debouncer = Debouncer(interval: 0.25)

    private func local_ndb_search(_ query: String, limit: Int) -> [NostrEvent] {
        let note_keys = damus_state.ndb.text_search(query: query, limit: limit, order: .newest_first)
        guard !note_keys.isEmpty else { return [] }

        var found = [NostrEvent]()
        var seen = Set<NoteKey>()

        for note_key in note_keys {
            damus_state.ndb.lookup_note_by_key(note_key, borrow: { maybeUnownedNote in
                switch maybeUnownedNote {
                case .none:
                    return
                case .some(let unownedNote):
                    guard !seen.contains(note_key) else { return }
                    found.append(unownedNote.toOwned())
                    seen.insert(note_key)
                }
            })
        }

        return found
    }

    /// NIP-50 relay search to augment local nostrdb results.
    private func nip50_relay_search(_ query: String, limit: Int) async -> ([NostrEvent], Bool) {
        let descriptors = damus_state.nostrNetwork.ourRelayDescriptors
        let nip50Relays = descriptors.compactMap { desc -> RelayURL? in
            guard let nips = damus_state.relay_model_cache.model(withURL: desc.url)?.metadata.supported_nips else {
                return nil
            }
            return nips.contains(50) ? desc.url : nil
        }
        // Prefer relays that explicitly advertise NIP-50; if none do, fall back to all relays so we still attempt.
        let targetRelays = nip50Relays.isEmpty ? descriptors.map { $0.url } : nip50Relays

        guard !targetRelays.isEmpty else { return ([], true) }

        var filter = NostrFilter()
        filter.search = query
        filter.kinds = [.text, .longform, .highlight]
        filter.limit = UInt32(limit)

        let events = await damus_state.nostrNetwork.reader.query(filters: [filter], to: targetRelays)

        let lowered = query.lowercased()
        guard !lowered.isEmpty else { return (events, true) }

        // Client-side guard to keep only items that actually contain the query.
        let filtered = events.filter { $0.content.lowercased().contains(lowered) }
        return (filtered, true)
    }

    private func do_search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await MainActor.run {
                results = []
                relay_result_count = 0
                relay_search_attempted = false
                is_search_loading = false
            }
            return
        }

        let localLimit = 128
        let relayLimit = 100

        await MainActor.run {
            is_search_loading = true
        }

        async let local = local_ndb_search(trimmed, limit: localLimit)
        async let remote = nip50_relay_search(trimmed, limit: relayLimit)

        let (remoteEvents, remoteAttempted) = await remote
        let combined = await [local, remoteEvents].flatMap { $0 }
        let remoteCount = remoteEvents.count

        guard !combined.isEmpty else {
            await MainActor.run {
                results = []
                relay_result_count = 0
                relay_search_attempted = remoteAttempted
                is_search_loading = false
            }
            return
        }

        var seen = Set<NoteId>()
        var deduped: [NostrEvent] = []

        for event in combined {
            guard !seen.contains(event.id) else { continue }
            seen.insert(event.id)
            deduped.append(event)
        }

        let sorted = deduped.sorted { $0.created_at > $1.created_at }
        let capped = Array(sorted.prefix(100))

        await MainActor.run {
            results = capped
            relay_result_count = remoteCount
            relay_search_attempted = remoteAttempted
            is_search_loading = false
        }
    }
    
    var body: some View {
        ScrollView {
            if relay_result_count > 0 {
                // Temporary dev indicator to confirm NIP-50 relay hits; keep if it proves useful.
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.secondary)
                    Text("Relay results included")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            } else if relay_search_attempted {
                // Relay search was sent but yielded no filtered hits.
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(.secondary)
                    Text("Relay search sent")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            InnerSearchResults(
                damus_state: damus_state,
                search: result,
                results: $results,
                is_loading: $is_search_loading,
                relay_result_count: $relay_result_count,
                relay_search_attempted: $relay_search_attempted
            )
                .padding()
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            self.result = search_for_string(profiles: damus_state.profiles, contacts: damus_state.contacts, search: search)
        }
        .onChange(of: search) { new in
            self.result = search_for_string(profiles: damus_state.profiles, contacts: damus_state.contacts, search: search)
        }
        .onChange(of: search) { query in
            debouncer.debounce {
                Task.detached {
                    await do_search(query: query)
                }
            }
        }
    }
}

/*
struct SearchResultsView_Previews: PreviewProvider {
    static var previews: some View {
        SearchResultsView(damus_state: test_damus_state(), s)
    }
}
 */


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

func search_profiles(profiles: Profiles, contacts: Contacts, search: String) -> [Pubkey] {
    // Search by hex pubkey.
    if let pubkey = hex_decode_pubkey(search),
       profiles.lookup_key_by_pubkey(pubkey) != nil
    {
        return [pubkey]
    }

    // Search by npub pubkey.
    if search.starts(with: "npub"),
       let bech32_key = decode_bech32_key(search),
       case Bech32Key.pub(let pk) = bech32_key,
       profiles.lookup_key_by_pubkey(pk) != nil
    {
        return [pk]
    }

    return profiles.search(search, limit: 128).sorted { a, b in
        let aFriendTypePriority = get_friend_type(contacts: contacts, pubkey: a)?.priority ?? 0
        let bFriendTypePriority = get_friend_type(contacts: contacts, pubkey: b)?.priority ?? 0

        if aFriendTypePriority > bFriendTypePriority {
            // `a` should be sorted before `b`
            return true
        } else {
            return false
        }
    }
}
