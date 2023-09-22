//
//  SearchResultsView.swift
//  damus
//
//  Created by William Casarin on 2022-06-06.
//

import SwiftUI

struct MultiSearch {
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
    
    var id: String {
        switch self {
        case .profiles: return "profiles"
        case .hashtag: return "hashtag"
        case .profile: return "profile"
        case .note: return "note"
        case .nip05: return "nip05"
        case .hex: return "hex"
        case .multi: return "multi"
        }
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
            Text("Search hashtag: #\(ht)", comment: "Navigation link to search hashtag.")
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

            case .multi(let multi):
                VStack {
                    HashtagSearch(multi.hashtag)
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
    
    var body: some View {
        ScrollView {
            InnerSearchResults(damus_state: damus_state, search: result)
                .padding()
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            let txn = NdbTxn.init(ndb: damus_state.ndb)
            self.result = search_for_string(profiles: damus_state.profiles, search: search, txn: txn)
        }
        .onChange(of: search) { new in
            let txn = NdbTxn.init(ndb: damus_state.ndb)
            self.result = search_for_string(profiles: damus_state.profiles, search: search, txn: txn)
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


func search_for_string<Y>(profiles: Profiles, search new: String, txn: NdbTxn<Y>) -> Search? {
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
    
    if let new = hex_decode_id(new) {
        return .hex(new)
    }

    if new.starts(with: "npub") {
        if let decoded = bech32_pubkey_decode(new) {
            return .profile(decoded)
        }
    }
    
    if new.starts(with: "note"), let decoded = try? bech32_decode(new) {
        return .note(NoteId(decoded.data))
    }
    
    let multisearch = MultiSearch(hashtag: make_hashtagable(new), profiles: search_profiles(profiles: profiles, search: new, txn: txn))
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

func search_profiles<Y>(profiles: Profiles, search: String, txn: NdbTxn<Y>) -> [Pubkey] {
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

    let new = search.lowercased()

    return profiles.search(search, limit: 10, txn: txn)
}

