//
//  ThreadView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

enum CollapsedEvent: Identifiable {
    case event(NostrEvent, Highlight)
    case collapsed(Int, String)
    
    var id: String {
        switch self {
        case .event(let ev, _):
            return ev.id
        case .collapsed(_, let id):
            return id
        }
    }
}

struct EventDetailView: View {
    @State var event: NostrEvent

    let sub_id = UUID().description

    @State var events: [NostrEvent] = []
    @State var has_event: [String: ()] = [:]
    @State var collapsed: Bool = true
    
    @EnvironmentObject var profiles: Profiles
    
    let pool: RelayPool

    func unsubscribe_to_thread() {
        print("unsubscribing from thread \(event.id) with sub_id \(sub_id)")
        self.pool.remove_handler(sub_id: sub_id)
        self.pool.send(.unsubscribe(sub_id))
    }

    func subscribe_to_thread() {
        var ref_events = NostrFilter.filter_text
        var events = NostrFilter.filter_text

        // TODO: add referenced relays
        ref_events.referenced_ids = event.referenced_ids.map { $0.ref_id }
        ref_events.referenced_ids!.append(event.id)

        events.ids = ref_events.referenced_ids!

        print("subscribing to thread \(event.id) with sub_id \(sub_id)")
        pool.register_handler(sub_id: sub_id, handler: handle_event)
        pool.send(.subscribe(.init(filters: [ref_events, events], sub_id: sub_id)))
    }
    
    func add_event(ev: NostrEvent) {
        if sub_id != self.sub_id || self.has_event[ev.id] != nil {
            return
        }
        self.add_event(ev)
    }

    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            break
        case .nostr_event(let res):
            switch res {
            case .event(let sub_id, let ev):
                if sub_id == self.sub_id {
                    add_event(ev: ev)
                }
                
            case .notice(let note):
                if note.contains("Too many subscription filters") {
                    // TODO: resend filters?
                    pool.reconnect(to: [relay_id])
                }
                break
            }
        }
    }
    
    func toggle_collapse_thread(scroller: ScrollViewProxy, id: String) {
        self.collapsed = !self.collapsed
        if !self.collapsed {
            scroll_to_event(scroller: scroller, id: id, delay: 0.1)
        }
    }
    
    func scroll_to_event(scroller: ScrollViewProxy, id: String, delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation {
                scroller.scrollTo(event.id)
            }
        }
    }
    
    func OurEventView(proxy: ScrollViewProxy, ev: NostrEvent, highlight: Highlight) -> some View {
        Group {
            if ev.id == event.id {
                EventView(event: ev, highlight: .main, has_action_bar: true)
                    .onAppear() {
                        scroll_to_event(scroller: proxy, id: ev.id, delay: 0.5)
                    }
                    .onTapGesture {
                        toggle_collapse_thread(scroller: proxy, id: ev.id)
                    }
            } else {
                if !(self.collapsed && highlight.is_none) {
                    EventView(event: ev, highlight: collapsed ? .none : highlight, has_action_bar: true)
                        .onTapGesture {
                            if !collapsed {
                                toggle_collapse_thread(scroller: proxy, id: ev.id)
                            }
                            self.event = ev
                        }
                }
            }
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ForEach(calculated_collapsed_events(collapsed: self.collapsed, active: self.event, events: self.events), id: \.id) { cev in
                    switch cev {
                    case .collapsed(let i, _):
                        Text("··· \(i) notes hidden ···")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    case .event(let ev, let highlight):
                        OurEventView(proxy: proxy, ev: ev, highlight: highlight)
                    }
                }
            }
            .padding()
            .onDisappear() {
                unsubscribe_to_thread()
            }
            .onAppear() {
                self.add_event(event)
                subscribe_to_thread()
                
            }
        }

    }

    func add_event(_ ev: NostrEvent) {
        if self.has_event[ev.id] == nil {
            self.has_event[ev.id] = ()
            self.events.append(ev)
            self.events = self.events.sorted { $0.created_at < $1.created_at }
        }
    }
}

/*
struct EventDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EventDetailView(event: NostrEvent(content: "Hello", pubkey: "Guy"), profile: nil)
    }
}
 */

func determine_highlight(current: NostrEvent, active: NostrEvent) -> Highlight
{
    if current.id == active.id {
        return .main
    }
    if active.references(id: current.id, key: "e") {
        return .replied_to(active.id)
    } else if current.references(id: active.id, key: "e") {
        return .replied_to(current.id)
    }
    return .none
}

func calculated_collapsed_events(collapsed: Bool, active: NostrEvent, events: [NostrEvent]) -> [CollapsedEvent] {
    var count: Int = 0
    
    if !collapsed {
        return events.reduce(into: []) { acc, ev in
            let highlight = determine_highlight(current: ev, active: active)
            return acc.append(.event(ev, highlight))
        }
    }
    
    return events.reduce(into: []) { (acc, ev) in
        let highlight = determine_highlight(current: ev, active: active)
        
        switch highlight {
        case .none:
            count += 1
        case .main:
            if count != 0 {
                acc.append(.collapsed(count, UUID().description))
                count = 0
            }
            acc.append(.event(ev, .main))
        case .replied_to:
            if count != 0 {
                acc.append(.collapsed(count, UUID().description))
                count = 0
            }
            acc.append(.event(ev, highlight))
        }
        
    }
}

