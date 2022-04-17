//
//  ContentView.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import Starscream

struct TimestampedProfile {
    let profile: Profile
    let timestamp: Int64
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

enum Timeline {
    case friends
    case global
    case debug
}

struct ContentView: View {
    @State var status: String = "Not connected"
    @State var active_sheet: Sheets? = nil
    @State var events: [NostrEvent] = []
    @State var profiles: Profiles = Profiles()
    @State var friends: [String: ()] = [:]
    @State var has_events: [String: ()] = [:]
    @State var profile_count: Int = 0
    @State var last_event_of_kind: [Int: NostrEvent] = [:]
    @State var loading: Bool = true
    @State var timeline: Timeline = .friends
    @State var pool: RelayPool? = nil

    let sub_id = UUID().description
    let pubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"

    func MainContent(pool: RelayPool) -> some View {
        ScrollView {
            ForEach(self.events, id: \.id) { (ev: NostrEvent) in
                if ev.is_local && timeline == .debug || (timeline == .global && !ev.is_local) || (timeline == .friends && is_friend(ev.pubkey)) {
                    let evdet = EventDetailView(event: ev, pool: pool)
                        .navigationBarTitle("Thread")
                        .environmentObject(profiles)
                    NavigationLink(destination: evdet) {
                        EventView(event: ev, highlight: .none, has_action_bar: true)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .environmentObject(profiles)
    }

    func TimelineButton(timeline: Timeline, img: String) -> some View {
        Button(action: {switch_timeline(timeline)}) {
            Label("", systemImage: img)
        }
        .frame(maxWidth: .infinity)
        .foregroundColor(self.timeline != timeline ? .gray : .primary)
    }

    func TopBar(selected: Timeline) -> some View {
        HStack {
            TimelineButton(timeline: .friends, img: selected == .friends ? "person.2.fill" : "person.2")
            TimelineButton(timeline: .global, img: selected == .global ? "globe.americas.fill" : "globe.americas")
            TimelineButton(timeline: .debug, img: selected == .debug ? "wrench.fill" : "wrench")
        }
    }

    var PostButtonContainer: some View {
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

    var body: some View {
        NavigationView {
            VStack {
                TopBar(selected: self.timeline)
                ZStack {
                    if let pool = self.pool {
                        MainContent(pool: pool)
                            .padding()
                    }
                    PostButtonContainer
                }
            }
            .navigationBarTitle("Damus", displayMode: .inline)
        }
        .onAppear() {
            self.connect()
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .post:
                PostView(references: [])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .post)) { obj in
            let post = obj.object as! NostrPost
            print("post \(post.content)")
            let privkey = ""
            let new_ev = NostrEvent(content: post.content, pubkey: pubkey)
            for id in post.references {
                new_ev.tags.append(["e", id])
            }
            new_ev.calculate_id()
            new_ev.sign(privkey: privkey)
            self.pool?.send(.event(new_ev))
        }
    }

    func is_friend(_ pubkey: String) -> Bool {
        return pubkey == self.pubkey || self.friends[pubkey] != nil
    }

    func switch_timeline(_ timeline: Timeline) {
        self.timeline = timeline
    }

    func add_relay(_ pool: RelayPool, _ relay: String) {
        //add_rw_relay(pool, "wss://nostr-pub.wellorder.net")
        let wssrelay = "wss://\(relay)"
        add_rw_relay(pool, wssrelay)
        let profile = Profile(name: relay, about: nil, picture: nil)
        let ts = Int64(Date().timeIntervalSince1970)
        let tsprofile = TimestampedProfile(profile: profile, timestamp: ts)
        self.profiles.add(id: wssrelay, profile: tsprofile)
    }

    func connect() {
        let pool = RelayPool()

        add_relay(pool, "nostr-pub.wellorder.net")
        add_relay(pool, "nostr.onsats.org")
        add_relay(pool, "nostr.bitcoiner.social")
        add_relay(pool, "nostr-relay.freeberty.net")
        add_relay(pool, "nostr-relay.untethr.me")

        pool.register_handler(sub_id: sub_id, handler: handle_event)

        self.pool = pool
        pool.connect()
    }

    func handle_contact_event(_ ev: NostrEvent) {
        if ev.pubkey == self.pubkey {
            // our contacts
            for tag in ev.tags {
                if tag.count > 1 && tag[0] == "p" {
                    self.friends[tag[1]] = ()
                }
            }
        }
    }

    func handle_metadata_event(_ ev: NostrEvent) {
        guard let profile: Profile = decode_data(Data(ev.content.utf8)) else {
            return
        }

        if let mprof = self.profiles.lookup_with_timestamp(id: ev.pubkey) {
            if mprof.timestamp > ev.created_at {
                // skip if we already have an newer profile
                return
            }
        }

        let tprof = TimestampedProfile(profile: profile, timestamp: ev.created_at)
        self.profiles.add(id: ev.pubkey, profile: tprof)
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

        var contacts_filter = NostrFilter.filter_contacts
        contacts_filter.authors = [self.pubkey]

        let filters = [since_filter, profile_filter, contacts_filter]
        print("connected to \(relay_id), refreshing from \(since)")
        self.pool?.send(.subscribe(.init(filters: filters, sub_id: sub_id)))
    }

    func handle_event(relay_id: String, conn_event: NostrConnectionEvent) {
        switch conn_event {
        case .ws_event(let ev):

            if let wsev = ws_nostr_event(relay: relay_id, ev: ev) {
                wsev.flags |= 1
                self.events.insert(wsev, at: 0)
            }

            switch ev {
            case .connected:
                send_filters(relay_id: relay_id)
            case .error(let merr):
                let desc = merr.debugDescription
                if desc.contains("Software caused connection abort") {
                    self.pool?.reconnect(to: [relay_id])
                }
            case .disconnected:
                self.pool?.reconnect(to: [relay_id])
            case .cancelled:
                self.pool?.reconnect(to: [relay_id])
            case .reconnectSuggested(let t):
                if t {
                    self.pool?.reconnect(to: [relay_id])
                }
            default:
                break
            }

            print("ws_event \(ev)")

        case .nostr_event(let ev):
            switch ev {
            case .event(let sub_id, let ev):
                if sub_id != self.sub_id {
                    // TODO: other views like threads might have their own sub ids, so ignore those events... or should we?
                    return
                }

                if self.loading {
                    self.loading = false
                }

                if has_events[ev.id] == nil {
                    has_events[ev.id] = ()
                    let last_k = last_event_of_kind[ev.kind]
                    if last_k == nil || ev.created_at > last_k!.created_at {
                        last_event_of_kind[ev.kind] = ev
                    }
                    if ev.kind == 1 {
                        if !should_hide_event(ev) {
                            self.events.append(ev)
                        }
                        self.events = self.events.sorted { $0.created_at > $1.created_at }
                    } else if ev.kind == 0 {
                        handle_metadata_event(ev)
                    } else if ev.kind == 3 {
                        handle_contact_event(ev)
                    }
                }
            case .notice(let msg):
                self.events.insert(NostrEvent(content: "NOTICE from \(relay_id): \(msg)", pubkey: "system"), at: 0)
                print(msg)
            }
        }
    }

    func should_hide_event(_ ev: NostrEvent) -> Bool {
        // TODO: implement mute
        if ev.pubkey == "887645fef0ce0c3c1218d2f5d8e6132a19304cdc57cd20281d082f38cfea0072" {
            return true
        }
        return false
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
        return Int64(Date().timeIntervalSince1970) - (24 * 60 * 60 * 4)
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


func ws_nostr_event(relay: String, ev: WebSocketEvent) -> NostrEvent? {
    switch ev {
    case .binary(let dat):
        return NostrEvent(content: "binary data? \(dat.count) bytes", pubkey: relay)
    case .cancelled:
        return NostrEvent(content: "cancelled", pubkey: relay)
    case .connected:
        return NostrEvent(content: "connected", pubkey: relay)
    case .disconnected:
        return NostrEvent(content: "disconnected", pubkey: relay)
    case .error(let err):
        return NostrEvent(content: "error \(err.debugDescription)", pubkey: relay)
    case .text(let txt):
        return NostrEvent(content: "text \(txt)", pubkey: relay)
    case .pong:
        return NostrEvent(content: "pong", pubkey: relay)
    case .ping:
        return NostrEvent(content: "ping", pubkey: relay)
    case .viabilityChanged(let b):
        return NostrEvent(content: "viabilityChanged \(b)", pubkey: relay)
    case .reconnectSuggested(let b):
        return NostrEvent(content: "reconnectSuggested \(b)", pubkey: relay)
    }
}
