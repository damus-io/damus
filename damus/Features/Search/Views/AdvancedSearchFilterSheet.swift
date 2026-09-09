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

    /// Whether the keyword field takes the keyboard as the sheet appears.
    ///
    /// True only for the entry points that arrive with nothing but a *scope*
    /// filled in — the profile and hashtag buttons — where the words are the
    /// entire reason the sheet is open and the first tap is always into that
    /// field. It stays false where the sheet is opened over terms somebody
    /// already typed (the explore pane's filter button, the results screen's),
    /// because a keyboard rising over an existing query hides the filters they
    /// came to look at.
    let autofocusKeywords: Bool

    @Environment(\.dismiss) private var dismiss

    @FocusState private var keywordsFocused: Bool

    /// The keyword field's text.
    ///
    /// Seeded from the query when the sheet appears and then only ever written *to*
    /// the query, never read back. Deriving the text from `query.keywords` on every
    /// render instead would rebuild it from the split words and eat the trailing
    /// space, making multi-word entry impossible. The sheet is modal, so nothing
    /// else can change the query underneath it while it is open.
    ///
    /// Seeded on appear rather than in `init`, which is what it used to do: a
    /// presenter that sets the query and raises the sheet in one action can build
    /// this view before that assignment is visible, and the snapshot came back
    /// empty. That is not cosmetic — ``commitFields`` writes these fields back on
    /// every keystroke *and* when Search is tapped, so an empty snapshot silently
    /// dropped the words the sheet was opened with.
    @State private var keywordsText: String = ""

    /// The exact-phrase field's text. Same one-way rule as ``keywordsText``.
    @State private var phraseText: String = ""

    /// Whether ``keywordsText`` and ``phraseText`` have been seeded. One-shot: the
    /// fields are the user's after that, and re-seeding would undo their typing.
    @State private var didSeedFields = false

    /// The tag being typed, before it is added.
    ///
    /// Deliberately *not* a mirror of `query.hashtags` the way ``keywordsText``
    /// mirrors the keywords: the tags a query already carries are rendered from the
    /// binding instead, so nothing here can be stale and no keystroke can write an
    /// empty field back over them. ``keywordsText`` needs its own storage for a
    /// reason a tag list does not have; where that choice is avoidable, avoid it.
    @State private var tagDraft: String = ""

    @State private var authorSearch: String = ""

    /// The query as the sheet found it, restored by Cancel.
    ///
    /// The sheet edits the binding directly, so by the time Cancel is tapped every
    /// change has already been written through — there is no draft to throw away.
    /// The two honest readings were "Cancel means stop editing" and "Cancel undoes
    /// what this sheet did"; this is the second, because the first is a lie on the
    /// results screen, where the binding is the running search and its chips. Edit
    /// the filters there, tap Cancel, and without this you are left looking at a
    /// *different* search than the one you cancelled out of.
    ///
    /// Captured alongside ``seedFields`` rather than in `init` for the same reason
    /// the text fields are: a presenter that sets the query and raises the sheet in
    /// one action can build this view before the assignment is visible, so an
    /// `init`-time snapshot would restore an empty query.
    @State private var restoreQuery: AdvancedSearchQuery?

    init(damus_state: DamusState,
         query: Binding<AdvancedSearchQuery>,
         autofocusKeywords: Bool = false,
         onSearch: @escaping () -> Void) {
        self.damus_state = damus_state
        self._query = query
        self.autofocusKeywords = autofocusKeywords
        self.onSearch = onSearch
    }

    /// Fills the text fields in from the query the sheet was opened with, and takes
    /// the snapshot Cancel restores. See ``keywordsText`` and ``restoreQuery``.
    private func seedFields() {
        guard !didSeedFields else { return }
        didSeedFields = true
        keywordsText = query.keywords.joined(separator: " ")
        phraseText = Self.phraseFieldText(for: query.phrases)
        restoreQuery = query
    }

    /// Clears every filter, the text fields included.
    private func resetFilters() {
        query = AdvancedSearchQuery()
        keywordsText = ""
        phraseText = ""
        tagDraft = ""
        authorSearch = ""
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

    /// What the local profile index has to say about what is in the author field.
    ///
    /// ``matched`` and ``addable`` are kept apart so an empty picker can explain
    /// itself: nothing matched at all is a different answer from everything that
    /// matched being on the query already, and showing no rows for both is what
    /// made the field look broken.
    private struct AuthorSuggestions {
        /// What was typed, trimmed. Empty means the field is empty and there is
        /// nothing to say either way.
        let term: String
        /// Every profile the index returned for ``term``.
        let matched: [Pubkey]
        /// Those of them not already on the query — the rows the picker offers.
        let addable: [Pubkey]
    }

    private var authorSuggestions: AuthorSuggestions {
        let search = authorSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return AuthorSuggestions(term: "", matched: [], addable: []) }
        let matched = search_profiles(profiles: damus_state.profiles, contacts: damus_state.contacts, search: search)
        let addable = matched
            .filter({ !query.authors.contains($0) })
            .prefix(20)
            .map({ $0 })
        return AuthorSuggestions(term: search, matched: matched, addable: addable)
    }

    /// Why the picker has no rows to show.
    ///
    /// The rest of this feature is careful to name where it looked — the results
    /// empty states, the DSL's "No profile found for" on the explore pane — and the
    /// picker searches the same local-only profile index, so it says so too rather
    /// than going blank and leaving somebody retyping a name that was never going to
    /// resolve.
    @ViewBuilder
    private func authorNote(_ suggestions: AuthorSuggestions) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if suggestions.matched.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text("No profile found for \(suggestions.term)", comment: "Warning that a name typed into the advanced search author picker matches nobody known to this device.")
                }
                Text("Author search covers only the profiles already stored on this device.", comment: "Explanation that the advanced search author picker can only find profiles the app has already downloaded.")
            } else {
                Text("Already added to this search.", comment: "Note that every profile matching what was typed into the advanced search author picker is already one of its authors.")
            }
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }

    /// True once adding another author would drop the query off nostrdb's fast
    /// author-kind plan.
    ///
    /// The picker refuses rather than truncating: silently dropping somebody the
    /// user chose would be worse than the slow path, and silently *taking* the slow
    /// path is what the cap exists to prevent.
    private var authorsAreFull: Bool { query.authors.count >= query.authorLimit }

    private var authorSection: some View {
        let suggestions = authorSuggestions

        return Section {
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

                ForEach(suggestions.addable, id: \.self) { pubkey in
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

                if !suggestions.term.isEmpty && suggestions.addable.isEmpty {
                    authorNote(suggestions)
                }
            }
        } header: {
            Text("Authors", comment: "Section header for the authors an advanced search covers.")
        }
    }

    // MARK: - Dates

    /// A date-only picker means a whole day, so a bound is snapped to that day's
    /// edge — the same rule a bare `YYYY-MM-DD` follows in the query language.
    private static func dayBound(_ date: Date, _ bound: AdvancedSearchQueryDSL.DateBound) -> Date {
        AdvancedSearchQueryDSL.dayBound(date, bound: bound)
    }

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

            // The toggles are their own rows rather than a DatePicker's label: a
            // disabled picker would disable the toggle inside it too, and a bound
            // that had been switched off could never be switched back on.
            Toggle(isOn: Binding(get: { query.since != nil },
                                 set: { query.since = $0 ? Self.dayBound(Date(), .since) : nil })) {
                Text("From", comment: "Label for the earliest date an advanced search covers.")
            }

            if query.since != nil {
                DatePicker(selection: Binding(get: { query.since ?? Date() },
                                              set: { query.since = Self.dayBound($0, .since) }),
                           displayedComponents: [.date]) {
                    Text("Start date", comment: "Label for the date picker choosing the earliest date an advanced search covers.")
                }
            }

            Toggle(isOn: Binding(get: { query.until != nil },
                                 set: { query.until = $0 ? Self.dayBound(Date(), .until) : nil })) {
                Text("To", comment: "Label for the latest date an advanced search covers.")
            }

            if query.until != nil {
                DatePicker(selection: Binding(get: { query.until ?? Date() },
                                              // Snapped to the end of the chosen day, then
                                              // clamped: both bounds are inclusive, so
                                              // `since == until` is a valid window and only
                                              // an inverted pair is empty.
                                              set: { query.until = max(Self.dayBound($0, .until), query.since ?? .distantPast) }),
                           in: (query.since ?? Date.distantPast)...,
                           displayedComponents: [.date]) {
                    Text("End date", comment: "Label for the date picker choosing the latest date an advanced search covers.")
                }
            }
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
                                 // An empty selection restores all indexed content types, so
                                 // turning every option off cannot produce a query that searches
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
                .focused($keywordsFocused)
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

    /// The tags the search is scoped to.
    ///
    /// Its own section rather than another line of the What section, because a tag
    /// is an *index* axis nostrdb narrows on while it walks rather than something
    /// matched against note content — and because the hashtag entry point arrives
    /// with one already set, which has to be visible here or the sheet would
    /// misdescribe the search it is about to run.
    ///
    /// Shaped like ``authorSection``: what the query holds is rendered from the
    /// binding and removed a row at a time, and the field only ever *adds*. See
    /// ``tagDraft``.
    private var tagSection: some View {
        Section {
            ForEach(query.hashtags, id: \.self) { tag in
                HStack {
                    Text(verbatim: "#\(tag)")
                    Spacer()
                    Button(action: { query.hashtags.removeAll(where: { $0 == tag }) }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField(NSLocalizedString("Add a hashtag", comment: "Placeholder for the field used to add a hashtag to an advanced search."),
                      text: $tagDraft)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .onSubmit { addDraftTag() }

            if !draftTagIsEmpty {
                Button(action: addDraftTag) {
                    HStack {
                        Text(verbatim: draftTagLabel)
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Tags", comment: "Section header for the hashtags an advanced search covers.")
        } footer: {
            Text("A note must carry every tag listed, as a tag rather than as a word in its text.", comment: "Explanation that advanced search hashtags are combined with AND and matched as tags.")
        }
    }

    private var draftTagIsEmpty: Bool {
        tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The draft as it will read once added — the `#` shown whether or not it was
    /// typed, since that is what the query means by a tag.
    private var draftTagLabel: String {
        let tag = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.hasPrefix("#") ? tag : "#\(tag)"
    }

    /// Adds the draft. The `#`, the case and any duplicate are
    /// ``AdvancedSearchQuery``'s to sort out, so the raw text goes straight in.
    private func addDraftTag() {
        guard !draftTagIsEmpty else { return }
        query.hashtags.append(tagDraft)
        tagDraft = ""
    }

    private var typeSection: some View {
        Section {
            kindToggle(.text, NSLocalizedString("Notes", comment: "Toggle for including short text notes in an advanced search."))
            kindToggle(.voice, NSLocalizedString("Voice", comment: "Toggle for searching voice transcripts."))
            kindToggle(.longform, NSLocalizedString("Long-form", comment: "Toggle for including long-form articles in an advanced search."))
        } header: {
            Text("Content type", comment: "Section header for which kinds of note an advanced search covers.")
        } footer: {
            Text("Search text notes, voice transcripts, and long-form posts.", comment: "Content types available in search.")
        }
    }

    /// Reset, at the bottom of the form rather than in the leading toolbar slot it
    /// used to hold. That slot belongs to Cancel — it is where every form sheet in
    /// iOS puts the way out — and Reset is the rarer, more destructive of the two,
    /// so it reads better as the last row of what it clears.
    private var resetSection: some View {
        Section {
            Button(role: .destructive, action: resetFilters) {
                Text("Reset filters", comment: "Button clearing every advanced search filter.")
            }
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
                tagSection
                authorSection
                dateSection
                typeSection
                sortSection
                resetSection
            }
            .task {
                seedFields()
                // After seeding, not before: focusing an empty field and then
                // filling it in behind the cursor is how a scoped entry point
                // would land somebody mid-word.
                if autofocusKeywords { keywordsFocused = true }
            }
            .navigationTitle(NSLocalizedString("Search filters", comment: "Title of the advanced search filter sheet."))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        // Undo what this sheet wrote through the binding. See
                        // ``restoreQuery``.
                        if let restoreQuery { query = restoreQuery }
                        dismiss()
                    }) {
                        Text("Cancel", comment: "Button leaving the advanced search filter sheet without searching.")
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

/// Presents the filters over the screen a search started from, and pushes the
/// results once one runs.
///
/// This is how the contextual entry points — the search button on a profile, the
/// one on a hashtag timeline — reach advanced search. They land on the filters
/// rather than straight on results, because all those buttons can prefill is the
/// *scope*: "everything this person ever posted" and "every note carrying this
/// tag" are not searches anybody tapped a magnifying glass to get, and the second
/// is a local-only copy of the timeline already on screen. The terms are the
/// search, so the filters are the destination and nothing runs until Search is
/// tapped.
///
/// Presented over the screen it started from rather than over a results view that
/// has not run: dismissing without searching then leaves you on the profile or
/// timeline you came from, rather than on an empty results screen whose only way
/// forward is the button you just dismissed.
struct AdvancedSearchScopeModifier: ViewModifier {
    let damus_state: DamusState
    @Binding var query: AdvancedSearchQuery
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            // Always autofocusing here rather than taking it as a parameter: every
            // screen that presents the sheet this way arrives with a scope and no
            // terms, which is exactly the condition the flag exists for. The flag
            // lives on the sheet because the *other* two presenters — over a typed
            // query, and over a running search — need it off.
            AdvancedSearchFilterSheet(damus_state: damus_state, query: $query, autofocusKeywords: true, onSearch: {
                // Reset can leave nothing to look for. Staying put beats pushing a
                // results screen that could only say "Search notes".
                guard !query.isTrivial else { return }
                damus_state.nav.push(route: .AdvancedSearch(model: AdvancedSearchModel(damus_state: damus_state, query: query)))
            })
        }
    }
}

extension View {
    /// Makes this screen an entry point into advanced search, scoped to `query`.
    /// See ``AdvancedSearchScopeModifier``.
    func advancedSearchScope(damus_state: DamusState,
                             query: Binding<AdvancedSearchQuery>,
                             isPresented: Binding<Bool>) -> some View {
        modifier(AdvancedSearchScopeModifier(damus_state: damus_state, query: query, isPresented: isPresented))
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
