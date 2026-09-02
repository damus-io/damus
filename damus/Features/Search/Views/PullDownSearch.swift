//
//  PullDownSearch.swift
//  damus
//
//  Created by William Casarin on 2023-12-03.
//

import Foundation

import SwiftUI

struct PullDownSearchView: View {
    @State private var search_text = ""
    @State private var results: [NostrEvent] = []
    @State private var is_active: Bool = false
    let debouncer: Debouncer = Debouncer(interval: 0.25)
    let state: DamusState
    let on_cancel: () -> Void
    
    func do_search(query: String) async {
        guard let notes = await search_notes(state: state, query: query) else { return }

        Task { @MainActor [notes] in
            results = notes
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField(NSLocalizedString("Search", comment: "Title of the text field for searching."), text: $search_text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: search_text) { query in
                        debouncer.debounce {
                            Task.detached {
                                await do_search(query: query)
                            }
                        }
                    }
                    .onTapGesture {
                        is_active = true
                    }

                if is_active {
                    Button(action: {
                        search_text = ""
                        results = []
                        end_editing()
                        on_cancel()
                    }, label: {
                        Text("Cancel", comment: "Button to cancel out of search text entry mode.")
                    })
                }
            }
            .padding()

            if results.count > 0 {
                HStack {
                    Image("search")
                    Text("Top hits", comment: "A label indicating that the notes being displayed below it are all top note search results")
                    Spacer()
                }
                .padding(.horizontal)
                .foregroundColor(.secondary)

                ForEach(results, id: \.self) { note in
                    EventView(damus: state, event: note)
                        .onTapGesture {
                            let event = note.get_inner_event(cache: state.events) ?? note
                            let thread = ThreadModel(event: event, damus_state: state)
                            state.nav.push(route: Route.Thread(thread: thread))
                        }
                }
                
                HStack {
                    Image("notes.fill")
                    Text("Notes", comment: "A label indicating that the notes being displayed below it are from a timeline, not search results")
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal)
            } else if results.count == 0 && !search_text.isEmpty {
                HStack {
                    Image("search")
                    Text("No results", comment: "A label indicating that note search resulted in no results")
                    Spacer()
                }
                .padding(.horizontal)
                .foregroundColor(.secondary)
            }
        }
    }
}

struct PullDownSearchView_Previews: PreviewProvider {
    static var previews: some View {
        PullDownSearchView(state: test_damus_state, on_cancel: {})
    }
}
