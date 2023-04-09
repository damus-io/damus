//
//  InnerTimelineView.swift
//  damus
//
//  Created by William Casarin on 2023-02-20.
//

import SwiftUI


struct InnerTimelineView: View {
    @ObservedObject var events: EventHolder
    let damus: DamusState
    let show_friend_icon: Bool
    let filter: (NostrEvent) -> Bool
    @State var nav_target: NostrEvent
    @State var navigating: Bool = false
    
    init(events: EventHolder, damus: DamusState, show_friend_icon: Bool, filter: @escaping (NostrEvent) -> Bool) {
        self.events = events
        self.damus = damus
        self.show_friend_icon = show_friend_icon
        self.filter = filter
        // dummy event to avoid MaybeThreadView
        self._nav_target = State(initialValue: test_event)
    }
    
    var event_options: EventViewOptions {
        if self.damus.settings.truncate_timeline_text {
            return [.wide, .truncate_content]
        }
        
        return [.wide]
    }
    
    var body: some View {
        let thread = ThreadModel(event: nav_target, damus_state: damus)
        let dest = ThreadView(state: damus, thread: thread)
        NavigationLink(destination: dest, isActive: $navigating) {
            EmptyView()
        }
        LazyVStack(spacing: 0) {
            let events = self.events.events
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                ForEach(events.filter(filter), id: \.id) { (ev: NostrEvent) in
                    EventView(damus: damus, event: ev, options: event_options)
                        .onTapGesture {
                            nav_target = ev.inner_event ?? ev
                            navigating = true
                        }
                        .padding(.top, 7)
                    
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
        InnerTimelineView(events: test_event_holder, damus: test_damus_state(), show_friend_icon: true, filter: { _ in true })
            .frame(width: 300, height: 500)
            .border(Color.red)
    }
}
