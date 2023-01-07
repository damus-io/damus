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
    
    mutating func clean() {
        // remove duplicates
        self.parentEvents = Array(Set(self.parentEvents))
        self.childEvents = Array(Set(self.childEvents))
        
        // remove empty contents
        self.parentEvents = self.parentEvents.filter { event in
            return !event.content.isEmpty
        }
        self.childEvents = self.childEvents.filter { event in
            return !event.content.isEmpty
        }
        
        // sort events by publication date
        self.parentEvents = self.parentEvents.sorted { event1, event2 in
            return event1 < event2
        }
        self.childEvents = self.childEvents.sorted { event1, event2 in
            return event1 < event2
        }
    }
}


struct BuildThreadV2View: View {
    let damus: DamusState
    
    @State var parents_ids: [String] = []
    let event_id: String
    
    @State var current_event: NostrEvent? = nil
    
    @State var thread: ThreadV2? = nil
    
    @State var current_events_uuid: String = ""
    @State var childs_events_uuid: String = ""
    @State var parents_events_uuids: [String] = []
    
    @State var subscriptions_uuids: [String] = []
    
    @Environment(\.dismiss) var dismiss
    
    init(damus: DamusState, event_id: String) {
        self.damus = damus
        self.event_id = event_id
    }
    
    func unsubscribe_all() {
        print("ThreadV2View: Unsubscribe all..")
        
        for subscriptions in subscriptions_uuids {
            unsubscribe(subscriptions)
        }
    }
    
    func unsubscribe(_ sub_id: String) {
        if subscriptions_uuids.contains(sub_id) {
            damus.pool.unsubscribe(sub_id: sub_id)
            
            subscriptions_uuids.remove(at: subscriptions_uuids.firstIndex(of: sub_id)!)
        }
    }
    
    func subscribe(filters: [NostrFilter], sub_id: String = UUID().description) -> String {
        damus.pool.register_handler(sub_id: sub_id, handler: handle_event)
        damus.pool.send(.subscribe(.init(filters: filters, sub_id: sub_id)))
        
        subscriptions_uuids.append(sub_id)
        
        return sub_id
    }
    
    func handle_current_events(ev: NostrEvent) {
        if current_event != nil {
            return
        }
        
        current_event = ev
        
        thread = ThreadV2(
            parentEvents: [],
            current: current_event!,
            childEvents: []
        )
        
        // Get parents
        parents_ids = current_event!.tags.enumerated().filter { (index, tag) in
            return tag.count >= 2 && tag[0] == "e" && !current_event!.content.contains("#[\(index)]")
        }.map { tag in
            return tag.1[1]
        }
        
        print("ThreadV2View: Parents list: (\(parents_ids)")
        
        if parents_ids.count > 0 {
            // Ask for parents
            let parents_events = NostrFilter(
                ids: parents_ids,
                limit: UInt32(parents_ids.count)
            )
            
            let uuid = subscribe(filters: [parents_events])
            parents_events_uuids.append(uuid)
            print("ThreadV2View: Ask for parents (\(uuid)) (\(parents_events))")
        }
        
        // Ask for children
        let childs_events = NostrFilter(
            kinds: [1],
            referenced_ids: [self.event_id],
            limit: 50
        )
        childs_events_uuid = subscribe(filters: [childs_events])
        print("ThreadV2View: Ask for children (\(childs_events) (\(childs_events_uuid))")
    }
    
    func handle_parent_events(sub_id: String, nostr_event: NostrEvent) {
    
        // We are filtering this later
        thread!.parentEvents.append(nostr_event)
        
        // Get parents of parents
        let local_parents_ids = nostr_event.tags.enumerated().filter { (index, tag) in
            return tag.count >= 2 && tag[0] == "e" && !nostr_event.content.contains("#[\(index)]")
        }.map { tag in
            return tag.1[1]
        }.filter { tag_id in
            return !parents_ids.contains(tag_id)
        }
        
        print("ThreadV2View: Sub Parents list: (\(local_parents_ids))")
        
        // Expand new parents id
        parents_ids.append(contentsOf: local_parents_ids)
        
        if local_parents_ids.count > 0 {
            // Ask for parents
            let parents_events = NostrFilter(
                ids: local_parents_ids,
                limit: UInt32(local_parents_ids.count)
            )
            let uuid = subscribe(filters: [parents_events])
            parents_events_uuids.append(uuid)
            print("ThreadV2View: Ask for sub_parents (\(local_parents_ids)) \(uuid)")
        }
        
        thread!.clean()
        unsubscribe(sub_id)
        return
    
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        guard case .nostr_event(let nostr_response) = ev else {
            return
        }
        
        guard case .event(let id, let nostr_event) = nostr_response else {
            return
        }
        
        // Is current event
        if id == current_events_uuid {
            handle_current_events(ev: nostr_event)
            return
        }
        
        if parents_events_uuids.contains(id) {
            handle_parent_events(sub_id: id, nostr_event: nostr_event)
            return
        }
        
        if id == childs_events_uuid {
            // We are filtering this later
            thread!.childEvents.append(nostr_event)
            
            thread!.clean()
            return
        }
    }

    func reload() {
        self.unsubscribe_all()
        print("ThreadV2View: Reload!")
        
        // Get the current event
        current_events_uuid = subscribe(filters: [
            NostrFilter(
                ids: [self.event_id],
                limit: 1
            )
        ])
        print("subscribing to threadV2 \(event_id) with sub_id \(current_events_uuid)")
    }
    
    var body: some View {
        VStack {
            if thread == nil {
                ProgressView()
            } else {
                ThreadV2View(damus: damus, thread: thread!)
            }
        }
        .onAppear {
            if self.thread == nil {
                self.reload()
            }
        }
        .onDisappear {
            self.unsubscribe_all()
        }
        .onReceive(handle_notify(.switched_timeline)) { n in
            dismiss()
        }
    }
}

struct ThreadV2View: View {
    let damus: DamusState
    let thread: ThreadV2
    @State var nav_target: String? = nil
    @State var navigating: Bool = false
    
    var MaybeBuildThreadView: some View {
        Group {
            if let evid = nav_target {
                BuildThreadV2View(damus: damus, event_id: evid)
            } else {
                EmptyView()
            }
        }
    }
    
    var body: some View {
        NavigationLink(destination: MaybeBuildThreadView, isActive: $navigating) {
            EmptyView()
        }
        ScrollViewReader { reader in
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
                            .onTapGesture {
                                nav_target = event.id
                                navigating = true
                            }
                            .onAppear {
                                // TODO: find another solution to prevent layout shifting and layout blocking on large responses
                                reader.scrollTo("main", anchor: .bottom)
                            }
                        }
                    }.background(GeometryReader { geometry in
                        // get the height and width of the EventView view
                        let eventHeight = geometry.frame(in: .global).height
                        //                    let eventWidth = geometry.frame(in: .global).width
                        
                        // vertical gray line in the background
                        Rectangle()
                            .fill(Color.gray.opacity(0.25))
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
                    ).id("main")
                    
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
                        .onTapGesture {
                            nav_target = event.id
                            navigating = true
                        }
                    }
                }.padding()
            }.navigationBarTitle("Thread")
        }
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
