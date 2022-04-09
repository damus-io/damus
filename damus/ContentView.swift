//
//  ContentView.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import Starscream

struct EventView: View {
    let event: NostrEvent
    let profile: Profile?

    var body: some View {
        VStack {
            Text(String(profile?.name ?? String(event.pubkey.prefix(16))))
                .bold()
                .onTapGesture {
                    UIPasteboard.general.string = event.pubkey
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(event.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        }
    }
}

enum Sheets: Identifiable {
    case post

    var id: String {
        switch self {
        case .post:
            return "post"
        }
    }
}

struct ContentView: View {
    @State var status: String = "Not connected"
    @State var sub_id: String? = nil
    @State var active_sheet: Sheets? = nil
    @State var events: [NostrEvent] = []
    @State var profiles: [String: Profile] = [:]
    @State var has_events: [String: Bool] = [:]
    @State var loading: Bool = true
    @State var pool: RelayPool? = nil

    var MainContent: some View {
        ScrollView {
            ForEach(events.reversed(), id: \.id) {
                EventView(event: $0, profile: profiles[$0.pubkey])
            }
        }
    }

    var body: some View {
        ZStack {
            MainContent
                .padding()
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    PostButton {
                        self.active_sheet = .post
                    }
                }
            }
        }
        .onAppear() {
            self.connect()
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .post:
                PostView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .post)) { obj in
            let post = obj.object as! NostrPost
            print("post \(post.content)")
        }
    }

    func connect() {
        let pool = RelayPool(handle_event: handle_event)

        add_rw_relay(pool, "wss://nostr-pub.wellorder.net")
        add_rw_relay(pool, "wss://nostr-relay.wlvs.space")
        add_rw_relay(pool, "wss://nostr.bitcoiner.social")

        self.pool = pool
        pool.connect()
    }

    func handle_contact_event(_ ev: NostrEvent) {
    }

    func handle_metadata_event(_ ev: NostrEvent) {
        guard let profile: Profile = decode_data(Data(ev.content.utf8)) else {
            return
        }

        self.profiles[ev.pubkey] = profile
    }

    func handle_event(relay_id: String, conn_event: NostrConnectionEvent) {
        switch conn_event {
        case .ws_event(let ev):
            switch ev {
            case .connected:
                // TODO: since times should be based on events from a specific relay
                // perhaps we could mark this in the relay pool somehow

                let since = get_since_time(events: self.events)
                let filter = NostrFilter.filter_since(since)
                print("connected to \(relay_id), refreshing from \(since)")
                let sub_id = self.sub_id ?? UUID().description
                if self.sub_id != sub_id {
                    self.sub_id = sub_id
                }
                print("subscribing to \(sub_id)")
                self.pool?.send(filter: filter, sub_id: sub_id)
            case .cancelled:
                self.pool?.connect(to: [relay_id])
            default:
                break
            }
            print("ws_event \(ev)")

        case .nostr_event(let ev):
            switch ev {
            case .event(_, let ev):
                if self.loading {
                    self.loading = false
                }
                self.sub_id = sub_id

                if !(has_events[ev.id] ?? false) {
                    has_events[ev.id] = true
                    if ev.kind == 1 {
                        self.events.append(ev)
                    } else if ev.kind == 0 {
                        handle_metadata_event(ev)
                    } else if ev.kind == 3 {
                        handle_contact_event(ev)
                    }
                }
            case .notice(let msg):
                print(msg)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

func PostButton(action: @escaping () -> ()) -> some View {
    return Button(action: action, label: {
        Text("+")
            .font(.system(.largeTitle))
            .frame(width: 57, height: 50)
            .foregroundColor(Color.white)
            .padding(.bottom, 7)
    })
    .background(Color.blue)
    .cornerRadius(38.5)
    .padding()
    .shadow(color: Color.black.opacity(0.3),
            radius: 3,
            x: 3,
            y: 3)
}



func get_since_time(events: [NostrEvent]) -> Int64 {
    if events.count == 0 {
        return Int64(Date().timeIntervalSince1970) - (24 * 60 * 60)
    }

    return events.last!.created_at - 60
}

/*
func fetch_profiles(relay: URL, pubkeys: [String]) {
    return NostrFilter(ids: nil, kinds: 3, event_ids: nil, pubkeys: pubkeys, since: nil, until: nil, authors: pubkeys)
}


func nostr_req(relays: [URL], filter: NostrFilter) {
    if relays.count == 0 {
        return
    }
    let conn = NostrConnection(url: relay) {
    }
}


func get_profiles()

*/

func add_rw_relay(_ pool: RelayPool, _ url: String) {
    let url_ = URL(string: url)!
    try! pool.add_relay(url_, info: RelayInfo.rw)
}
