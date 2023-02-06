//
//  ContentView.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import Starscream
import Kingfisher

var BOOTSTRAP_RELAYS = [
    "wss://relay.damus.io",
    "wss://eden.nostr.land",
    "wss://relay.snort.social",
    "wss://nostr.bitcoiner.social",
    "wss://nos.lol",
    "wss://relay.current.fyi",
    "wss://brb.io",
]

struct TimestampedProfile {
    let profile: Profile
    let timestamp: Int64
}

enum Sheets: Identifiable {
    case post
    case report(ReportTarget)
    case reply(NostrEvent)

    var id: String {
        switch self {
        case .report: return "report"
        case .post: return "post"
        case .reply(let ev): return "reply-" + ev.id
        }
    }
}

enum ThreadState {
    case event_details
    case chatroom
}

enum FilterState : Int {
    case posts_and_replies = 1
    case posts = 0
    
    func filter(ev: NostrEvent) -> Bool {
        switch self {
        case .posts:
            return !ev.is_reply(nil)
        case .posts_and_replies:
            return true
        }
    }
}

struct ContentView: View {
    let keypair: Keypair
    
    var pubkey: String {
        return keypair.pubkey
    }
    
    var privkey: String? {
        return keypair.privkey
    }
    
    @State var status: String = "Not connected"
    @State var active_sheet: Sheets? = nil
    @State var damus_state: DamusState? = nil
    @State var selected_timeline: Timeline? = .home
    @State var is_thread_open: Bool = false
    @State var is_deleted_account: Bool = false
    @State var is_profile_open: Bool = false
    @State var event: NostrEvent? = nil
    @State var active_profile: String? = nil
    @State var active_search: NostrFilter? = nil
    @State var active_event_id: String? = nil
    @State var profile_open: Bool = false
    @State var thread_open: Bool = false
    @State var search_open: Bool = false
    @State var blocking: String? = nil
    @State var confirm_block: Bool = false
    @State var user_blocked_confirm: Bool = false
    @State var confirm_overwrite_mutelist: Bool = false
    @State var filter_state : FilterState = .posts_and_replies
    @State private var isSideBarOpened = false
    @StateObject var home: HomeModel = HomeModel()

    // connect retry timer
    let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    let sub_id = UUID().description
    
    @Environment(\.colorScheme) var colorScheme

    var PostingTimelineView: some View {
        VStack {
            ZStack {
                TabView(selection: $filter_state) {
                    contentTimelineView(filter: FilterState.posts.filter)
                        .tag(FilterState.posts)
                        .id(FilterState.posts)
                    contentTimelineView(filter: FilterState.posts_and_replies.filter)
                        .tag(FilterState.posts_and_replies)
                        .id(FilterState.posts_and_replies)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                if privkey != nil {
                    PostButtonContainer(is_left_handed: damus_state?.settings.left_handed ?? false) {
                        self.active_sheet = .post
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(selection: $filter_state, content: {
                    Text("Posts", comment: "Label for filter for seeing only posts (instead of posts and replies).").tag(FilterState.posts)
                    Text("Posts & Replies", comment: "Label for filter for seeing posts and replies (instead of only posts).").tag(FilterState.posts_and_replies)
                })
                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }
    
    func contentTimelineView(filter: (@escaping (NostrEvent) -> Bool)) -> some View {
        ZStack {
            if let damus = self.damus_state {
                TimelineView(events: $home.events, loading: $home.loading, damus: damus, show_friend_icon: false, filter: filter)
            }
        }
    }
    
    func MainContent(damus: DamusState) -> some View {
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
                SearchHomeView(damus_state: damus_state!, model: SearchHomeModel(damus_state: damus_state!))
                
            case .home:
                PostingTimelineView
                
            case .notifications:
                TimelineView(events: $home.notifications, loading: $home.loading, damus: damus, show_friend_icon: true, filter: { _ in true })
                    .navigationTitle(NSLocalizedString("Notifications", comment: "Navigation title for notifications."))
                
            case .dms:
                DirectMessagesView(damus_state: damus_state!)
                    .environmentObject(home.dms)
            
            case .none:
                EmptyView()
            }
        }
        .navigationBarTitle(selected_timeline == .home ?  NSLocalizedString("Home", comment: "Navigation bar title for Home view where posts and replies appear from those who the user is following.") : NSLocalizedString("Global", comment: "Navigation bar title for Global view where posts from all connected relay servers appear."), displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                switch selected_timeline {
                case .home:
                    Image("damus-home")
                    .resizable()
                    .frame(width:30,height:30)
                    .shadow(color: Color("DamusPurple"), radius: 2)
                case .dms:
                    Text("DMs", comment: "Toolbar label for DMs view, where DM is the English abbreviation for Direct Message.")
                        .bold()
                case .notifications:
                    Text("Notifications", comment: "Toolbar label for Notifications view.")
                        .bold()
                case .search:
                    Text("Global", comment: "Toolbar label for Global view where posts from all connected relay servers appear.")
                        .bold()
                case .none:
                    Text("", comment: "Toolbar label for unknown views. This label would be displayed only if a new timeline view is added but a toolbar label was not explicitly assigned to it yet.")
                }
            }
        }
        .ignoresSafeArea(.keyboard)
    }
    
    var MaybeSearchView: some View {
        Group {
            if let search = self.active_search {
                SearchView(appstate: damus_state!, search: SearchModel(contacts: damus_state!.contacts, pool: damus_state!.pool, search: search))
            } else {
                EmptyView()
            }
        }
    }
    
    var MaybeThreadView: some View {
        Group {
            if let evid = self.active_event_id {
                BuildThreadV2View(damus: damus_state!, event_id: evid)
            } else {
                EmptyView()
            }
        }
    }
    
    var MaybeProfileView: some View {
        Group {
            if let pk = self.active_profile {
                let profile_model = ProfileModel(pubkey: pk, damus: damus_state!)
                let followers = FollowersModel(damus_state: damus_state!, target: pk)
                ProfileView(damus_state: damus_state!, profile: profile_model, followers: followers)
            } else {
                EmptyView()
            }
        }
    }
    
    func MaybeReportView(target: ReportTarget) -> some View {
        Group {
            if let ds = damus_state {
                if let sec = ds.keypair.privkey {
                    ReportView(pool: ds.pool, target: target, privkey: sec)
                } else {
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let damus = self.damus_state {
                NavigationView {
                    ZStack {
                        VStack {
                            MainContent(damus: damus)
                                .toolbar() {
                                    ToolbarItem(placement: .navigationBarLeading) {
                                        Button {
                                            isSideBarOpened.toggle()
                                        } label: {
                                            ProfilePicView(pubkey: damus_state!.pubkey, size: 32, highlight: .none, profiles: damus_state!.profiles)
                                        }
                                    }
                                    
                                    ToolbarItem(placement: .navigationBarTrailing) {
                                        HStack(alignment: .center) {
                                            if home.signal.signal != home.signal.max_signal {
                                                NavigationLink(destination: RelayConfigView(state: damus_state!)) {
                                                    Text("\(home.signal.signal)/\(home.signal.max_signal)", comment: "Fraction of how many of the user's relay servers that are operational.")
                                                        .font(.callout)
                                                        .foregroundColor(.gray)
                                                }
                                            }

                                        }
                                    }
                                }

                        }
                        
                        Color.clear
                        .overlay(
                            SideMenuView(damus_state: damus, isSidebarVisible: $isSideBarOpened)
                        )
                    }
                    .navigationBarHidden(isSideBarOpened ? true: false) // Would prefer a different way of doing this.
                }
                .navigationViewStyle(.stack)
            
                TabBar(new_events: $home.new_events, selected: $selected_timeline, isSidebarVisible: $isSideBarOpened, action: switch_timeline)
                    .padding([.bottom], 8)
            }
        }
        .onAppear() {
            self.connect()
            //KingfisherManager.shared.cache.clearDiskCache()
            setup_notifications()
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .report(let target):
                MaybeReportView(target: target)
            case .post:
                PostView(replying_to: nil, references: [], damus_state: damus_state!)
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
            guard let privkey = self.privkey else {
                return
            }
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
        }
        .onReceive(handle_notify(.deleted_account)) { notif in
            self.is_deleted_account = true
        }
        .onReceive(handle_notify(.report)) { notif in
            let target = notif.object as! ReportTarget
            self.active_sheet = .report(target)
        }
        .onReceive(handle_notify(.block)) { notif in
            let pubkey = notif.object as! String
            self.blocking = pubkey
            self.confirm_block = true
        }
        .onReceive(handle_notify(.broadcast_event)) { obj in
            let ev = obj.object as! NostrEvent
            self.damus_state?.pool.send(.event(ev))
        }
        .onReceive(handle_notify(.unfollow)) { notif in
            guard let privkey = self.privkey else {
                return
            }
            
            guard let damus = self.damus_state else {
                return
            }
            
            let target = notif.object as! FollowTarget
            let pk = target.pubkey
            
            if let ev = unfollow_user(pool: damus.pool,
                                      our_contacts: damus.contacts.event,
                                      pubkey: damus.pubkey,
                                      privkey: privkey,
                                      unfollow: pk) {
                notify(.unfollowed, pk)
                
                damus.contacts.event = ev
                damus.contacts.remove_friend(pk)
                //friend_events = friend_events.filter { $0.pubkey != pk }
            }
        }
        .onReceive(handle_notify(.follow)) { notif in
            guard let privkey = self.privkey else {
                return
            }
            
            let fnotify = notif.object as! FollowTarget
            guard let damus = self.damus_state else {
                return
            }
            
            if let ev = follow_user(pool: damus.pool,
                                    our_contacts: damus.contacts.event,
                                    pubkey: damus.pubkey,
                                    privkey: privkey,
                                    follow: ReferencedId(ref_id: fnotify.pubkey, relay_id: nil, key: "p")) {
                notify(.followed, fnotify.pubkey)
                
                damus_state?.contacts.event = ev
                
                switch fnotify {
                case .pubkey(let pk):
                    damus.contacts.add_friend_pubkey(pk)
                case .contact(let ev):
                    damus.contacts.add_friend_contact(ev)
                }
            }
        }
        .onReceive(handle_notify(.post)) { obj in
            guard let privkey = self.privkey else {
                return
            }
            
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
        }
        .onReceive(handle_notify(.new_mutes)) { notif in
            home.filter_muted()
        }
        .alert(NSLocalizedString("Deleted Account", comment: "Alert message to indicate this is a deleted account"), isPresented: $is_deleted_account) {
            Button(NSLocalizedString("Logout", comment: "Button to close the alert that informs that the current account has been deleted.")) {
                is_deleted_account = false
                notify(.logout, ())
            }
        }
        .alert(NSLocalizedString("User blocked", comment: "Alert message to indicate the user has been blocked"), isPresented: $user_blocked_confirm, actions: {
            Button(NSLocalizedString("Thanks!", comment: "Button to close out of alert that informs that the action to block a user was successful.")) {
                user_blocked_confirm = false
            }
        }, message: {
            if let pubkey = self.blocking {
                let profile = damus_state!.profiles.lookup(id: pubkey)
                let name = Profile.displayName(profile: profile, pubkey: pubkey)
                Text("\(name) has been blocked", comment: "Alert message that informs a user was blocked.")
            } else {
                Text("User has been blocked", comment: "Alert message that informs a user was blocked.")
            }
        })
        .alert(NSLocalizedString("Create new mutelist", comment: "Title of alert prompting the user to create a new mutelist."), isPresented: $confirm_overwrite_mutelist, actions: {
            Button(NSLocalizedString("Cancel", comment: "Button to cancel out of alert that creates a new mutelist.")) {
                confirm_overwrite_mutelist = false
                confirm_block = false
            }

            Button(NSLocalizedString("Yes, Overwrite", comment: "Text of button that confirms to overwrite the existing mutelist.")) {
                guard let ds = damus_state else {
                    return
                }
                
                guard let keypair = ds.keypair.to_full() else {
                    return
                }
                
                guard let pubkey = blocking else {
                    return
                }
                
                guard let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: pubkey) else {
                    return
                }
                
                damus_state?.contacts.set_mutelist(mutelist)
                ds.pool.send(.event(mutelist))

                confirm_overwrite_mutelist = false
                confirm_block = false
                user_blocked_confirm = true
            }
        }, message: {
            Text("No block list found, create a new one? This will overwrite any previous block lists.", comment: "Alert message prompt that asks if the user wants to create a new block list, overwriting previous block lists.")
        })
        .alert(NSLocalizedString("Block User", comment: "Title of alert for blocking a user."), isPresented: $confirm_block, actions: {
            Button(NSLocalizedString("Cancel", comment: "Alert button to cancel out of alert for blocking a user."), role: .cancel) {
                confirm_block = false
            }
            Button(NSLocalizedString("Block", comment: "Alert button to block a user."), role: .destructive) {
                guard let ds = damus_state else {
                    return
                }

                if ds.contacts.mutelist == nil {
                    confirm_overwrite_mutelist = true
                } else {
                    guard let keypair = ds.keypair.to_full() else {
                        return
                    }
                    guard let pubkey = blocking else {
                        return
                    }

                    guard let ev = create_or_update_mutelist(keypair: keypair, mprev: ds.contacts.mutelist, to_add: pubkey) else {
                        return
                    }
                    damus_state?.contacts.set_mutelist(ev)
                    ds.pool.send(.event(ev))
                }
            }
        }, message: {
            if let pubkey = blocking {
                let profile = damus_state?.profiles.lookup(id: pubkey)
                let name = Profile.displayName(profile: profile, pubkey: pubkey)
                Text("Block \(name)?", comment: "Alert message prompt to ask if a user should be blocked.")
            } else {
                Text("Could not find user to block...", comment: "Alert message to indicate that the blocked user could not be found.")
            }
        })
    }
    
    func switch_timeline(_ timeline: Timeline) {
        NotificationCenter.default.post(name: .switched_timeline, object: timeline)
        
        if timeline == self.selected_timeline {
            NotificationCenter.default.post(name: .scroll_to_top, object: nil)
            return
        }
        
        self.selected_timeline = timeline
        //NotificationCenter.default.post(name: .switched_timeline, object: timeline)
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
        
        for relay in BOOTSTRAP_RELAYS {
            add_relay(pool, relay)
        }
        
        pool.register_handler(sub_id: sub_id, handler: home.handle_event)

        self.damus_state = DamusState(pool: pool, keypair: keypair,
                                likes: EventCounter(our_pubkey: pubkey),
                                boosts: EventCounter(our_pubkey: pubkey),
                                contacts: Contacts(our_pubkey: pubkey),
                                tips: TipCounter(our_pubkey: pubkey),
                                profiles: Profiles(),
                                dms: home.dms,
                                previews: PreviewCache(),
                                zaps: Zaps(our_pubkey: pubkey),
                                lnurls: LNUrls(),
                                settings: UserSettingsStore()
        )
        home.damus_state = self.damus_state!
        
        pool.connect()
    }

    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(keypair: Keypair(pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681", privkey: nil))
    }
}

func get_since_time(last_event: NostrEvent?) -> Int64? {
    if let last_event = last_event {
        return last_event.created_at - 60 * 10
    }
    
    return nil
}

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

func get_last_event(_ timeline: Timeline) -> LastNotification? {
    let str = timeline.rawValue
    let last = UserDefaults.standard.string(forKey: "last_\(str)")
    let last_created = UserDefaults.standard.string(forKey: "last_\(str)_time")
        .flatMap { Int64($0) }
    
    return last.flatMap { id in
        last_created.map { created in
            return LastNotification(id: id, created_at: created)
        }
    }
}

func save_last_event(_ ev: NostrEvent, timeline: Timeline) {
    let str = timeline.rawValue
    UserDefaults.standard.set(ev.id, forKey: "last_\(str)")
    UserDefaults.standard.set(String(ev.created_at), forKey: "last_\(str)_time")
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
            let since: Int64? = get_since_time(last_event: last)
            
            if earliest == nil {
                if since == nil {
                    return nil
                }
                return since
            }
            
            if since == nil {
                return earliest
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



func setup_notifications() {
    
    UIApplication.shared.registerForRemoteNotifications()
    let center = UNUserNotificationCenter.current()
    
    center.getNotificationSettings { settings in
        guard settings.authorizationStatus == .authorized else {
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                
            }
            
            return
        }
    }
}

