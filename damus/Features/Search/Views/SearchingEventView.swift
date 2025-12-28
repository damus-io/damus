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
    case found_profile(Pubkey)
    case not_found
}

enum SearchType: Equatable {
    case event(NoteId, relays: [RelayURL])
    case profile(Pubkey, relays: [RelayURL])
    case nip05(String)
    case naddr(NAddr)
}

@MainActor
struct SearchingEventView: View {
    let state: DamusState
    let search_type: SearchType
    
    @State var search_state: SearchState = .searching
    
    var search_name: String {
        switch search_type {
        case .nip05:
            return "Nostr Address"
        case .profile(_, _):
            return "Profile"
        case .event(_, _):
            return "Note"
        case .naddr:
            return "Naddr"
        }
    }
    
    func handle_search(search: SearchType) {
        self.search_state = .searching
        
        switch search {
        case .nip05(let nip05):
            if let pk = state.profiles.nip05_pubkey[nip05] {
                if (try? state.profiles.lookup_key_by_pubkey(pk)) != nil {
                    self.search_state = .found_profile(pk)
                }
            } else {
                Task {
                    guard let nip05 = NIP05.parse(nip05) else {
                        Task { @MainActor in
                            self.search_state = .not_found
                        }
                        return
                    }
                    guard let nip05_resp = await fetch_nip05(nip05: nip05) else {
                        Task { @MainActor in
                            self.search_state = .not_found
                        }
                        return
                    }
                    
                    Task { @MainActor in
                        guard let pk = nip05_resp.names[nip05.username] else {
                            self.search_state = .not_found
                            return
                        }
                        
                        self.search_state = .found_profile(pk)
                    }
                }
            }
            
        case .event(let note_id, let relays):
            Task {
                let targetRelays = relays.isEmpty ? nil : relays
                let res = await state.nostrNetwork.reader.findEvent(query: .event(evid: note_id, find_from: targetRelays))
                guard case .event(let ev) = res else {
                    self.search_state = .not_found
                    return
                }
                self.search_state = .found(ev)
            }
        case .profile(let pubkey, let relays):
            Task {
                let targetRelays = relays.isEmpty ? nil : relays
                let res = await state.nostrNetwork.reader.findEvent(query: .profile(pubkey: pubkey, find_from: targetRelays))
                guard case .profile(let pubkey) = res else {
                    self.search_state = .not_found
                    return
                }
                self.search_state = .found_profile(pubkey)
            }
        case .naddr(let naddr):
            Task {
                let targetRelays = naddr.relays.isEmpty ? nil : naddr.relays
                let res = await state.nostrNetwork.reader.lookup(naddr: naddr, to: targetRelays)
                guard let res = res else {
                    self.search_state = .not_found
                    return
                }
                self.search_state = .found(res)
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
        .onChange(of: search_type, debounceTime: 0.5) { stype in
            handle_search(search: stype)
        }
        .onAppear {
            handle_search(search: search_type)
        }
    }
}

struct SearchingEventView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        SearchingEventView(state: state, search_type: .event(test_note.id, relays: []))
    }
}
