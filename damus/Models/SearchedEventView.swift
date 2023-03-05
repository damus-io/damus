//
//  SearchedEventView.swift
//  damus
//
//  Created by William Casarin on 2023-03-03.
//

import SwiftUI

enum EventSearchState {
    case searching
    case not_found
    case found(NostrEvent)
}

struct SearchedEventView: View {
    let state: DamusState
    let event_id: String
    @State var search_state: EventSearchState = .searching
    
    var body: some View {
        Group {
            switch search_state {
            case .not_found:
                Text("Event could not be found")
            case .searching:
                Text("Searching...")
            case .found(let ev):
                let thread = ThreadModel(event: ev, damus_state: state)
                let dest = ThreadView(state: state, thread: thread)
                NavigationLink(destination: dest) {
                    EventView(damus: state, event: ev)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            find_event(state: state, evid: event_id, find_from: nil) { ev in
                if let ev {
                    self.search_state = .found(ev)
                } else {
                    self.search_state = .not_found
                }
            }
        }
    }
}

struct SearchedEventView_Previews: PreviewProvider {
    static var previews: some View {
        SearchedEventView(state: test_damus_state(), event_id: "event_id")
    }
}
