//
//  SpellTimelineView.swift
//  damus
//
//  A timeline view for spell feed results that uses SpellResultView
//  to resolve referenced events (zaps, reactions) into their
//  primary content with action context.
//

import SwiftUI

/// Displays spell feed events in a timeline, using SpellResultView
/// to handle referenced event resolution for zaps and reactions.
struct SpellTimelineView: View {
    let events: [NostrEvent]
    let damus: DamusState

    var event_options: EventViewOptions {
        if damus.settings.truncate_timeline_text {
            return [.wide, .truncate_content]
        }
        return [.wide]
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                let indexed = Array(zip(events, 0...))
                ForEach(indexed, id: \.0.id) { tup in
                    let ev = tup.0
                    let ind = tup.1

                    SpellResultView(damus: damus, event: ev, options: event_options)
                        .onTapGesture {
                            let target = resolvedTapTarget(ev)
                            let thread = ThreadModel(event: target, damus_state: damus)
                            damus.nav.push(route: Route.Thread(thread: thread))
                        }
                        .padding(.top, 7)
                        .onAppear {
                            let toPreload = [
                                indexed[safe: ind+1]?.0,
                                indexed[safe: ind+2]?.0,
                                indexed[safe: ind+3]?.0,
                                indexed[safe: ind+4]?.0,
                                indexed[safe: ind+5]?.0
                            ].compactMap { $0 }
                            preload_events(state: damus, events: toPreload)
                        }

                    ThiccDivider()
                        .padding([.top], 7)
                }
            }
        }
    }

    /// Determines the correct tap target for a spell result event.
    ///
    /// For reference events (reposts, zaps, reactions), navigates to
    /// the referenced event's thread. For other events, navigates
    /// to the event itself.
    private func resolvedTapTarget(_ ev: NostrEvent) -> NostrEvent {
        // Reposts: use inner event if available
        if let inner = ev.get_inner_event(cache: damus.events) {
            return inner
        }

        // Reactions/zaps: try to find referenced event in cache
        if ev.known_kind == .like || ev.known_kind == .zap {
            if let refId = ev.referenced_ids.first,
               let cached = damus.events.lookup(refId) {
                return cached
            }
        }

        return ev
    }
}
