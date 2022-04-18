//
//  ThreadView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

struct CollapsedEvents: Identifiable {
    let count: Int
    let start: Int
    let end: Int
    
    var id: String = UUID().description
}

enum CollapsedEvent: Identifiable {
    case event(NostrEvent, Highlight)
    case collapsed(CollapsedEvents)

    var id: String {
        switch self {
        case .event(let ev, _):
            return ev.id
        case .collapsed(let c):
            return c.id
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

    func toggle_collapse_thread(scroller: ScrollViewProxy, id mid: String?, animate: Bool = true, anchor: UnitPoint = .center) {
        self.collapsed = !self.collapsed
        if let id = mid {
            if !self.collapsed {
                scroll_to_event(scroller: scroller, id: id, delay: 0.1, animate: animate, anchor: anchor)
            }
        }
    }

    func scroll_to_event(scroller: ScrollViewProxy, id: String, delay: Double, animate: Bool, anchor: UnitPoint = .center) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if animate {
                withAnimation {
                    scroller.scrollTo(id, anchor: anchor)
                }
            } else {
                scroller.scrollTo(id, anchor: anchor)
            }
        }
    }

    func OurEventView(proxy: ScrollViewProxy, ev: NostrEvent, highlight: Highlight, collapsed_events: [CollapsedEvent]) -> some View {
        Group {
            if ev.id == event.id {
                EventView(event: ev, highlight: .main, has_action_bar: true)
                    .onAppear() {
                        scroll_to_event(scroller: proxy, id: ev.id, delay: 0.5, animate: true)
                    }
                    .onTapGesture {
                        let any = any_collapsed(collapsed_events)
                        if (collapsed && any) || (!collapsed && !any) {
                            toggle_collapse_thread(scroller: proxy, id: ev.id)
                        }
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
    
    func uncollapse_section(scroller: ScrollViewProxy, c: CollapsedEvents)
    {
        let ev = events[c.start]
        print("uncollapsing section at \(c.start) '\(ev.content.prefix(12))...'")
        let start_id = ev.id
        
        toggle_collapse_thread(scroller: scroller, id: start_id, animate: true, anchor: .top)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let collapsed_events = calculated_collapsed_events(collapsed: self.collapsed, active: self.event, events: self.events)
                ForEach(collapsed_events, id: \.id) { cev in
                    switch cev {
                    case .collapsed(let c):
                        Text("··· \(c.count) other replies ···")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .onTapGesture {
                                self.uncollapse_section(scroller: proxy, c: c)
                                //self.toggle_collapse_thread(scroller: proxy, id: nil)
                            }
                    case .event(let ev, let highlight):
                        OurEventView(proxy: proxy, ev: ev, highlight: highlight, collapsed_events: collapsed_events)
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

/// Find the entire reply path for the active event
func make_reply_map(active: NostrEvent, events: [NostrEvent]) -> [String: ()]
{
    let event_map: [String: Int] = zip(events,0...events.count).reduce(into: [:]) { (acc, arg1) in
        let (ev, i) = arg1
        acc[ev.id] = i
    }
    var is_reply: [String: ()] = [:]
    var i: Int = 0
    var start: Int = 0
    var iterations: Int = 0

    if events.count == 0 {
        return is_reply
    }
    
    let is_root = active.is_root_event()
    
    for ev in events {
        if is_root && ev.directly_references(active.id) {
            is_reply[ev.id] = ()
            start = i
        } else if !is_root && ev.references(id: active.id, key: "e") {
            is_reply[ev.id] = ()
            start = i
        } else if active.references(id: ev.id, key: "e") {
            is_reply[ev.id] = ()
            start = i
        }
        i += 1
    }

    i = start

    while true {
        if iterations > 1024 {
            // infinite loop? or super large thread
            print("breaking from large reply_map... big thread??")
            break
        }

        let ev = events[i]

        let ref_ids = ev.referenced_ids
        if ref_ids.count == 0 {
            break
        }

        let ref_id = ref_ids[ref_ids.count-1]
        let pubkey = ref_id.ref_id
        is_reply[pubkey] = ()

        if let mi = event_map[pubkey] {
            i = mi
        } else {
            break
        }

        iterations += 1
    }

    return is_reply
}

func determine_highlight(reply_map: [String: ()], current: NostrEvent, active: NostrEvent) -> Highlight
{
    if current.id == active.id {
        return .main
    } else if reply_map[current.id] != nil {
        return .reply
    } else {
        return .none
    }
    
    /*
    if current.id == active.id {
        return .main
    }
    if active.is_root_event() {
        if active.directly_references(current.id) {
            return .reply
        } else if current.directly_references(active.id) {
            return .reply
        }
    } else {
        if active.references(id: current.id, key: "e") {
            return .reply
        } else if current.references(id: active.id, key: "e") {
            return .reply
        }
    }
    
    return .none
     */
}

func calculated_collapsed_events(collapsed: Bool, active: NostrEvent, events: [NostrEvent]) -> [CollapsedEvent] {
    var count: Int = 0

    let reply_map = make_reply_map(active: active, events: events)
    
    if !collapsed {
        return events.reduce(into: []) { acc, ev in
            let highlight = determine_highlight(reply_map: reply_map, current: ev, active: active)
            return acc.append(.event(ev, highlight))
        }
    }

    let nevents = events.count
    var start: Int = 0
    var i: Int = 0
    
    return events.reduce(into: []) { (acc, ev) in
        let highlight = determine_highlight(reply_map: reply_map, current: ev, active: active)

        switch highlight {
        case .none:
            if i == 0 {
                start = 1
            }
            count += 1
        case .main: fallthrough
        case .reply:
            if count != 0 {
                let c = CollapsedEvents(count: count, start: start, end: i)
                acc.append(.collapsed(c))
                start = i
                count = 0
            }
            acc.append(.event(ev, highlight))
        }

        if i == nevents-1 {
            if count != 0 {
                let c = CollapsedEvents(count: count, start: i-count, end: i)
                acc.append(.collapsed(c))
                count = 0
            }
        }

        i += 1
    }
}



func any_collapsed(_ evs: [CollapsedEvent]) -> Bool {
    for ev in evs {
        switch ev {
        case .collapsed:
            return true
        case .event:
            continue
        }
    }
    return false
}
