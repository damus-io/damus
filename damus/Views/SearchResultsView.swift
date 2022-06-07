//
//  SearchResultsView.swift
//  damus
//
//  Created by William Casarin on 2022-06-06.
//

import SwiftUI

struct SearchResultsView: View {
    let damus_state: DamusState
    @Binding var search: String
    @State var results: [(String, Profile)] = []
    
    func ProfileSearchResult(pk: String, res: Profile) -> some View {
        FollowUserView(target: .pubkey(pk), damus_state: damus_state)
    }
    
    var MainContent: some View {
        ScrollView {
            LazyVStack {
                ForEach(results, id: \.0) { prof in
                    ProfileSearchResult(pk: prof.0, res: prof.1)
                }
            }
        }
    }
    
    func search_changed(_ new: String) {
        let profs = damus_state.profiles.profiles.enumerated()
        self.results = profs.reduce(into: []) { acc, els in
            let pk = els.element.key
            let prof = els.element.value.profile
            let lowname = prof.name.map { $0.lowercased() }
            let lowdisp = prof.display_name.map { $0.lowercased() }
            let ok = new.count == 1 ?
            ((lowname?.starts(with: new) ?? false) ||
             (lowdisp?.starts(with: new) ?? false)) : (pk.starts(with: new) || String(new.dropFirst()) == pk
                || lowname?.contains(new) ?? false
                || lowdisp?.contains(new) ?? false)
            if ok {
                acc.append((pk, prof))
            }
        }
            
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
