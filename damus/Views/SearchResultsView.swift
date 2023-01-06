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
                    let search_model = SearchModel(pool: damus_state.pool, search: .filter_hashtag([ht]))
                    let dst = SearchView(appstate: damus_state, search: search_model)
                    NavigationLink(destination: dst) {
                        Text("Search hashtag: #\(ht)")
                    }
                case .profile(let prof):
                    let decoded = try? bech32_decode(prof)
                    let hex = hex_encode(decoded!.data)
                    let prof_model = ProfileModel(pubkey: hex, damus: damus_state)
                    let f = FollowersModel(damus_state: damus_state, target: prof)
                    let dst = ProfileView(damus_state: damus_state, profile: prof_model, followers: f)
                    NavigationLink(destination: dst) {
                        Text("Goto profile \(prof)")
                    }
                case .hex(let h):
                    let prof_model = ProfileModel(pubkey: h, damus: damus_state)
                    let f = FollowersModel(damus_state: damus_state, target: h)
                    let prof_view = ProfileView(damus_state: damus_state, profile: prof_model, followers: f)
                    let ev_view = BuildThreadV2View(
                        damus: damus_state,
                        event_id: h
                    )

                    VStack(spacing: 50) {
                        NavigationLink(destination: prof_view) {
                            Text("Goto profile \(h)")
                        }
                        NavigationLink(destination: ev_view) {
                            Text("Goto post \(h)")
                        }
                    }
                case .note(let nid):
                    let decoded = try? bech32_decode(nid)
                    let hex = hex_encode(decoded!.data)
                    let ev_view = BuildThreadV2View(
                        damus: damus_state,
                        event_id: hex
                    )
                    NavigationLink(destination: ev_view) {
                        Text("Goto post \(nid)")
                    }
                case .none:
                    Text("none")
                }
            }.padding(.horizontal)
        }
    }
    
    func search_changed(_ new: String) {
        guard new.count != 0 else {
            return
        }
        
        if new.first! == "#" {
            let ht = String(new.dropFirst())
            self.result = .hashtag(ht)
            return
        }
        
        if let _ = hex_decode(new), new.count == 64 {
            self.result = .hex(new)
            return
        }
        
        if new.starts(with: "npub") {
            if let _ = try? bech32_decode(new) {
                self.result = .profile(new)
                return
            }
        }
        
        if new.starts(with: "note") {
            if let _ = try? bech32_decode(new) {
                self.result = .note(new)
                return
            }
        }
        
        let profs = damus_state.profiles.profiles.enumerated()
        let results: [(String, Profile)] = profs.reduce(into: []) { acc, els in
            let pk = els.element.key
            let prof = els.element.value.profile
            let lowname = prof.name.map { $0.lowercased() }
            let lownip05 = damus_state.profiles.is_validated(pk).map { $0.host.lowercased() }
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
            
        self.result = .profiles(results)
    }
    
    var body: some View {
        MainContent
            .frame(maxHeight: .infinity)
            .onAppear {
                search_changed(search)
            }
            .onChange(of: search) { new in
                search_changed(new)
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
