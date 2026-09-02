//
//  AdvancedSearchView.swift
//  damus
//
//  Created by William Casarin on 2026-09-02.
//

import SwiftUI

/// Where an advanced search lands: the results, and the constraints that produced
/// them.
///
/// The chip row above the list is the load-bearing part. A narrowed local search
/// can legitimately return very little, and the difference between "there is
/// nothing to find" and "your date window is two hours wide" has to be visible
/// and one tap away — otherwise a search that found nothing looks like an answer.
struct AdvancedSearchView: View {
    let damus_state: DamusState
    @ObservedObject var model: AdvancedSearchModel

    @State private var filtersPresented = false

    /// The terms `EventView` highlights in the results.
    ///
    /// Taken from the query rather than re-split out of the raw search text, which
    /// is what `NDBSearchView` has to do — so a phrase highlights as a phrase and
    /// a `from:` never highlights as a word.
    private var highlightTerms: [String] {
        var terms = model.query.phrases + model.query.keywords + model.query.hashtags
        terms = terms.map({ $0.lowercased() })

        var seen = Set<String>()
        return terms.filter({ !$0.isEmpty && seen.insert($0).inserted })
    }

    private func name(for pubkey: Pubkey) -> String {
        let profile = try? damus_state.profiles.lookup(id: pubkey)
        return Profile.displayName(profile: profile, pubkey: pubkey).username.truncate(maxLength: 30)
    }

    private func remove(_ constraint: AdvancedSearchConstraint) {
        model.query = constraint.removed(from: model.query)
    }

    // MARK: - Chips

    private func chip(_ constraint: AdvancedSearchConstraint) -> some View {
        Button(action: { remove(constraint) }) {
            HStack(spacing: 4) {
                Text(constraint.label(authorName: name))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DamusColors.neutral1)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(DamusColors.neutral3, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: NSLocalizedString("Remove filter %@", comment: "Accessibility label for a button that removes one search filter."),
                                   constraint.label(authorName: name)))
    }

    @ViewBuilder
    private var chips: some View {
        let constraints = AdvancedSearchConstraint.all(in: model.query)
        if !constraints.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(constraints) { constraint in
                        chip(constraint)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Status

    /// The line under the chips: how many, and whether that is all of them.
    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .searching:
            Label(NSLocalizedString("Searching…", comment: "Label shown while a search is running."),
                  systemImage: "ellipsis")
        case .results(let events, let reachedLimit):
            if reachedLimit {
                // Deliberately not "N results": nostrdb filled every slot it was
                // given, so this is a first batch rather than an answer.
                Text("First \(events.count) matches", comment: "Label indicating the search returned as many results as the database would give in one batch, and there may be more.")
            } else {
                Text("\(events.count) matches", comment: "Label indicating how many notes a search matched.")
            }
        case .idle, .failed:
            EmptyView()
        }
    }

    // MARK: - Empty states

    /// What to say when there is nothing to show.
    ///
    /// Every branch names where it looked. Local search only sees the notes
    /// nostrdb has already ingested, which *is* the complaint this feature came
    /// from — so an empty result that reads as authoritative is worse than the
    /// vaguer behaviour it replaces.
    @ViewBuilder
    private func empty(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 10) {
            Image("search")
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.top, 60)
    }

    /// The line every "found nothing" state ends with.
    private var localOnlyNote: String {
        NSLocalizedString("Search covers only the notes already stored on this device. Notes that were never downloaded from a relay will not appear here.",
                          comment: "Explanation that local search cannot see notes the app has not downloaded.")
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.state {
        case .idle(let reason):
            switch reason {
            case .emptyQuery:
                empty(NSLocalizedString("Search notes", comment: "Title of the advanced search empty state before anything has been entered."),
                      NSLocalizedString("Add a word, a phrase, an author or a hashtag to search for.",
                                        comment: "Explanation of what an advanced search needs before it can run."))
            case .unconstrained:
                empty(NSLocalizedString("Nothing to search for", comment: "Title shown when an advanced search has a date range but nothing to look for."),
                      NSLocalizedString("A date range on its own would match every note. Add a word, an author or a hashtag.",
                                        comment: "Explanation that a date range alone is not a search."))
            case .emptyDateWindow:
                empty(NSLocalizedString("That date range is empty", comment: "Title shown when an advanced search's start date is after its end date."),
                      NSLocalizedString("The start of the range is after the end of it, so no note can fall inside.",
                                        comment: "Explanation that a search's since date is later than its until date."))
            case .noIndexableTerms:
                empty(NSLocalizedString("Words are too short to search", comment: "Title shown when every word of a search is too short for the note index."),
                      NSLocalizedString("The note index cannot look up words shorter than two characters on their own. Add a longer word, an author or a hashtag.",
                                        comment: "Explanation that nostrdb cannot search for single-character words without another constraint."))
            }
        case .failed:
            empty(NSLocalizedString("Search failed", comment: "Title shown when an advanced search could not be run at all."),
                  NSLocalizedString("The note database could not run that search. Try changing the filters.",
                                    comment: "Explanation shown when a search could not be run."))
        case .searching:
            // Nothing yet, but nor is there an answer yet. The status line above
            // already says a search is running; "No matches" here would contradict
            // it.
            EmptyView()
        case .results:
            empty(NSLocalizedString("No matches", comment: "Title shown when an advanced search ran and matched nothing."),
                  localOnlyNote)
        }
    }

    // MARK: - Body

    private var results: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.state.events, id: \.self) { note in
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
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                chips

                status
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                if model.state.events.isEmpty {
                    emptyState
                } else {
                    results
                }
            }
            .padding(.top, 10)
        }
        .navigationTitle(NSLocalizedString("Search", comment: "Title of the advanced search results screen."))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { filtersPresented = true }) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(NSLocalizedString("Search filters", comment: "Accessibility label for the button that opens the advanced search filters."))
            }
        }
        // Bound straight to the model's query, so editing the filters re-runs the
        // search in place rather than pushing another screen. Chips take a
        // constraint off; this is how one goes back on.
        .sheet(isPresented: $filtersPresented) {
            AdvancedSearchFilterSheet(damus_state: damus_state, query: $model.query, onSearch: { model.search() })
        }
        .task {
            // `.task` rather than `onAppear`: a prefilled query — from a profile,
            // a hashtag, or the filter sheet — has to run without waiting out a
            // debounce nobody typed into.
            model.search()
        }
        .onDisappear {
            model.cancel()
        }
        // Muting from inside the results has to re-run rather than filter what is
        // on screen: re-running also refills the slots the mute frees up.
        .onReceive(handle_notify(.new_mutes)) { _ in model.refresh() }
        .onReceive(handle_notify(.new_unmutes)) { _ in model.refresh() }
    }
}

struct AdvancedSearchView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        AdvancedSearchView(damus_state: state,
                           model: AdvancedSearchModel(damus_state: state,
                                                      query: AdvancedSearchQuery(keywords: ["fox"],
                                                                                 phrases: ["jumped over"],
                                                                                 hashtags: ["nostr"])))
    }
}
