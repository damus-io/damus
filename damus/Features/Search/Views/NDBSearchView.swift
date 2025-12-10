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
    @Binding var is_loading: Bool
    @Binding var relay_result_count: Int
    @Binding var relay_search_attempted: Bool

    var relayBadge: some View {
        Group {
            if relay_result_count > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.secondary)
                    Text("Relay results included")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if relay_search_attempted {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(.secondary)
                    Text("Relay search sent")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    var body: some View {
        ScrollView {
            if is_loading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
                .padding()
            }

            relayBadge

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
