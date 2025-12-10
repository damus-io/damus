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
    let searchQuery: String

    var highlightTerms: [String] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        var terms: [String] = []

        for part in parts {
            let term = String(part)
            let strippedHashtag = term.hasPrefix("#") ? String(term.dropFirst()) : nil

            if let stripped = strippedHashtag, !stripped.isEmpty {
                terms.append(stripped)
            }

            if !term.isEmpty {
                terms.append(term)
            }
        }

        var deduped: [String] = []
        var seen = Set<String>()
        for term in terms.map({ $0.lowercased() }) {
            if seen.insert(term).inserted {
                deduped.append(term)
            }
        }

        return deduped
    }
    
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

                if !highlightTerms.isEmpty {
                    Text("Search: \(searchQuery)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                LazyVStack {
                    ForEach(results, id: \.self) { note in
                        EventView(damus: damus_state, event: note, options: [.truncate_content], highlightTerms: highlightTerms)
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
