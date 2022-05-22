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

struct ContentView: View {
    let pubkey: String
    let privkey: String
    @State var status: String = "Not connected"
    @State var active_sheet: Sheets? = nil
    @State var loading: Bool = true
    @State var damus_state: DamusState? = nil
    @State var selected_timeline: Timeline? = .home
    @State var is_thread_open: Bool = false
    @State var is_profile_open: Bool = false
    @State var last_event_of_kind: [String: [Int: NostrEvent]] = [:]
    @State var has_events: [String: ()] = [:]
    @State var new_notifications: Bool = false
    @State var event: NostrEvent? = nil
    @State var events: [NostrEvent] = []
    @State var friend_events: [NostrEvent] = []
    @State var notifications: [NostrEvent] = []
    @State var active_profile: String? = nil
    @State var active_search: NostrFilter? = nil
    @State var active_event_id: String? = nil
    @State var profile_open: Bool = false
    @State var thread_open: Bool = false
    @State var search_open: Bool = false
    
    // connect retry timer
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    let sub_id = UUID().description
    
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

    var PostingTimelineView: some View {
        ZStack {
            if let damus = self.damus_state {
                TimelineView(events: $friend_events, damus: damus)
            }
            PostButtonContainer {
                self.active_sheet = .post
            }
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
                NavigationLink(destination: MaybeSearchView, isActive: $search_open) {
                    EmptyView()
                }
                switch selected_timeline {
                case .search:
                    SearchHomeView()
                    
                case .home:
                    PostingTimelineView
                    
                case .notifications:
                    TimelineView(events: $notifications, damus: damus)
                        .navigationTitle("Notifications")
                
                case .global:
                    
                    TimelineView(events: $events, damus: damus)
                        .navigationTitle("Global")
                case .none:
                    EmptyView()
                }
            }
            .navigationBarTitle("Damus", displayMode: .inline)
                            
        }
        .navigationViewStyle(.stack)
    }
    
    var MaybeSearchView: some View {
        Group {
            if let search = self.active_search {
                SearchView(appstate: damus_state!, search: SearchModel(pool: damus_state!.pool, search: search))
            } else {
                EmptyView()
            }
        }
    }
    
    var MaybeThreadView: some View {
        Group {
            if let evid = self.active_event_id {
                let thread_model = ThreadModel(evid: evid, pool: damus_state!.pool)
                ThreadView(thread: thread_model, damus: damus_state!)
            } else {
                EmptyView()
            }
        }
    }
    
    var MaybeProfileView: some View {
        Group {
            if let pk = self.active_profile {
                let profile_model = ProfileModel(pubkey: pk, damus: damus_state!)
                ProfileView(damus_state: damus_state!, profile: profile_model)
            } else {
                EmptyView()
            }
        }
    }
    
    var body: some View {
        VStack {
            if let damus = self.damus_state {
                ZStack {
                    MainContent(damus: damus)
                        .padding([.bottom], -8.0)
                    
                    LoadingContainer
                }
            }
            
            TabBar(new_notifications: $new_notifications, selected: $selected_timeline, action: switch_timeline)
        }
        .onAppear() {
            self.connect()
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .post:
                PostView(references: [])
            case .reply(let event):
                ReplyView(replying_to: event, damus: damus_state!)
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
            case .filter(let filt):
                active_search = filt
                search_open = true
                break
                // TODO: handle filter searches?
            }
            
        }
        .onReceive(handle_notify(.boost)) { notif in
            let ev = notif.object as! NostrEvent
            let boost = make_boost_event(pubkey: pubkey, privkey: privkey, boosted: ev)
            self.damus_state?.pool.send(.event(boost))
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
            let like_ev = make_like_event(pubkey: pubkey, privkey: privkey, liked: ev)
            self.damus_state?.pool.send(.event(like_ev))
        }
        .onReceive(handle_notify(.broadcast_event)) { obj in
            let ev = obj.object as! NostrEvent
            self.damus_state?.pool.send(.event(ev))
        }
        .onReceive(handle_notify(.unfollow)) { notif in
            let pk = notif.object as! String
            guard let damus = self.damus_state else {
                return
            }
            
            if unfollow_user(pool: damus.pool,
                             our_contacts: damus.contacts.event,
                             pubkey: damus.pubkey,
                             privkey: privkey,
                             unfollow: pk) {
                notify(.unfollowed, pk)
                damus.contacts.friends.remove(pk)
                //friend_events = friend_events.filter { $0.pubkey != pk }
            }
        }
        .onReceive(handle_notify(.follow)) { notif in
            let pk = notif.object as! String
            guard let damus = self.damus_state else {
                return
            }
            
            if follow_user(pool: damus.pool,
                           our_contacts: damus.contacts.event,
                           pubkey: damus.pubkey,
                           privkey: privkey,
                           follow: ReferencedId(ref_id: pk, relay_id: nil, key: "p")) {
                notify(.followed, pk)
                damus.contacts.friends.insert(pk)
            }
        }
        .onReceive(handle_notify(.post)) { obj in
            let post_res = obj.object as! NostrPostResult
            switch post_res {
            case .post(let post):
                print("post \(post.content)")
                let new_ev = post_to_event(post: post, privkey: privkey, pubkey: pubkey)
                self.damus_state?.pool.send(.event(new_ev))
            case .cancel:
                active_sheet = nil
                print("post cancelled")
            }
        }
        .onReceive(timer) { n in
            self.damus_state?.pool.connect_to_disconnected()
            self.loading = (self.damus_state?.pool.num_connecting ?? 0) != 0
        }
    }
    
    func is_friend_event(_ ev: NostrEvent) -> Bool {
        return damus.is_friend_event(ev, our_pubkey: self.pubkey, friends: self.damus_state!.contacts.friends)
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
        /*
        let profile = Profile(name: relay, about: nil, picture: nil)
        let ts = Int64(Date().timeIntervalSince1970)
        let tsprofile = TimestampedProfile(profile: profile, timestamp: ts)
        damus!.profiles.add(id: relay, profile: tsprofile)
         */
    }

    func connect() {
        let pool = RelayPool()

        add_relay(pool, "wss://relay.damus.io")
        add_relay(pool, "wss://nostr-pub.wellorder.net")
        add_relay(pool, "wss://nostr.onsats.org")
        add_relay(pool, "wss://nostr.bitcoiner.social")
        add_relay(pool, "ws://monad.jb55.com:8080")
        add_relay(pool, "wss://nostr-relay.freeberty.net")
        add_relay(pool, "wss://nostr-relay.untethr.me")

        pool.register_handler(sub_id: sub_id, handler: handle_event)

        self.damus_state = DamusState(pool: pool, pubkey: pubkey,
                                likes: EventCounter(our_pubkey: pubkey),
                                boosts: EventCounter(our_pubkey: pubkey),
                                contacts: Contacts(),
                                tips: TipCounter(our_pubkey: pubkey),
                                image_cache: ImageCache(),
                                profiles: Profiles()
        )
        pool.connect()
    }

    func handle_contact_event(_ ev: NostrEvent) {
        if ev.pubkey == self.pubkey {
            damus_state!.contacts.event = ev
            // our contacts
            for tag in ev.tags {
                if tag.count > 1 && tag[0] == "p" {
                    damus_state!.contacts.friends.insert(tag[1])
                }
            }
        }
    }
    
    func handle_boost_event(_ ev: NostrEvent) {
        var boost_ev_id = ev.last_refid()?.ref_id
        
        // CHECK SIGS ON THESE
        if let inner_ev = ev.inner_event {
            boost_ev_id = inner_ev.id
            
            if inner_ev.kind == 1 {
                handle_text_event(ev)
            }
        }
        
        guard let e = boost_ev_id else {
            return
        }
        
        switch damus_state!.boosts.add_event(ev, target: e) {
        case .already_counted:
            break
        case .success(let n):
            let boosted = Counted(event: ev, id: e, total: n)
            notify(.boosted, boosted)
        }
    }
    
    func handle_like_event(_ ev: NostrEvent) {
        guard let e = ev.last_refid() else {
            // no id ref? invalid like event
            return
        }
        
        // CHECK SIGS ON THESE
        
        switch damus_state!.likes.add_event(ev, target: e.ref_id) {
        case .already_counted:
            break
        case .success(let n):
            let liked = Counted(event: ev, id: e.ref_id, total: n)
            notify(.liked, liked)
        }
    }
    
    func handle_metadata_event(_ ev: NostrEvent) {
        guard let profile: Profile = decode_data(Data(ev.content.utf8)) else {
            return
        }

        if let mprof = damus_state!.profiles.lookup_with_timestamp(id: ev.pubkey) {
            if mprof.timestamp > ev.created_at {
                // skip if we already have an newer profile
                return
            }
        }

        let tprof = TimestampedProfile(profile: profile, timestamp: ev.created_at)
        damus_state!.profiles.add(id: ev.pubkey, profile: tprof)
        
        notify(.profile_updated, ProfileUpdate(pubkey: ev.pubkey, profile: profile))
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
        let text_filter = NostrFilter.filter_kinds([1,5,6,7])
        let profile_filter = NostrFilter.filter_profiles
        var contacts_filter = NostrFilter.filter_contacts
        
        contacts_filter.authors = [self.pubkey]

        var filters = [text_filter, profile_filter, contacts_filter]

        filters = update_filters_with_since(last_of_kind: last_event_of_kind[relay_id] ?? [:], filters: filters)
        
        print("connected to \(relay_id) with filters:")
        for filter in filters {
            print(filter)
        }
        print("-----")
        
        self.damus_state?.pool.send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: [relay_id])
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
        if !is_friend_event(ev) {
            return
        }
        if !insert_uniq_sorted_event(events: &self.friend_events, new_ev: ev, cmp: { $0.created_at > $1.created_at } ) {
            return
        }
    }
    
    func handle_text_event(_ ev: NostrEvent) {
        if should_hide_event(ev) {
            return
        }
        
        if !insert_uniq_sorted_event(events: &self.events, new_ev: ev, cmp: { $0.created_at > $1.created_at }) {
            return
        }
        
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
        } else if ev.kind == 6 {
            handle_boost_event(ev)
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
                    self.damus_state?.pool.reconnect(to: [relay_id])
                }
            case .disconnected: fallthrough
            case .cancelled:
                self.damus_state?.pool.reconnect(to: [relay_id])
            case .reconnectSuggested(let t):
                if t {
                    self.damus_state?.pool.reconnect(to: [relay_id])
                }
            default:
                break
            }
            
            self.loading = (self.damus_state?.pool.num_connecting ?? 0) != 0

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


func get_like_pow() -> [String] {
    return ["00000"] // 20 bits
}


func update_filters_with_since(last_of_kind: [Int: NostrEvent], filters: [NostrFilter]) -> [NostrFilter] {
    
    return filters.map { filter in
        let kinds = filter.kinds ?? []
        let initial: Int64? = nil
        let earliest = kinds.reduce(initial) { earliest, kind in
            let last = last_of_kind[kind]
            var since: Int64? = nil
            
            if kind == 0 {
                since = get_metadata_since_time(last)
            } else {
                since = get_since_time(last_event: last)
            }
            
            if earliest == nil {
                if since == nil {
                    return nil
                }
                return since
            }
            
            return since! < earliest! ? since! : earliest!
        }
        
        if let earliest = earliest {
            var with_since = NostrFilter.copy(from: filter)
            with_since.since = earliest
            return with_since
        }
        
        return filter
    }
}

