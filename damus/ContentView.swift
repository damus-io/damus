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
    case reply(NostrEvent)

    var id: String {
        switch self {
        case .post: return "post"
        case .reply(let ev): return "reply-" + ev.id
        }
    }
}

enum ThreadState {
    case event_details
    case chatroom
}

enum Timeline: String, CustomStringConvertible {
    case home
    case notifications
    case global
    
    var description: String {
        return self.rawValue
    }
}

struct ContentView: View {
    @State var status: String = "Not connected"
    @State var active_sheet: Sheets? = nil
    @State var profiles: Profiles = Profiles()
    @State var friends: [String: ()] = [:]
    @State var loading: Bool = true
    @State var damus: DamusState? = nil
    @State var selected_timeline: Timeline? = .home
    @State var is_thread_open: Bool = false
    @State var is_profile_open: Bool = false
    @State var last_event_of_kind: [String: [Int: NostrEvent]] = [:]
    @State var has_events: [String: ()] = [:]
    @State var has_friend_event: [String: ()] = [:]
    @State var new_notifications: Bool = false
    @State var event: NostrEvent? = nil
    @State var events: [NostrEvent] = []
    @State var friend_events: [NostrEvent] = []
    @State var notifications: [NostrEvent] = []
    @State var active_profile: String? = nil
    @State var active_event_id: String? = nil
    @State var profile_open: Bool = false
    @State var thread_open: Bool = false
    
    // connect retry timer
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    let sub_id = UUID().description
    let pubkey = MY_PUBKEY
    let privkey = MY_PRIVKEY 
    
    var NotificationTab: some View {
        ZStack(alignment: .center) {
            Button(action: {switch_timeline(.notifications)}) {
                Label("", systemImage: selected_timeline == .notifications ? "bell.fill" : "bell")
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, minHeight: 30.0)
            }
            .foregroundColor(selected_timeline != .notifications ? .gray : .primary)
            
            if new_notifications {
                Circle()
                    .size(CGSize(width: 8, height: 8))
                    .frame(width: 10, height: 10, alignment: .topTrailing)
                    .alignmentGuide(VerticalAlignment.center) { a in a.height + 2.0 }
                    .alignmentGuide(HorizontalAlignment.center) { a in a.width - 12.0 }
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    func TabButton(timeline: Timeline, img: String) -> some View {
        Button(action: {switch_timeline(timeline)}) {
            Label("", systemImage: selected_timeline == timeline ? "\(img).fill" : img)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: 30.0)
        }
        .foregroundColor(selected_timeline != timeline ? .gray : .primary)
    }
    
    var TabBar: some View {
        VStack {
            Divider()
            HStack {
                TabButton(timeline: .home, img: "house")
                NotificationTab
                TabButton(timeline: .global, img: "globe.americas")
            }
        }
    }

    var LoadingContainer: some View {
        VStack {
            HStack {
                Spacer()
        
                if self.loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }

            Spacer()
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
    
    var PostingTimelineView: some View {
        ZStack {
            if let damus = self.damus {
                TimelineView(events: $friend_events, damus: damus)
                    .environmentObject(profiles)
            }
            PostButtonContainer
        }
    }
    
    func MainContent(damus: DamusState) -> some View {
        NavigationView {
            VStack {
                NavigationLink(destination: MaybeProfileView, isActive: $profile_open) {
                    EmptyView()
                }
                NavigationLink(destination: MaybeThreadView, isActive: $thread_open) {
                    EmptyView()
                }
                switch selected_timeline {
                case .home:
                    PostingTimelineView
                        .onAppear() {
                            //switch_timeline(.home)
                        }
                    
                case .notifications:
                    TimelineView(events: $notifications, damus: damus)
                        .environmentObject(profiles)
                        .navigationTitle("Notifications")
                
                case .global:
                    
                    TimelineView(events: $events, damus: damus)
                        .environmentObject(profiles)
                        .navigationTitle("Global")
                case .none:
                    EmptyView()
                }
            }
            .navigationBarTitle("Damus", displayMode: .inline)
                            
        }
        .navigationViewStyle(.stack)
    }
    
    var MaybeThreadView: some View {
        Group {
            if let evid = self.active_event_id {
                let thread_model = ThreadModel(evid: evid, pool: damus!.pool)
                ThreadView(thread: thread_model, damus: damus!)
                    .environmentObject(profiles)
            } else {
                EmptyView()
            }
        }
    }
    
    var MaybeProfileView: some View {
        Group {
            if let pk = self.active_profile {
                let profile_model = ProfileModel(pubkey: pk, damus: damus!)
                ProfileView(damus: damus!, profile: profile_model)
                    .environmentObject(profiles)
            } else {
                EmptyView()
            }
        }
    }
    
    var body: some View {
        VStack {
            if let damus = self.damus {
                ZStack {
                    MainContent(damus: damus)
                        .padding([.bottom], -8.0)
                    
                    LoadingContainer
                }
            }
            
            TabBar
        }
        .onAppear() {
            self.connect()
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .post:
                PostView(references: [])
            case .reply(let event):
                ReplyView(replying_to: event, damus: damus!)
                    .environmentObject(profiles)
            }
        }
        .onOpenURL { url in
            guard let link = decode_nostr_uri(url.absoluteString) else {
                return
            }
            
            switch link {
            case .ref(let ref):
                if ref.key == "p" {
                    active_profile = ref.ref_id
                    profile_open = true
                } else if ref.key == "e" {
                    active_event_id = ref.ref_id
                    thread_open = true
                }
            case .filter:
                break
                // TODO: handle filter searches?
            }
            
        }
        .onReceive(handle_notify(.boost)) { notif in
            let ev = notif.object as! NostrEvent
            let boost = make_boost_event(ev, privkey: privkey, pubkey: pubkey)
            self.damus?.pool.send(.event(boost))
        }
        .onReceive(handle_notify(.open_thread)) { obj in
            //let ev = obj.object as! NostrEvent
            //thread.set_active_event(ev)
            //is_thread_open = true
        }
        .onReceive(handle_notify(.reply)) { notif in
            let ev = notif.object as! NostrEvent
            self.active_sheet = .reply(ev)
        }
        .onReceive(handle_notify(.like)) { like in
            let ev = like.object as! NostrEvent
            guard let like_ev = make_like_event(pubkey: pubkey, liked: ev) else {
                return
            }
            like_ev.calculate_id()
            like_ev.sign(privkey: privkey)
            self.damus?.pool.send(.event(like_ev))
        }
        .onReceive(handle_notify(.broadcast_event)) { obj in
            let ev = obj.object as! NostrEvent
            self.damus?.pool.send(.event(ev))
        }
        .onReceive(handle_notify(.post)) { obj in
            let post_res = obj.object as! NostrPostResult
            switch post_res {
            case .post(let post):
                print("post \(post.content)")
                let new_ev = post_to_event(post: post, privkey: privkey, pubkey: pubkey)
                self.damus?.pool.send(.event(new_ev))
            case .cancel:
                active_sheet = nil
                print("post cancelled")
            }
        }
        .onReceive(timer) { n in
            self.damus?.pool.connect_to_disconnected()
            self.loading = (self.damus?.pool.num_connecting ?? 0) != 0
        }
    }
    
    func is_friend(pubkey: String) -> Bool {
        return pubkey == self.pubkey || friends[pubkey] != nil
    }
    
    func is_friend_event(_ ev: NostrEvent) -> Bool {
        if is_friend(pubkey: ev.pubkey) {
            return true
        }
        
        if ev.is_reply {
            // show our replies?
            if ev.pubkey == self.pubkey {
                return true
            }
            for pk in ev.referenced_pubkeys {
                if is_friend(pubkey: pk.ref_id) {
                    return true
                }
            }
        }
        
        return false
    }

    func switch_timeline(_ timeline: Timeline) {
        if timeline == self.selected_timeline {
            NotificationCenter.default.post(name: .scroll_to_top, object: nil)
            return
        }
        
        if (timeline != .notifications && self.selected_timeline == .notifications) || timeline == .notifications {
            new_notifications = false
        }
        self.selected_timeline = timeline
        NotificationCenter.default.post(name: .switched_timeline, object: timeline)
        //self.selected_timeline = timeline
    }
    
    func add_relay(_ pool: RelayPool, _ relay: String) {
        //add_rw_relay(pool, "wss://nostr-pub.wellorder.net")
        add_rw_relay(pool, relay)
        let profile = Profile(name: relay, about: nil, picture: nil)
        let ts = Int64(Date().timeIntervalSince1970)
        let tsprofile = TimestampedProfile(profile: profile, timestamp: ts)
        self.profiles.add(id: relay, profile: tsprofile)
    }

    func connect() {
        let pool = RelayPool()

        add_relay(pool, "wss://nostr-pub.wellorder.net")
        add_relay(pool, "wss://nostr.onsats.org")
        add_relay(pool, "wss://nostr.bitcoiner.social")
        add_relay(pool, "ws://monad.jb55.com:8080")
        add_relay(pool, "wss://nostr-relay.freeberty.net")
        add_relay(pool, "wss://nostr-relay.untethr.me")

        pool.register_handler(sub_id: sub_id, handler: handle_event)

        self.damus = DamusState(pool: pool, pubkey: pubkey,
                                likes: EventCounter(our_pubkey: pubkey),
                                boosts: EventCounter(our_pubkey: pubkey),
                                image_cache: ImageCache()
        )
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
    
    func handle_boost_event(_ ev: NostrEvent) {
        damus!.boosts.add_event(ev)
    }
    
    func handle_like_event(_ ev: NostrEvent) {
        guard let e = ev.last_refid() else {
            // no id ref? invalid like event
            return
        }
        
        // CHECK SIGS ON THESE
        
        switch damus!.likes.add_event(ev) {
        case .user_already_liked:
            break
        case .success(let n):
            let liked = Liked(like: ev, id: e.ref_id, total: n)
            notify(.liked, liked)
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
    
    func get_last_event_of_kind(relay_id: String, kind: Int) -> NostrEvent? {
        guard let m = last_event_of_kind[relay_id] else {
            last_event_of_kind[relay_id] = [:]
            return nil
        }
        
        return m[kind]
    }
    
    func send_filters(relay_id: String) {
        // TODO: since times should be based on events from a specific relay
        // perhaps we could mark this in the relay pool somehow
        let last_text_event = get_last_event_of_kind(relay_id: relay_id, kind: NostrKind.text.rawValue)
        let since = get_since_time(last_event: last_text_event)
        var since_filter = NostrFilter.filter_kinds([1,5,6])
        since_filter.since = since
        
        let last_like_event = get_last_event_of_kind(relay_id: relay_id, kind: 7)
        var like_filter = NostrFilter.filter_kinds([7])
        like_filter.since = get_since_time(last_event: last_like_event)
        //like_filter.ids = get_like_pow()

        let last_metadata_event = get_last_event_of_kind(relay_id: relay_id, kind: NostrKind.metadata.rawValue)
        var profile_filter = NostrFilter.filter_profiles
        if let prof_since = get_metadata_since_time(last_metadata_event) {
            profile_filter.since = prof_since
        }
        
        /*
        var notification_filter = NostrFilter.filter_text
        notification_filter.since = since
         */

        var contacts_filter = NostrFilter.filter_contacts
        contacts_filter.authors = [self.pubkey]

        let filters = [since_filter, profile_filter, contacts_filter, like_filter]
        print("connected to \(relay_id), refreshing from \(since)")
        self.damus?.pool.send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: [relay_id])
        //self.pool?.send(.subscribe(.init(filters: [notification_filter], sub_id: "notifications")))
    }
    
    func handle_notification(ev: NostrEvent) {
        notifications.append(ev)
        notifications = notifications.sorted { $0.created_at > $1.created_at }
        
        let last_notified = get_last_notified()
        
        if last_notified == nil || last_notified!.created_at < ev.created_at {
            save_last_notified(ev)
            new_notifications = true
        }
    }
    
    func handle_friend_event(_ ev: NostrEvent) {
        if has_friend_event[ev.id] != nil || !is_friend_event(ev) {
            return
        }
        self.has_friend_event[ev.id] = ()
        self.friend_events.append(ev)
        self.friend_events = self.friend_events.sorted { $0.created_at > $1.created_at }
    }
    
    func handle_text_event(_ ev: NostrEvent) {
        if should_hide_event(ev) {
            return
        }
        
        self.events.append(ev)
        self.events = self.events.sorted { $0.created_at > $1.created_at }
        
        handle_friend_event(ev)
        
        if is_notification(ev: ev, pubkey: pubkey) {
            handle_notification(ev: ev)
        }
    }
    
    func process_event(relay_id: String, ev: NostrEvent) {
        if has_events[ev.id] != nil {
            return
        }
        
        has_events[ev.id] = ()
        let last_k = get_last_event_of_kind(relay_id: relay_id, kind: ev.kind)
        if last_k == nil || ev.created_at > last_k!.created_at {
            last_event_of_kind[relay_id]?[ev.kind] = ev
        }
        if ev.kind == 1 {
            handle_text_event(ev)
        } else if ev.kind == 0 {
            handle_metadata_event(ev)
        } else if ev.kind == 7 {
            handle_like_event(ev)
        } else if ev.kind == 3 {
            handle_contact_event(ev)
            
            if ev.pubkey == pubkey {
                process_friend_events()
            }
        }
    }
    
    func process_friend_events() {
        for event in events {
            handle_friend_event(event)
        }
    }
    
    func handle_event(relay_id: String, conn_event: NostrConnectionEvent) {
        switch conn_event {
        case .ws_event(let ev):

            /*
            if let wsev = ws_nostr_event(relay: relay_id, ev: ev) {
                wsev.flags |= 1
                self.events.insert(wsev, at: 0)
            }
             */
            

            switch ev {
            case .connected:
                send_filters(relay_id: relay_id)
            case .error(let merr):
                let desc = merr.debugDescription
                if desc.contains("Software caused connection abort") {
                    self.damus?.pool.reconnect(to: [relay_id])
                }
            case .disconnected: fallthrough
            case .cancelled:
                self.damus?.pool.reconnect(to: [relay_id])
            case .reconnectSuggested(let t):
                if t {
                    self.damus?.pool.reconnect(to: [relay_id])
                }
            default:
                break
            }
            
            self.loading = (self.damus?.pool.num_connecting ?? 0) != 0

            print("ws_event \(ev)")

        case .nostr_event(let ev):
            switch ev {
            case .event(let sub_id, let ev):
                // globally handle likes
                let always_process = ev.known_kind == .like || ev.known_kind == .contacts || ev.known_kind == .metadata
                if !always_process && sub_id != self.sub_id {
                    // TODO: other views like threads might have their own sub ids, so ignore those events... or should we?
                    return
                }
                
                self.process_event(relay_id: relay_id, ev: ev)
            case .notice(let msg):
                self.events.insert(NostrEvent(content: "NOTICE from \(relay_id): \(msg)", pubkey: "system"), at: 0)
                print(msg)
            }
        }
    }

    func should_hide_event(_ ev: NostrEvent) -> Bool {
        return false
    }
}

/*
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
 */


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

func is_notification(ev: NostrEvent, pubkey: String) -> Bool {
    if ev.pubkey == pubkey {
        return false
    }
    return ev.references(id: pubkey, key: "p")
}


extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}

struct LastNotification {
    let id: String
    let created_at: Int64
}

func get_last_notified() -> LastNotification? {
    let last = UserDefaults.standard.string(forKey: "last_notification")
    let last_created = UserDefaults.standard.string(forKey: "last_notification_time")
        .flatMap { Int64($0) }
    
    return last.flatMap { id in
        last_created.map { created in
            return LastNotification(id: id, created_at: created)
        }
    }
}

func save_last_notified(_ ev: NostrEvent) {
    UserDefaults.standard.set(ev.id, forKey: "last_notification")
    UserDefaults.standard.set(String(ev.created_at), forKey: "last_notification_time")
}



func make_boost_event(_ ev: NostrEvent, privkey: String, pubkey: String) -> NostrEvent {
    let boost = NostrEvent(content: "", pubkey: pubkey, kind: 6, tags: [["e", ev.id]])
    boost.calculate_id()
    boost.sign(privkey: privkey)
    return boost
}


func get_like_pow() -> [String] {
    return ["00000"] // 20 bits
}
