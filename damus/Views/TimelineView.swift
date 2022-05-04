//
//  TimelineView.swift
//  damus
//
//  Created by William Casarin on 2022-04-18.
//

import SwiftUI

enum TimelineAction {
    case chillin
    case navigating
}

struct TimelineView: View {
    @Binding var events: [NostrEvent]

    @EnvironmentObject var profiles: Profiles
    
    let damus: DamusState
    
    var body: some View {
        MainContent
        .padding([.leading, .trailing], 6)
        .environmentObject(profiles)
    }
    
    var MainContent: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack {
                    ForEach(events, id: \.id) { (ev: NostrEvent) in
                        /*
                        let evdet = EventDetailView(thread: ThreadModel(event: ev, pool: pool))
                            .navigationBarTitle("Thread")
                            .padding([.leading, .trailing], 6)
                            .environmentObject(profiles)
                         */
                        
                        let tv = ThreadView(thread: ThreadModel(ev: ev, pool: damus.pool), damus: damus)
                            .environmentObject(profiles)
                        
                        NavigationLink(destination: tv) {
                            EventView(event: ev, highlight: .none, has_action_bar: true, damus: damus)
                        }
                        .isDetailLink(true)
                        .buttonStyle(PlainButtonStyle())
                            //.onTapGesture {
                                //NotificationCenter.default.post(name: .open_thread, object: ev)
                            //}
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scroll_to_top)) { _ in
                guard let event = events.first else {
                    return
                }
                scroll_to_event(scroller: scroller, id: event.id, delay: 0.0, animate: true)
            }
        }
    }
}

/*
struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineView()
    }
}
 */


struct NavigationLazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}
