//
//  InnerTimelineView.swift
//  damus
//
//  Created by William Casarin on 2023-02-20.
//

import SwiftUI


struct InnerTimelineView: View {
    var events: EventHolder
    @StateObject var filteredEvents: EventHolder.FilteredHolder
    let state: DamusState

    init(events: EventHolder, damus: DamusState, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true) {
        self.events = events
        self.state = damus
        let filter = apply_mute_rules ? { filter($0) && !damus.mutelist_manager.is_event_muted($0) } : filter
        _filteredEvents = StateObject.init(wrappedValue: EventHolder.FilteredHolder(filter: filter, parent: events))
    }
    
    var event_options: EventViewOptions {
        if self.state.settings.truncate_timeline_text {
            return [.wide, .truncate_content]
        }
        
        return [.wide]
    }
    
    var body: some View {
        LazyVStack(spacing: 0) {
            let events = self.filteredEvents.events
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                let indexed = Array(zip(events, 0...))
                ForEach(indexed, id: \.0.id) { tup in
                    let ev = tup.0
                    let ind = tup.1
                    let to_preload = Array([indexed[safe: ind+1]?.0,
                           indexed[safe: ind+2]?.0,
                           indexed[safe: ind+3]?.0,
                           indexed[safe: ind+4]?.0,
                           indexed[safe: ind+5]?.0
                          ].compactMap({ $0 }))
                    EventView(damus: state, event: ev, options: event_options)
                        .onTapGesture {
                            let event = ev.get_inner_event(cache: state.events) ?? ev
                            let thread = ThreadModel(event: event, damus_state: state)
                            state.nav.push(route: Route.Thread(thread: thread))
                        }
                        .padding(.top, 7)
                        .onAppear {
                            preload_events(state: state, events: to_preload)
                        }
                        .task {
                            // NOTE: Profile loading is also done in the events themselves. So this is more of an optimization to preload profiles
                            // into NostrDB before the notes appear, in order to prevent a "poppy" feel.
                            // NOTE 2: Perhaps this should be in "preload_events", but that function is designed as a fire-and-forget function,
                            // which is not compatible with a continuous streaming task with a lifetime bound to the view itself,
                            // so I will do this preloading here as it has a more predictable lifecycle that will auto-cleanup
                            // the task once the view disappears
                            guard let pubkeysToPreload = try? getPubkeysToPreloadFor(events: to_preload, ndb: state.ndb, ourKeypair: state.keypair) else {
                                Log.error("Error preloading profiles in timeline", for: .timeline)
                                return
                            }
                            Log.debug("PRELOAD: preloading %d pubkeys", for: .timeline, pubkeysToPreload.count)
                            for await profile in await state.nostrNetwork.profilesManager.streamProfiles(pubkeys: pubkeysToPreload, yieldCached: false) {
                                Log.debug("PRELOAD: Preloaded %s", for: .timeline, profile.display_name ?? "someone")
                                // NO-OP, we just want these to be in ndb
                                continue
                            }
                        }
                    
                    ThiccDivider()
                        .padding([.top], 7)
                }
            }
        }
    }
}

extension InnerTimelineView {
    // MARK: Functions to help with preloading profiles
    
    fileprivate func getPubkeysToPreloadFor(events: [NdbNote], ndb: Ndb, ourKeypair: Keypair) throws -> Set<Pubkey> {
        var relevantPubkeys: Set<Pubkey> = []
        
        for event in events {
            relevantPubkeys.formUnion(try getPubkeysToPreloadFor(event: event, ndb: ndb, ourKeypair: ourKeypair))
        }
        
        return relevantPubkeys
    }
    
    fileprivate func getPubkeysToPreloadFor(event: NdbNote, ndb: Ndb, ourKeypair: Keypair) throws -> Set<Pubkey> {
        var relevantPubkeys: Set<Pubkey> = [event.pubkey]
        try NdbBlockGroup.borrowBlockGroup(event: event, using: ndb, and: ourKeypair, borrow: { blockGroup in
            blockGroup.forEachBlock({ _, block in
                guard let pubkey = block.mentionPubkey(tags: event.tags) else {
                    return .loopContinue
                }
                relevantPubkeys.insert(pubkey)
                return .loopContinue
            })
        })
        
        return relevantPubkeys
    }
}

struct InnerTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        InnerTimelineView(events: test_event_holder, damus: test_damus_state, filter: { _ in true })
            .frame(width: 300, height: 500)
            .border(Color.red)
    }
}

