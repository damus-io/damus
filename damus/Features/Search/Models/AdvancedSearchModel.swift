//
//  AdvancedSearchModel.swift
//  damus
//
//  Created by William Casarin on 2026-09-02.
//

import Foundation

/// Runs advanced searches on behalf of a view: debounced, off the main thread,
/// and cancellable.
///
/// ``AdvancedSearchEngine`` is synchronous and blocking; this is what makes it
/// safe to drive from a text field. Assigning ``query`` supersedes whatever was
/// running, so a user typing produces one search rather than one per keystroke,
/// and the results are always the ones the current query asked for.
///
/// The model owns its results rather than writing into a binding, so a `Route`
/// can carry it without threading a `Binding` through navigation the way
/// `Route.NDBSearch` does.
@MainActor
final class AdvancedSearchModel: ObservableObject {
    /// How long to wait for typing to stop before touching the database.
    ///
    /// Matches the 0.25s the existing search field already uses (`Debouncer` in
    /// `SearchResultsView`), so the two panes feel the same.
    static let debounceInterval: Duration = .milliseconds(250)

    /// What to search for. Assigning it starts a new search and abandons any
    /// search already running.
    ///
    /// This is the only piece of state the filter sheet and the query text field
    /// share, on purpose: neither keeps its own copy to drift out of sync.
    @Published var query: AdvancedSearchQuery {
        didSet {
            guard query != oldValue else { return }
            restart()
        }
    }

    /// Where the current search has got to.
    @Published private(set) var state: State = .idle(reason: .emptyQuery)

    enum State {
        /// Nothing was run, and why. The reason is what lets a view say "we did
        /// not search" rather than the much worse "we searched and found nothing".
        case idle(reason: AdvancedSearchPlan.Reason)

        /// A search is in flight. Carries the previous results so a view can keep
        /// showing them instead of flashing empty while the user types.
        case searching(previous: [NostrEvent])

        /// A search finished.
        ///
        /// `reachedLimit` means nostrdb filled every result slot it was given, so
        /// there are probably older matches this batch does not include. Fetching
        /// them is Phase 4; until then a view has to say so rather than imply the
        /// list is complete.
        case results([NostrEvent], reachedLimit: Bool)

        /// The database refused the query. Rare — a filter that would not convert,
        /// or a transaction that could not open.
        case failed

        /// The results to show right now, whether or not a search is running.
        var events: [NostrEvent] {
            switch self {
            case .idle, .failed: return []
            case .searching(let previous): return previous
            case .results(let events, _): return events
            }
        }

        var isSearching: Bool {
            if case .searching = self { return true }
            return false
        }
    }

    private let damus_state: DamusState
    private var inFlight: Task<Void, Never>?

    init(damus_state: DamusState, query: AdvancedSearchQuery = AdvancedSearchQuery()) {
        self.damus_state = damus_state
        self.query = query
    }

    /// Runs ``query`` now, without waiting out the debounce.
    ///
    /// For the cases where the query did not arrive a keystroke at a time — the
    /// filter sheet's Search button, or a view appearing with a prefilled query.
    func search() {
        restart(debounced: false)
    }

    /// Re-runs the current query.
    ///
    /// Worth doing when the *database* changed under a query that did not: a new
    /// mute has to re-run rather than filter the results in place, because
    /// re-running also refills the slots the mute freed up.
    func refresh() {
        restart(debounced: false)
    }

    /// Abandons any search in flight.
    ///
    /// Call from `onDisappear`, so a search nobody is waiting for stops competing
    /// for database transactions.
    func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    private func restart(debounced: Bool = true) {
        inFlight?.cancel()

        // Planning is pure and cheap, so it happens before the debounce: a query
        // with nothing to run should say so the instant it is typed rather than a
        // quarter second later.
        let plan = AdvancedSearchPlanner.plan(for: query)
        if case .nothingToRun(let reason) = plan {
            inFlight = nil
            state = .idle(reason: reason)
            return
        }

        let query = self.query
        state = .searching(previous: state.events)

        inFlight = Task { [weak self] in
            if debounced {
                do { try await Task.sleep(for: Self.debounceInterval) } catch { return }
            }
            guard !Task.isCancelled, let self else { return }

            let outcome = await Self.run(plan, order: query.order, in: self.damus_state)

            guard !Task.isCancelled else { return }
            switch outcome {
            case .some(let found):
                self.state = .results(found.events, reachedLimit: found.reachedLimit)
            case .none:
                self.state = .failed
            }
        }
    }

    private struct Output {
        let events: [NostrEvent]
        let reachedLimit: Bool
    }

    /// Runs a plan off the main actor and brings back owned notes.
    ///
    /// `nonisolated async` rather than a detached task: the caller is on the main
    /// actor, and a nonisolated async function hops off it on its own. Note that
    /// the index walk itself cannot be interrupted once nostrdb is inside it —
    /// cancellation is checked either side of it, so a superseded search stops
    /// mattering promptly but does not stop immediately.
    private nonisolated static func run(_ plan: AdvancedSearchPlan,
                                        order: NdbSearchOrder,
                                        in state: DamusState) async -> Output? {
        let rules = await state.mutelist_manager.rules

        do {
            let found = try AdvancedSearchEngine.run(plan, order: order, in: state.ndb, excluding: rules)
            let events = try state.ndb.compact_map_notes(keys: found.keys, { _, note in note.toOwned() })
            return Output(events: ordered(events, by: order), reachedLimit: found.reachedLimit)
        } catch {
            Log.error("advanced search failed: %s", for: .ndb, error.localizedDescription)
            return nil
        }
    }

    /// Deduplicates and sorts the results.
    ///
    /// Both halves are compensating for nostrdb's text index, which can return the
    /// same note twice and in a mixed order — the two TODOs on the existing search
    /// path, tracked as Phase 12. The index-walk strategy needs neither, and
    /// sorting an already-sorted list is free, so this is applied to both rather
    /// than only to the path that needs it. It comes out when Phase 12 lands.
    private nonisolated static func ordered(_ events: [NostrEvent], by order: NdbSearchOrder) -> [NostrEvent] {
        var seen = Set<NoteId>()
        let unique = events.filter({ seen.insert($0.id).inserted })

        switch order {
        case .newest_first: return unique.sorted(by: { $0.created_at > $1.created_at })
        case .oldest_first: return unique.sorted(by: { $0.created_at < $1.created_at })
        }
    }
}
