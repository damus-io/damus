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
    let sub_id = UUID().description
    let damus: DamusState
    
    @StateObject var thread: ThreadModel
    @State var collapsed: Bool = true
    
    func toggle_collapse_thread(scroller: ScrollViewProxy, id mid: String?, animate: Bool = true) {
        self.collapsed = !self.collapsed
        if let id = mid {
            if !self.collapsed {
                scroll_to_event(scroller: scroller, id: id, delay: 0.1, animate: animate)
            }
        }
    }
    
    func uncollapse_section(scroller: ScrollViewProxy, c: CollapsedEvents)
    {
        let ev = thread.events[c.start]
        print("uncollapsing section at \(c.start) '\(ev.content.prefix(12))...'")
        let start_id = ev.id
        
        toggle_collapse_thread(scroller: scroller, id: start_id, animate: false)
    }
    
    func CollapsedEventView(_ cev: CollapsedEvent, scroller: ScrollViewProxy) -> some View {
        Group {
            switch cev {
            case .collapsed(let c):
                Text("··· \(c.count) other notes ···")
                    .padding([.top,.bottom], 8)
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .onTapGesture {
                        //self.uncollapse_section(scroller: proxy, c: c)
                        //self.toggle_collapse_thread(scroller: proxy, id: nil)
                        if let ev = thread.events[safe: c.start] {
                            thread.set_active_event(ev, privkey: damus.keypair.privkey)
                        }
                        toggle_thread_view()
                    }
            case .event(let ev, let highlight):
                EventView(event: ev, highlight: highlight, has_action_bar: true, damus: damus, show_friend_icon: true)
                    .onTapGesture {
                        if thread.initial_event.id == ev.id {
                            toggle_thread_view()
                        } else {
                            thread.set_active_event(ev, privkey: damus.keypair.privkey)
                        }
                    }
            }
        }
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            if thread.loading {
                ProgressView().progressViewStyle(.circular)
            }
            
            ScrollView(.vertical) {
                LazyVStack {
                    let collapsed_events = calculated_collapsed_events(
                        privkey: damus.keypair.privkey,
                        collapsed: self.collapsed,
                        active: thread.event,
                        events: thread.events
                    )
                    ForEach(collapsed_events, id: \.id) { cev in
                        CollapsedEventView(cev, scroller: proxy)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                EndBlock()
            }
            .onChange(of: thread.loading) { val in
                scroll_after_load(thread: thread, proxy: proxy)
            }
            .onAppear() {
                scroll_after_load(thread: thread, proxy: proxy)
            }
        }
        .navigationBarTitle("Thread")

    }
    
    func toggle_thread_view() {
        NotificationCenter.default.post(name: .toggle_thread_view, object: nil)
    }
}

func scroll_after_load(thread: ThreadModel, proxy: ScrollViewProxy) {
    if !thread.loading {
        let id = thread.initial_event.id
        scroll_to_event(scroller: proxy, id: id, delay: 0.1, animate: false)
    }
}


struct EventDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        let tm = ThreadModel(evid: "4da698ceac09a16cdb439276fa3d13ef8f6620ffb45d11b76b3f103483c2d0b0", damus_state: state)
        EventDetailView(damus: state, thread: tm)
    }
}

/// Find the entire reply path for the active event
func make_reply_map(active: NostrEvent, events: [NostrEvent], privkey: String?) -> [String: ()]
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
    
    for ev in events {
        /// does this event reply to the active event?
        let ev_refs = ev.event_refs(privkey)
        for ev_ref in ev_refs {
            if let reply = ev_ref.is_reply {
                if reply.ref_id == active.id {
                    is_reply[ev.id] = ()
                    start = i
                }
            }
        }
        
        /// does the active event reply to this event?
        let active_refs = active.event_refs(privkey)
        for active_ref in active_refs {
            if let reply = active_ref.is_reply {
                if reply.ref_id == ev.id {
                    is_reply[ev.id] = ()
                    start = i
                }
            }
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
}

func calculated_collapsed_events(privkey: String?, collapsed: Bool, active: NostrEvent?, events: [NostrEvent]) -> [CollapsedEvent] {
    var count: Int = 0
    
    guard let active = active else {
        return []
    }
    
    let reply_map = make_reply_map(active: active, events: events, privkey: privkey)
    
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
        case .custom: fallthrough
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


func print_event(_ ev: NostrEvent) {
    print(ev.description)
}

func scroll_to_event(scroller: ScrollViewProxy, id: String, delay: Double, animate: Bool) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        if animate {
            withAnimation {
                scroller.scrollTo(id, anchor: .bottom)
            }
        } else {
            scroller.scrollTo(id, anchor: .bottom)
        }
    }
}

extension Collection {

    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
