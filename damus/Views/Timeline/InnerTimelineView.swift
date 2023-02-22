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
    @State var nav_target: NostrEvent? = nil
    @State var navigating: Bool = false
    
    var MaybeBuildThreadView: some View {
        Group {
            if let ev = nav_target {
                BuildThreadV2View(damus: damus, event_id: (ev.inner_event ?? ev).id)
            } else {
                EmptyView()
            }
        }
    }
    
    var body: some View {
        NavigationLink(destination: MaybeBuildThreadView, isActive: $navigating) {
            EmptyView()
        }
        LazyVStack(spacing: 0) {
            let events = self.events.events
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                ForEach(events.filter(filter), id: \.id) { (ev: NostrEvent) in
                    EventView(damus: damus, event: ev, has_action_bar: true)
                        .onTapGesture {
                            nav_target = ev
                            navigating = true
                        }
                        .padding(.top, 10)
                    
                    Divider()
                        .padding([.top], 10)
                }
            }
        }
        .padding(.horizontal)
    }
}


struct InnerTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        InnerTimelineView(events: test_event_holder, damus: test_damus_state(), show_friend_icon: true, filter: { _ in true }, nav_target: nil, navigating: false)
            .frame(width: 300, height: 500)
            .border(Color.red)
    }
}
