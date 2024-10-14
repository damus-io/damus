//
//  NDBSearchView.swift
//  damus
//
//  Created by eric on 9/9/24.
//

import SwiftUI

struct NDBSearchView: View {
    
    let damus_state: DamusState
    @Binding var results: [NostrEvent]
    
    var body: some View {
        ScrollView {
            if results.count > 0 {
                HStack {
                    Spacer()
                    Image("search")
                    Text("Top hits", comment: "A label indicating that the notes being displayed below it are all top note search results")
                    Spacer()
                }
                .padding()
                .foregroundColor(.secondary)

                LazyVStack {
                    ForEach(results, id: \.self) { note in
                        EventView(damus: damus_state, event: note, options: [.truncate_content])
                            .onTapGesture {
                                let event = note.get_inner_event(cache: damus_state.events) ?? note
                                let thread = ThreadModel(event: event, damus_state: damus_state)
                                damus_state.nav.push(route: Route.Thread(thread: thread))
                            }
                            .padding(.horizontal)

                        ThiccDivider()
                    }
                }

            } else if results.count == 0 {
                HStack {
                    Spacer()
                    Image("search")
                    Text("No results", comment: "A label indicating that note search resulted in no results")
                    Spacer()
                }
                .padding()
                .foregroundColor(.secondary)
            }
        }
    }
}
