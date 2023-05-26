//
//  SearchResultsView.swift
//  damus
//
//  Created by William Casarin on 2022-06-06.
//

import SwiftUI

struct MultiSearch {
    let hashtag: String
    let profiles: [SearchedUser]
}

enum Search: Identifiable {
    case profiles([SearchedUser])
    case hashtag(String)
    case profile(String)
    case note(String)
    case nip05(String)
    case hex(String)
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
    
    func ProfileSearchResult(pk: String) -> some View {
        FollowUserView(target: .pubkey(pk), damus_state: damus_state)
    }
    
    func HashtagSearch(_ ht: String) -> some View {
        let search_model = SearchModel(state: damus_state, search: .filter_hashtag([ht]))
        let dst = SearchView(appstate: damus_state, search: search_model)
        return NavigationLink(destination: dst) {
            Text("Search hashtag: #\(ht)", comment: "Navigation link to search hashtag.")
        }
    }
    
    func ProfilesSearch(_ results: [SearchedUser]) -> some View {
        return LazyVStack {
            ForEach(results) { prof in
                ProfileSearchResult(pk: prof.pubkey)
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
                SearchingEventView(state: damus_state, evid: addr, search_type: .nip05)
                
            case .profile(let prof):
                let decoded = try? bech32_decode(prof)
                let hex = hex_encode(decoded!.data)
                
                SearchingEventView(state: damus_state, evid: hex, search_type: .profile)
            case .hex(let h):
                //let prof_view = ProfileView(damus_state: damus_state, pubkey: h)
                //let ev_view = ThreadView(damus: damus_state, event_id: h)
                
                VStack(spacing: 10) {
                    SearchingEventView(state: damus_state, evid: h, search_type: .event)
                    
                    SearchingEventView(state: damus_state, evid: h, search_type: .profile)
                }
                
            case .note(let nid):
                let decoded = try? bech32_decode(nid)
                let hex = hex_encode(decoded!.data)
                
                SearchingEventView(state: damus_state, evid: hex, search_type: .event)
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
            self.result = search_for_string(profiles: damus_state.profiles, search)
        }
        .onChange(of: search) { new in
            self.result = search_for_string(profiles: damus_state.profiles, new)
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


func search_for_string(profiles: Profiles, _ new: String) -> Search? {
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
    
    if hex_decode(new) != nil, new.count == 64 {
        return .hex(new)
    }
    
    if new.starts(with: "npub") {
        if (try? bech32_decode(new)) != nil {
            return .profile(new)
        }
    }
    
    if new.starts(with: "note") {
        if (try? bech32_decode(new)) != nil {
            return .note(new)
        }
    }
    
    let multisearch = MultiSearch(hashtag: make_hashtagable(new), profiles: search_profiles(profiles: profiles, search: new))
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

func search_profiles(profiles: Profiles, search: String) -> [SearchedUser] {
    let new = search.lowercased()
    return profiles.enumerated().reduce(into: []) { acc, els in
        let pk = els.element.key
        let prof = els.element.value.profile
        
        if let searched = profile_search_matches(profiles: profiles, profile: prof, pubkey: pk, search: new) {
            acc.append(searched)
        }
    }
}


func profile_search_matches(profiles: Profiles, profile prof: Profile, pubkey pk: String, search new: String) -> SearchedUser? {
    let lowname = prof.name.map { $0.lowercased() }
    let lownip05 = profiles.is_validated(pk).map { $0.host.lowercased() }
    let lowdisp = prof.display_name.map { $0.lowercased() }
    let ok = new.count == 1 ?
    ((lowname?.starts(with: new) ?? false) ||
     (lownip05?.starts(with: new) ?? false) ||
     (lowdisp?.starts(with: new) ?? false)) : (pk.starts(with: new) || String(new.dropFirst()) == pk
        || lowname?.contains(new) ?? false
        || lownip05?.contains(new) ?? false
        || lowdisp?.contains(new) ?? false)
    
    if ok {
        return SearchedUser(petname: nil, profile: prof, pubkey: pk)
    }
    
    return nil
}
