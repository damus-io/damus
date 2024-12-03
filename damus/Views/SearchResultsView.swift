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
        return NavigationLink(value: Route.NDBSearch(results: $results)) {
            HStack {
                Text(txt)
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
    let debouncer: Debouncer = Debouncer(interval: 0.25)
    
    func do_search(query: String) {
        let limit = 128
        var note_keys = damus_state.ndb.text_search(query: query, limit: limit, order: .newest_first)
        var res = [NostrEvent]()
        // TODO: fix duplicate results from search
        var keyset = Set<NoteKey>()

        // try reverse because newest first is a bit buggy on partial searches
        if note_keys.count == 0 {
            // don't touch existing results if there are no new ones
            return
        }

        do {
            guard let txn = NdbTxn(ndb: damus_state.ndb) else { return }
            for note_key in note_keys {
                guard let note = damus_state.ndb.lookup_note_by_key_with_txn(note_key, txn: txn) else {
                    continue
                }

                if !keyset.contains(note_key) {
                    let owned_note = note.to_owned()
                    res.append(owned_note)
                    keyset.insert(note_key)
                }
            }
        }

        let res_ = res

        Task { @MainActor [res_] in
            results = res_
        }
    }
    
    var body: some View {
        ScrollView {
            InnerSearchResults(damus_state: damus_state, search: result, results: $results)
                .padding()
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            guard let txn = NdbTxn.init(ndb: damus_state.ndb) else { return }
            self.result = search_for_string(profiles: damus_state.profiles, contacts: damus_state.contacts, search: search, txn: txn)
        }
        .onChange(of: search) { new in
            guard let txn = NdbTxn.init(ndb: damus_state.ndb) else { return }
            self.result = search_for_string(profiles: damus_state.profiles, contacts: damus_state.contacts, search: search, txn: txn)
        }
        .onChange(of: search) { query in
            debouncer.debounce {
                Task.detached {
                    do_search(query: query)
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


func search_for_string<Y>(profiles: Profiles, contacts: Contacts, search new: String, txn: NdbTxn<Y>) -> Search? {
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
    
    let multisearch = MultiSearch(text: new, hashtag: make_hashtagable(searchQuery), profiles: search_profiles(profiles: profiles, contacts: contacts, search: new, txn: txn))
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

func search_profiles<Y>(profiles: Profiles, contacts: Contacts, search: String, txn: NdbTxn<Y>) -> [Pubkey] {
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

    return profiles.search(search, limit: 128, txn: txn).sorted { a, b in
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

