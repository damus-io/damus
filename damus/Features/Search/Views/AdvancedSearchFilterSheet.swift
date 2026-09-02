//
//  AdvancedSearchFilterSheet.swift
//  damus
//
//  Created by William Casarin on 2026-09-02.
//

import SwiftUI

/// The discoverable front-end to ``AdvancedSearchQueryDSL``: every filter the
/// query language can express, as controls.
///
/// The sheet edits an ``AdvancedSearchQuery`` binding directly rather than
/// building up a draft, so it and the query text field are the same state and
/// cannot drift. The two text fields are the only exception — see
/// ``keywordsText`` for why they need their own storage and why that storage is
/// one-way.
struct AdvancedSearchFilterSheet: View {
    let damus_state: DamusState
    @Binding var query: AdvancedSearchQuery

    /// Called when Search is tapped, after the fields have been committed.
    let onSearch: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// The keyword field's text.
    ///
    /// Seeded from the query once and then only ever written *to* the query, never
    /// read back. Deriving the text from `query.keywords` on every render instead
    /// would rebuild it from the split words and eat the trailing space, making
    /// multi-word entry impossible. The sheet is modal, so nothing else can change
    /// the query underneath it while it is open.
    @State private var keywordsText: String

    /// The exact-phrase field's text. Same one-way rule as ``keywordsText``.
    @State private var phraseText: String

    @State private var authorSearch: String = ""

    init(damus_state: DamusState, query: Binding<AdvancedSearchQuery>, onSearch: @escaping () -> Void) {
        self.damus_state = damus_state
        self._query = query
        self.onSearch = onSearch
        self._keywordsText = State(initialValue: query.wrappedValue.keywords.joined(separator: " "))
        self._phraseText = State(initialValue: Self.phraseFieldText(for: query.wrappedValue.phrases))
    }

    // MARK: - Text fields

    /// How several phrases read in one field: each quoted, the way they would be
    /// typed into the search field.
    ///
    /// A single phrase is left unquoted, because that is what the field is *for* —
    /// making quoting discoverable without demanding it.
    static func phraseFieldText(for phrases: [String]) -> String {
        guard phrases.count > 1 else { return phrases.first ?? "" }
        return phrases.map({ "\"\($0)\"" }).joined(separator: " ")
    }

    /// The inverse: quoted runs become separate phrases, and anything unquoted is
    /// one phrase in its entirety. Parsed with the DSL's own tokenizer so the field
    /// and the query language agree about what a quote does.
    static func phrases(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("\"") else { return trimmed.isEmpty ? [] : [trimmed] }
        return AdvancedSearchQueryDSL.tokenize(trimmed).filter(\.quoted).map(\.text)
    }

    private func commitFields() {
        query.keywords = keywordsText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        query.phrases = Self.phrases(from: phraseText)
    }

    // MARK: - Authors

    private var authorResults: [Pubkey] {
        let search = authorSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return [] }
        return search_profiles(profiles: damus_state.profiles, contacts: damus_state.contacts, search: search)
            .filter({ !query.authors.contains($0) })
            .prefix(20)
            .map({ $0 })
    }

    /// True once adding another author would drop the query off nostrdb's fast
    /// author-kind plan.
    ///
    /// The picker refuses rather than truncating: silently dropping somebody the
    /// user chose would be worse than the slow path, and silently *taking* the slow
    /// path is what the cap exists to prevent.
    private var authorsAreFull: Bool { query.authors.count >= query.authorLimit }

    private var authorSection: some View {
        Section {
            ForEach(query.authors, id: \.self) { pubkey in
                HStack {
                    UserViewRow(damus_state: damus_state, pubkey: pubkey)
                    Spacer()
                    Button(action: { query.authors.removeAll(where: { $0 == pubkey }) }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            if authorsAreFull {
                Text("You can search up to \(query.authorLimit) authors at once.", comment: "Explanation that the number of authors an advanced search can cover is limited.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                TextField(NSLocalizedString("Add an author", comment: "Placeholder for the field used to add an author to an advanced search."),
                          text: $authorSearch)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)

                ForEach(authorResults, id: \.self) { pubkey in
                    Button(action: {
                        query.authors.append(pubkey)
                        authorSearch = ""
                    }) {
                        HStack {
                            UserViewRow(damus_state: damus_state, pubkey: pubkey)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Authors", comment: "Section header for the authors an advanced search covers.")
        }
    }

    // MARK: - Dates

    private var datePreset: AdvancedSearchDatePreset {
        AdvancedSearchDatePreset.matching(query)
    }

    private var dateSection: some View {
        Section {
            Picker(selection: Binding(get: { datePreset },
                                      set: { query = $0.applied(to: query) })) {
                ForEach(AdvancedSearchDatePreset.selectable) { preset in
                    Text(preset.label).tag(preset)
                }
                if datePreset == .custom {
                    Text(AdvancedSearchDatePreset.custom.label).tag(AdvancedSearchDatePreset.custom)
                }
            } label: {
                Text("Date range", comment: "Label for the date range of an advanced search.")
            }

            DatePicker(selection: Binding(get: { query.since ?? Date() },
                                          set: { query.since = $0 }),
                       displayedComponents: [.date]) {
                Toggle(isOn: Binding(get: { query.since != nil },
                                     set: { query.since = $0 ? Date() : nil })) {
                    Text("From", comment: "Label for the earliest date an advanced search covers.")
                }
            }
            .disabled(query.since == nil)

            DatePicker(selection: Binding(get: { query.until ?? Date() },
                                          // Both bounds are inclusive, so `since == until`
                                          // is a valid one-second window and only an
                                          // inverted pair is empty. Clamp rather than
                                          // letting the user build one that cannot match.
                                          set: { query.until = max($0, query.since ?? $0) }),
                       in: (query.since ?? Date.distantPast)...,
                       displayedComponents: [.date]) {
                Toggle(isOn: Binding(get: { query.until != nil },
                                     set: { query.until = $0 ? Date() : nil })) {
                    Text("To", comment: "Label for the latest date an advanced search covers.")
                }
            }
            .disabled(query.until == nil)
        } header: {
            Text("When", comment: "Section header for the date range of an advanced search.")
        }
    }

    // MARK: - Content

    private func kindToggle(_ kind: NostrKind, _ label: String) -> some View {
        Toggle(isOn: Binding(get: { query.kinds.contains(kind) },
                             set: { on in
                                 var kinds = query.kinds
                                 if on { kinds.insert(kind) } else { kinds.remove(kind) }
                                 // Assigning an empty set restores the default pair, so
                                 // turning both off cannot produce a query that searches
                                 // nothing.
                                 query.kinds = kinds
                             })) {
            Text(label)
        }
    }

    private var contentSection: some View {
        Section {
            TextField(NSLocalizedString("Words", comment: "Placeholder for the keywords field of an advanced search."),
                      text: $keywordsText)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .onChange(of: keywordsText) { _ in commitFields() }

            TextField(NSLocalizedString("Exact phrase", comment: "Placeholder for the exact-phrase field of an advanced search."),
                      text: $phraseText)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .onChange(of: phraseText) { _ in commitFields() }
        } header: {
            Text("What", comment: "Section header for the terms an advanced search looks for.")
        } footer: {
            Text("Every word and phrase must appear in a note for it to match.", comment: "Explanation that advanced search terms are combined with AND.")
        }
    }

    private var typeSection: some View {
        Section {
            kindToggle(.text, NSLocalizedString("Notes", comment: "Toggle for including short text notes in an advanced search."))
            kindToggle(.longform, NSLocalizedString("Long-form", comment: "Toggle for including long-form articles in an advanced search."))
        } header: {
            Text("Content type", comment: "Section header for which kinds of note an advanced search covers.")
        } footer: {
            Text("Only notes and long-form posts are indexed for search.", comment: "Explanation that only two note kinds can be searched.")
        }
    }

    private var sortSection: some View {
        Section {
            Picker(selection: $query.order) {
                Text("Newest first", comment: "Search result ordering, newest note first.").tag(NdbSearchOrder.newest_first)
                Text("Oldest first", comment: "Search result ordering, oldest note first.").tag(NdbSearchOrder.oldest_first)
            } label: {
                Text("Sort", comment: "Label for the ordering of search results.")
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            Form {
                contentSection
                authorSection
                dateSection
                typeSection
                sortSection
            }
            .navigationTitle(NSLocalizedString("Search filters", comment: "Title of the advanced search filter sheet."))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        query = AdvancedSearchQuery()
                        keywordsText = ""
                        phraseText = ""
                        authorSearch = ""
                    }) {
                        Text("Reset", comment: "Button clearing every advanced search filter.")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        commitFields()
                        onSearch()
                        dismiss()
                    }) {
                        Text("Search", comment: "Button running the advanced search the filter sheet describes.")
                            .bold()
                    }
                }
            }
        }
    }
}

struct AdvancedSearchFilterSheet_Previews: PreviewProvider {
    struct Container: View {
        @State var query = AdvancedSearchQuery(keywords: ["fox"], phrases: ["jumped over"])
        var body: some View {
            AdvancedSearchFilterSheet(damus_state: test_damus_state, query: $query, onSearch: {})
        }
    }

    static var previews: some View {
        Container()
    }
}
