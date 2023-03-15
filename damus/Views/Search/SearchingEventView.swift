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
}

struct SearchingEventView: View {
    let state: DamusState
    let evid: String
    let search_type: SearchType
    @State var search_state: SearchState = .searching
    
    var bech32_evid: String {
        guard let bytes = hex_decode(evid) else {
            return evid
        }
        let noteid = bech32_encode(hrp: "note", bytes)
        return abbrev_pubkey(noteid)
    }
    
    var search_name: String {
        switch search_type {
        case .profile:
            return "profile"
        case .event:
            return "note"
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
                NavigationLink(destination: ThreadView(state: state, thread: ThreadModel(event: ev, damus_state: state))) {
                    
                    EventView(damus: state, event: ev)
                }
                .buttonStyle(PlainButtonStyle())
            case .found_profile(let pk):
                NavigationLink(destination: ProfileView(damus_state: state, pubkey: pk)) {
                    
                    FollowUserView(target: .pubkey(pk), damus_state: state)
                }
                .buttonStyle(PlainButtonStyle())
            case .not_found:
                Text("\(search_name.capitalized) not found", comment: "When a note or profile is not found when searching for it via its note id")
            }
        }
        .onAppear {
            
            switch search_type {
            case .event:
                if let ev = state.events.lookup(evid) {
                    self.search_state = .found(ev)
                    return
                }
                find_event(state: state, evid: evid, search_type: search_type, find_from: nil) { ev in
                    if let ev {
                        self.search_state = .found(ev)
                    } else {
                        self.search_state = .not_found
                    }
                }
            case .profile:
                find_event(state: state, evid: evid, search_type: search_type, find_from: nil) { _ in
                    if state.profiles.lookup(id: evid) != nil {
                        self.search_state = .found_profile(evid)
                        return
                    } else {
                        self.search_state = .not_found
                    }
                }
            }
        }
    }
}

struct SearchingEventView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        SearchingEventView(state: state, evid: test_event.id, search_type: .event)
    }
}


enum EventSearchState {
    case searching
    case not_found
    case found(NostrEvent)
    case found_profile(String)
}

