//
//  ThreadView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

struct EventDetailView: View {
    let event: NostrEvent

    let sub_id = UUID().description

    @State var events: [NostrEvent] = []
    @State var has_event: [String: ()] = [:]
    
    @EnvironmentObject var profiles: Profiles
    
    let pool: RelayPool

    func unsubscribe_to_thread() {
        print("unsubscribing from thread \(event.id) with sub_id \(sub_id)")
        self.pool.send(.unsubscribe(sub_id))
        self.pool.remove_handler(sub_id: sub_id)
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


    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            break
        case .nostr_event(let res):
            switch res {
            case .event(let sub_id, let ev):
                if sub_id != self.sub_id || self.has_event[ev.id] != nil {
                    return
                }
                self.add_event(ev)

            case .notice(_):
                // TODO: handle notices in threads?
                break
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ForEach(events, id: \.id) { ev in
                    let is_active_id = ev.id == event.id
                    if is_active_id {
                        EventView(event: ev, highlighted: is_active_id, has_action_bar: true)
                            .onAppear() {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation {
                                        proxy.scrollTo(event.id)
                                    }
                                }
                            }
                    } else {
                        let evdet = EventDetailView(event: ev, pool: pool)
                            .navigationBarTitle("Note")
                            .environmentObject(profiles)
                        
                        NavigationLink(destination: evdet) {
                            EventView(event: ev, highlighted: is_active_id, has_action_bar: true)
                        }
                        .buttonStyle(PlainButtonStyle())
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
