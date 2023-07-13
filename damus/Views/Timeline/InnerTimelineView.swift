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
    
    static var count: Int = 0
    
    init(events: EventHolder, damus: DamusState, filter: @escaping (NostrEvent) -> Bool) {
        self.events = events
        self.state = damus
        self.filter = filter
        print("rendering InnerTimelineView \(InnerTimelineView.count)")
        InnerTimelineView.count += 1
    }
    
    var event_options: EventViewOptions {
        if self.state.settings.truncate_timeline_text {
            return [.wide, .truncate_content]
        }
        
        return [.wide]
    }
    
    var body: some View {
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
                            let event = ev.get_inner_event(cache: state.events) ?? ev
                            let thread = ThreadModel(event: event, damus_state: state)
                            state.nav.push(route: Route.Thread(thread: thread))
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

