//
//  InnerTimelineView.swift
//  damus
//
//  Created by William Casarin on 2023-02-20.
//

import SwiftUI


struct InnerTimelineView: View {
    @ObservedObject var events: EventHolder
    let state: DamusState
    let filter: (NostrEvent) -> Bool
    @State var nav_target: NostrEvent
    @State var navigating: Bool = false
    
    init(events: EventHolder, damus: DamusState, filter: @escaping (NostrEvent) -> Bool) {
        self.events = events
        self.state = damus
        self.filter = filter
        // dummy event to avoid MaybeThreadView
        self._nav_target = State(initialValue: test_event)
    }
    
    var event_options: EventViewOptions {
        if self.state.settings.truncate_timeline_text {
            return [.wide, .truncate_content]
        }
        
        return [.wide]
    }
    
    var body: some View {
        let thread = ThreadModel(event: nav_target, damus_state: state)
        let dest = ThreadView(state: state, thread: thread)
        NavigationLink(destination: dest, isActive: $navigating) {
            EmptyView()
        }
        LazyVStack(spacing: 0) {
            let events = self.events.events
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                let evs = events.filter(filter)
                let indexed = Array(zip(evs, 0...))
                ForEach(indexed, id: \.0.id) { tup in
                    let ev = tup.0
                    let ind = tup.1
                    EventView(damus: state, event: ev, options: event_options)
                        .onTapGesture {
                            nav_target = ev.get_inner_event(cache: state.events) ?? ev
                            navigating = true
                        }
                        .padding(.top, 7)
                        .onAppear {
                            let to_preload =
                            Array([indexed[safe: ind+1]?.0,
                                   indexed[safe: ind+2]?.0,
                                   indexed[safe: ind+3]?.0,
                                   indexed[safe: ind+4]?.0,
                                   indexed[safe: ind+5]?.0
                                  ].compactMap({ $0 }))
                            
                            preload_events(state: state, events: to_preload)
                        }
                    
                    ThiccDivider()
                        .padding([.top], 7)
                }
            }
        }
        //.padding(.horizontal)
        
    }
}


struct InnerTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        InnerTimelineView(events: test_event_holder, damus: test_damus_state(), filter: { _ in true })
            .frame(width: 300, height: 500)
            .border(Color.red)
    }
}

