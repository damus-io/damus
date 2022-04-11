//
//  ContentView.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import Starscream

let PFP_SIZE: CGFloat? = 64
let CORNER_RADIUS: CGFloat = 32

struct TimestampedProfile {
    let profile: Profile
    let timestamp: Int64
}

struct EventView: View {
    let event: NostrEvent
    let profile: Profile?

    var body: some View {
        HStack {
            if let pic = profile?.picture.flatMap { URL(string: $0) } {
                AsyncImage(url: pic) { img in
                    img.resizable()
                } placeholder: {
                    Color.purple.opacity(0.1)
                }
                .frame(width: PFP_SIZE, height: PFP_SIZE, alignment: .top)
                .cornerRadius(CORNER_RADIUS)
            } else {
                Color.purple.opacity(0.1)
                    .frame(width: PFP_SIZE, height: PFP_SIZE, alignment: .top)
                    .cornerRadius(CORNER_RADIUS)
            }

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
    @State var profiles: [String: TimestampedProfile] = [:]
    @State var has_events: [String: ()] = [:]
    @State var profile_count: Int = 0
    @State var last_event_of_kind: [Int: NostrEvent] = [:]
    @State var loading: Bool = true
    @State var pool: RelayPool? = nil

    var MainContent: some View {
        ScrollView {
            ForEach(events, id: \.id) {
                EventView(event: $0, profile: profiles[$0.pubkey]?.profile)
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
                    PostButton() {
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

        if let mprof = self.profiles[ev.pubkey] {
            if mprof.timestamp > ev.created_at {
                // skip if we already have an newer profile
                return
            }
        }

        self.profiles[ev.pubkey] = TimestampedProfile(profile: profile, timestamp: ev.created_at)
    }

    func send_filters(relay_id: String) {
        // TODO: since times should be based on events from a specific relay
        // perhaps we could mark this in the relay pool somehow

        let last_text_event = last_event_of_kind[NostrKind.text.rawValue]
        let since = get_since_time(last_event: last_text_event)
        var since_filter = NostrFilter.filter_text
        since_filter.since = since

        let last_metadata_event = last_event_of_kind[NostrKind.metadata.rawValue]
        var profile_filter = NostrFilter.filter_profiles
        if let prof_since = get_metadata_since_time(last_metadata_event) {
            profile_filter.since = prof_since
        }

        let filters = [since_filter, profile_filter]
        print("connected to \(relay_id), refreshing from \(since)")
        let sub_id = self.sub_id ?? UUID().description
        if self.sub_id != sub_id {
            self.sub_id = sub_id
        }
        print("subscribing to \(sub_id)")
        self.pool?.send(filters: filters, sub_id: sub_id)
    }

    func handle_event(relay_id: String, conn_event: NostrConnectionEvent) {
        switch conn_event {
        case .ws_event(let ev):
            switch ev {
            case .connected:
                send_filters(relay_id: relay_id)
            case .disconnected: fallthrough
            case .cancelled:
                self.pool?.connect(to: [relay_id])
            case .reconnectSuggested(let t):
                if t {
                    self.pool?.connect(to: [relay_id])
                }
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

                if has_events[ev.id] == nil {
                    has_events[ev.id] = ()
                    let last_k = last_event_of_kind[ev.kind]
                    if last_k == nil || ev.created_at > last_k!.created_at {
                        last_event_of_kind[ev.kind] = ev
                    }
                    if ev.kind == 1 {
                        self.events.append(ev)
                        self.events = self.events.sorted { $0.created_at > $1.created_at }
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



func get_metadata_since_time(_ metadata_event: NostrEvent?) -> Int64? {
    if metadata_event == nil {
        return nil
    }

    return metadata_event!.created_at - 60 * 10
}

func get_since_time(last_event: NostrEvent?) -> Int64 {
    if last_event == nil {
        return Int64(Date().timeIntervalSince1970) - (24 * 60 * 60 * 3)
    }

    return last_event!.created_at - 60 * 10
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

