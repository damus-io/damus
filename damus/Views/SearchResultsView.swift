//
//  SearchResultsView.swift
//  damus
//
//  Created by William Casarin on 2022-06-06.
//

import SwiftUI

enum Search {
    case profiles([(String, Profile)])
    case hashtag(String)
    case profile(String)
    case note(String)
    case hex(String)
}

struct SearchResultsView: View {
    let damus_state: DamusState
    @Binding var search: String
    
    @State var result: Search? = nil
    
    func ProfileSearchResult(pk: String, res: Profile) -> some View {
        FollowUserView(target: .pubkey(pk), damus_state: damus_state)
    }
    
    var MainContent: some View {
        ScrollView {
            Group {
                switch result {
                case .profiles(let results):
                    LazyVStack {
                        ForEach(results, id: \.0) { prof in
                            ProfileSearchResult(pk: prof.0, res: prof.1)
                        }
                    }
                case .hashtag(let ht):
                    let search_model = SearchModel(contacts: damus_state.contacts, pool: damus_state.pool, search: .filter_hashtag([ht]))
                    let dst = SearchView(appstate: damus_state, search: search_model)
                    NavigationLink(destination: dst) {
                        Text("Search hashtag: #\(ht)", comment: "Navigation link to search hashtag.")
                    }
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
                case .none:
                    Text("none", comment: "No search results.")
                }
            }
            .padding()
        }
    }
    
    var body: some View {
        MainContent
            .frame(maxHeight: .infinity)
            .onAppear {
                self.result = search_changed(profiles: damus_state.profiles, search)
            }
            .onChange(of: search) { new in
                self.result = search_changed(profiles: damus_state.profiles, new)
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


func search_changed(profiles: Profiles, _ new: String) -> Search? {
    guard new.count != 0 else {
        return nil
    }
    
    if new.first! == "#" {
        let ht = String(new.dropFirst())
        return .hashtag(ht)
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
    
    let profs = profiles.profiles.enumerated()
    let results: [(String, Profile)] = profs.reduce(into: []) { acc, els in
        let pk = els.element.key
        let prof = els.element.value.profile
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
            acc.append((pk, prof))
        }
    }
        
    return .profiles(results)
}
