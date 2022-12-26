//
//  ThreadV2View.swift
//  damus
//
//  Created by Thomas Tastet on 25/12/2022.
//

import SwiftUI

struct ThreadV2 {
    var parentEvents: [NostrEvent]
    var current: NostrEvent
    var childEvents: [NostrEvent]
}

struct BuildThreadV2View: View {
    let damus: DamusState
    let event_id: String
    
    @State var thread: ThreadV2?
    
    init(damus: DamusState, event_id: String, thread: ThreadV2? = nil) {
        self.damus = damus
        self.event_id = event_id
        self.thread = thread
        
        if self.thread == nil {
            self.reload()
        }
    }
    
    func reload() {
        // TODO: construct the thread
    }
    
    var body: some View {
        if thread == nil {
            ProgressView()
        } else {
            ThreadV2View(damus: damus, thread: thread!)
        }
    }
}

struct ThreadV2View: View {
    let damus: DamusState
    let thread: ThreadV2
    
    var body: some View {
        ScrollView {
            VStack {
                // MARK: - Parents events view
                VStack {
                    ForEach(thread.parentEvents, id: \.id) { event in
                        EventView(
                            event: event,
                            highlight: .none,
                            has_action_bar: true,
                            damus: damus,
                            show_friend_icon: true, // TODO: change it
                            size: .small
                        )
                    }
                }.background(GeometryReader { geometry in
                    // get the height and width of the EventView view
                    let eventHeight = geometry.frame(in: .global).height
//                    let eventWidth = geometry.frame(in: .global).width

                    // vertical gray line in the background
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 2, height: eventHeight)
                        .offset(x: 25, y: 40)
                })
                
                // MARK: - Actual event view
                EventView(
                    event: thread.current,
                    highlight: .none,
                    has_action_bar: true,
                    damus: damus,
                    show_friend_icon: true, // TODO: change it
                    size: .selected
                )
                
                // MARK: - Responses of the actual event view
                ForEach(thread.childEvents, id: \.id) { event in
                    EventView(
                        event: event,
                        highlight: .none,
                        has_action_bar: true,
                        damus: damus,
                        show_friend_icon: true, // TODO: change it
                        size: .small
                    )
                }
            }
        }.padding().navigationBarTitle("Thread")
    }
}

struct ThreadV2View_Previews: PreviewProvider {
    static var previews: some View {
        BuildThreadV2View(damus: test_damus_state(), event_id: "ac9fd97b53b0c1d22b3aea2a3d62e11ae393960f5f91ee1791987d60151339a7")
        ThreadV2View(
            damus: test_damus_state(),
            thread: ThreadV2(
                parentEvents: [
                    NostrEvent(id: "1", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                    NostrEvent(id: "2", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                    NostrEvent(id: "3", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                ],
                current: NostrEvent(id: "4", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                childEvents: [
                    NostrEvent(id: "5", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                    NostrEvent(id: "6", content: "hello there https://jb55.com/s/Oct12-150217.png https://jb55.com/red-me.jb55 cool 4", pubkey: "916b7aca250f43b9f842faccc831db4d155088632a8c27c0d140f2043331ba57"),
                ]
            )
        )
    }
}
