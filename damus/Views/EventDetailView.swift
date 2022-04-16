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

    let pool: RelayPool
    let profiles: [String: TimestampedProfile]

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

    var NoteBody: some View {
        HStack {
            let profile = profiles[event.pubkey]?.profile

            VStack {
                ProfilePicView(picture: profile?.picture, size: 64, highlighted: false)

                Spacer()
            }

            VStack {
                HStack {
                    ProfileName(pubkey: event.pubkey, profile: profile)
                    Text("\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                    Spacer()
                    PowView(event.pow)
                }
                Text(event.content)
                    .frame(maxWidth: .infinity, alignment: .leading)

                EventActionBar(event: event)

                Divider()
                    .padding([.bottom], 10)
            }
        }
    }

    var body: some View {
        ScrollView {
            ForEach(events, id: \.id) { ev in
                let evdet = EventDetailView(event: ev, pool: pool, profiles: profiles)
                    .navigationBarTitle("Note")
                NavigationLink(destination: evdet) {
                    EventView(event: ev, profile: self.profiles[ev.pubkey]?.profile, highlighted: ev.id == event.id)
                }
                .buttonStyle(PlainButtonStyle())
                //EventView(event: ev, profile: self.profiles[ev.pubkey]?.profile, highlighted: ev.id == event.id)
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
