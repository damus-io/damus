//
//  SearchContentView.swift
//  damus
//
//  Created by eric on 3/14/24.
//

import SwiftUI

struct SearchContentView: View {
    let state: DamusState
    @Binding var search_text: String
    @Binding var results: [NostrEvent]
    
    var event_options: EventViewOptions {
        if self.state.settings.truncate_timeline_text {
            return [.wide, .truncate_content]
        }
        return [.wide]
    }
    
    var body: some View {
        ScrollView {
            if results.count > 0 {
                HStack {
                    Image("search")
                    Text(NSLocalizedString("Top hits", comment: "A label indicating that the notes being displayed below it are all top note search results"))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding()
                
                ForEach(results, id: \.self) { note in
                    EventView(damus: state, event: note, options: event_options)
                        .onTapGesture {
                            let event = note.get_inner_event(cache: state.events) ?? note
                            let thread = ThreadModel(event: event, damus_state: state)
                            state.nav.push(route: Route.Thread(thread: thread))
                        }
                        .padding(.top, 7)
                    
                    ThiccDivider()
                        .padding([.top], 7)
                }
                
            } else if results.count == 0 && !search_text.isEmpty {
                VStack(alignment: .center) {
                    HStack {
                        Image("search")
                        Text(NSLocalizedString("No results", comment: "A label indicating that note search resulted in no results"))
                    }
                }
                .padding(.vertical)
                .foregroundColor(.secondary)
            } else if search_text.isEmpty {
                VStack(alignment: .center) {
                    Text(NSLocalizedString("Try searching for keywords", comment: "A label suggesting the user search for keywords"))
                }
                .padding(.vertical)
                .foregroundColor(.secondary)
            }
        }
        .onChange(of: search_text) { _ in
            if search_text.isEmpty {
                results = [NostrEvent]()
            }
        }
        .onChange(of: results) { _ in
            if search_text.isEmpty {
                results = [NostrEvent]()
            }
        }
    }
}
