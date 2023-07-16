//
//  SearchingEventView.swift
//  damus
//
//  Created by William Casarin on 2023-03-05.
//

import SwiftUI

enum SearchState {
    case searching
    case found(NostrEvent)
    case found_profile(String)
    case not_found
}

enum SearchType {
    case event
    case profile
    case nip05
}

struct SearchingEventView: View {
    let state: DamusState
    let evid: String
    let search_type: SearchType
    
    @State var search_state: SearchState = .searching
    
    var search_name: String {
        switch search_type {
        case .nip05:
            return "Nostr Address"
        case .profile:
            return "Profile"
        case .event:
            return "Note"
        }
    }
    
    func handle_search(_ evid: String) {
        self.search_state = .searching
        
        switch search_type {
        case .nip05:
            if let pk = state.profiles.nip05_pubkey[evid] {
                if state.profiles.lookup(id: pk) != nil {
                    self.search_state = .found_profile(pk)
                }
            } else {
                Task {
                    guard let nip05 = NIP05.parse(evid) else {
                        self.search_state = .not_found
                        return
                    }
                    guard let nip05_resp = await fetch_nip05(nip05: nip05) else {
                        DispatchQueue.main.async {
                            self.search_state = .not_found
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        guard let pk = nip05_resp.names[nip05.username] else {
                            self.search_state = .not_found
                            return
                        }
                        
                        self.search_state = .found_profile(pk)
                    }
                }
            }
            
        case .event:
            find_event(state: state, query: .event(evid: evid)) { res in
                guard case .event(let ev) = res else {
                    self.search_state = .not_found
                    return
                }
                self.search_state = .found(ev)
            }
        case .profile:
            find_event(state: state, query: .profile(pubkey: evid)) { res in
                guard case .profile(_, let ev) = res else {
                    self.search_state = .not_found
                    return
                }
                self.search_state = .found_profile(ev.pubkey)
            }
        }
    }
    
    var body: some View {
        Group {
            switch search_state {
            case .searching:
                HStack(spacing: 10) {
                    Text("Looking for \(search_name)...", comment: "Label that appears when searching for note or profile")
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            case .found(let ev):
                NavigationLink(value: Route.Thread(thread: ThreadModel(event: ev, damus_state: state))) {
                    EventView(damus: state, event: ev)
                }
                .buttonStyle(PlainButtonStyle())
            case .found_profile(let pk):
                NavigationLink(value: Route.ProfileByKey(pubkey: pk)) {
                    FollowUserView(target: .pubkey(pk), damus_state: state)
                }
                .buttonStyle(PlainButtonStyle())
            case .not_found:
                Text("\(search_name) not found", comment: "When a note or profile is not found when searching for it via its note id")
            }
        }
        .onChange(of: evid, debounceTime: 0.5) { evid in
            handle_search(evid)
        }
        .onAppear {
            handle_search(evid)
        }
    }
}

struct SearchingEventView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        SearchingEventView(state: state, evid: test_event.id, search_type: .event)
    }
}
