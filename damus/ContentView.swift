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
    let event: NostrEvent
}

enum Sheets: Identifiable {
    case post
    case report(ReportTarget)
    case reply(NostrEvent)
    case event(NostrEvent)
    case filter

    var id: String {
        switch self {
        case .report: return "report"
        case .post: return "post"
        case .reply(let ev): return "reply-" + ev.id
        case .event(let ev): return "event-" + ev.id
        case .filter: return "filter"
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
    @State var active_event: NostrEvent? = nil
    @State var profile_open: Bool = false
    @State var thread_open: Bool = false
    @State var search_open: Bool = false
    @State var muting: String? = nil
    @State var confirm_mute: Bool = false
    @State var user_muted_confirm: Bool = false
    @State var confirm_overwrite_mutelist: Bool = false
    @State var current_boost: NostrEvent? = nil
    @State var filter_state : FilterState = .posts_and_replies
    @State private var isSideBarOpened = false
    @StateObject var home: HomeModel = HomeModel()
    
    // connect retry timer
    let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    let sub_id = UUID().description
    
    @Environment(\.colorScheme) var colorScheme
    
    var mystery: some View {
        Text("Are you lost?")
        .id("what")
    }
    
    var PostingTimelineView: some View {
        VStack {
            ZStack {
                TabView(selection: $filter_state) {
                    // This is needed or else there is a bug when switching from the 3rd or 2nd tab to first. no idea why.
                    mystery
                    
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
                TimelineView(events: home.events, loading: $home.loading, damus: damus, show_friend_icon: false, filter: filter)
            }
        }
    }
    
    func popToRoot() {
        profile_open = false
        thread_open = false
        search_open = false
        isSideBarOpened = false
    }
    
    var timelineNavItem: Text {
        return Text(timeline_name(selected_timeline))
            .bold()
    }
    
    func MainContent(damus: DamusState) -> some View {
        VStack {
            NavigationLink(destination: MaybeProfileView, isActive: $profile_open) {
                EmptyView()
            }
            if let active_event {
                let thread = ThreadModel(event: active_event, damus_state: damus_state!)
                NavigationLink(destination: ThreadView(state: damus_state!, thread: thread), isActive: $thread_open) {
                    EmptyView()
                }
            }
            NavigationLink(destination: MaybeSearchView, isActive: $search_open) {
                EmptyView()
            }
            switch selected_timeline {
            case .search:
                if #available(iOS 16.0, *) {
                    SearchHomeView(damus_state: damus_state!, model: SearchHomeModel(damus_state: damus_state!))
                        .scrollDismissesKeyboard(.immediately)
                } else {
                    // Fallback on earlier versions
                    SearchHomeView(damus_state: damus_state!, model: SearchHomeModel(damus_state: damus_state!))
                }
                
            case .home:
                PostingTimelineView
                
            case .notifications:
                NotificationsView(state: damus, notifications: home.notifications)
                
            case .dms:
                DirectMessagesView(damus_state: damus_state!)
                    .environmentObject(home.dms)
            
            case .none:
                EmptyView()
            }
        }
        .navigationBarTitle(timeline_name(selected_timeline), displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    if selected_timeline == .home {
                        Image("damus-home")
                            .resizable()
                            .frame(width:30,height:30)
                            .shadow(color: DamusColors.purple, radius: 2)
                            .opacity(isSideBarOpened ? 0 : 1)
                            .animation(isSideBarOpened ? .none : .default, value: isSideBarOpened)
                    } else {
                        timelineNavItem
                            .opacity(isSideBarOpened ? 0 : 1)
                            .animation(isSideBarOpened ? .none : .default, value: isSideBarOpened)
                    }
                }
            }
        }
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
            if let damus_state {
                if let sec = damus_state.keypair.privkey {
                    ReportView(postbox: damus_state.postbox, target: target, privkey: sec)
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
                    TabView { // Prevents navbar appearance change on scroll
                        MainContent(damus: damus)
                            .toolbar() {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button {
                                        isSideBarOpened.toggle()
                                    } label: {
                                        ProfilePicView(pubkey: damus_state!.pubkey, size: 32, highlight: .none, profiles: damus_state!.profiles)
                                            .opacity(isSideBarOpened ? 0 : 1)
                                            .animation(isSideBarOpened ? .none : .default, value: isSideBarOpened)
                                    }
                                    .disabled(isSideBarOpened)
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
                                        
                                        // maybe expand this to other timelines in the future
                                        if selected_timeline == .search {
                                            Button(action: {
                                                //isFilterVisible.toggle()
                                                self.active_sheet = .filter
                                            }) {
                                                // checklist, checklist.checked, lisdt.bullet, list.bullet.circle, line.3.horizontal.decrease...,  line.3.horizontail.decrease
                                                Label(NSLocalizedString("Filter", comment: "Button label text for filtering relay servers."), systemImage: "line.3.horizontal.decrease")
                                                    .foregroundColor(.gray)
                                                    //.contentShape(Rectangle())
                                            }
                                        }
                                    }
                                }
                            }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .overlay(
                        SideMenuView(damus_state: damus, isSidebarVisible: $isSideBarOpened.animation())
                    )
                }
                .navigationViewStyle(.stack)
            
                TabBar(new_events: $home.new_events, selected: $selected_timeline, settings: damus.settings, action: switch_timeline)
                    .padding([.bottom], 8)
                    .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear() {
            self.connect()
            setup_notifications()
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .report(let target):
                MaybeReportView(target: target)
            case .post:
                PostView(replying_to: nil, damus_state: damus_state!)
            case .reply(let event):
                PostView(replying_to: event, damus_state: damus_state!)
            case .event:
                EventDetailView()
            case .filter:
                let timeline = selected_timeline ?? .home
                if #available(iOS 16.0, *) {
                    RelayFilterView(state: damus_state!, timeline: timeline)
                        .presentationDetents([.height(550)])
                        .presentationDragIndicator(.visible)
                } else {
                    RelayFilterView(state: damus_state!, timeline: timeline)
                }
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
                    find_event(state: damus_state!, evid: ref.ref_id, search_type: .event, find_from: nil) { ev in
                        if let ev {
                            active_event = ev
                        }
                    }
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
            current_boost = (notif.object as? NostrEvent)
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
        .onReceive(handle_notify(.mute)) { notif in
            let pubkey = notif.object as! String
            self.muting = pubkey
            self.confirm_mute = true
        }
        .onReceive(handle_notify(.broadcast_event)) { obj in
            let ev = obj.object as! NostrEvent
            guard let ds = self.damus_state else {
                return
            }
            ds.postbox.send(ev)
            if let profile = ds.profiles.profiles[ev.pubkey] {
                ds.postbox.send(profile.event)
            }
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
            
            if let ev = unfollow_user(postbox: damus.postbox,
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
                //let post = tup.0
                //let to_relays = tup.1
                print("post \(post.content)")
                let new_ev = post_to_event(post: post, privkey: privkey, pubkey: pubkey)
                guard let ds = self.damus_state else {
                    return
                }
                ds.postbox.send(new_ev)
                for eref in new_ev.referenced_ids.prefix(3) {
                    // also broadcast at most 3 referenced events
                    if let ev = ds.events.lookup(eref.ref_id) {
                        ds.postbox.send(ev)
                    }
                }
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
        .alert(NSLocalizedString("User muted", comment: "Alert message to indicate the user has been muted"), isPresented: $user_muted_confirm, actions: {
            Button(NSLocalizedString("Thanks!", comment: "Button to close out of alert that informs that the action to muted a user was successful.")) {
                user_muted_confirm = false
            }
        }, message: {
            if let pubkey = self.muting {
                let profile = damus_state!.profiles.lookup(id: pubkey)
                let name = Profile.displayName(profile: profile, pubkey: pubkey).username
                Text("\(name) has been muted", comment: "Alert message that informs a user was muted.")
            } else {
                Text("User has been muted", comment: "Alert message that informs a user was d.")
            }
        })
        .alert(NSLocalizedString("Create new mutelist", comment: "Title of alert prompting the user to create a new mutelist."), isPresented: $confirm_overwrite_mutelist, actions: {
            Button(NSLocalizedString("Cancel", comment: "Button to cancel out of alert that creates a new mutelist.")) {
                confirm_overwrite_mutelist = false
                confirm_mute = false
            }

            Button(NSLocalizedString("Yes, Overwrite", comment: "Text of button that confirms to overwrite the existing mutelist.")) {
                guard let ds = damus_state else {
                    return
                }
                
                guard let keypair = ds.keypair.to_full() else {
                    return
                }
                
                guard let pubkey = muting else {
                    return
                }
                
                guard let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: pubkey) else {
                    return
                }
                
                damus_state?.contacts.set_mutelist(mutelist)
                ds.postbox.send(mutelist)

                confirm_overwrite_mutelist = false
                confirm_mute = false
                user_muted_confirm = true
            }
        }, message: {
            Text("No mute list found, create a new one? This will overwrite any previous mute lists.", comment: "Alert message prompt that asks if the user wants to create a new mute list, overwriting previous mute lists.")
        })
        .alert(NSLocalizedString("Mute User", comment: "Title of alert for muting a user."), isPresented: $confirm_mute, actions: {
            Button(NSLocalizedString("Cancel", comment: "Alert button to cancel out of alert for muting a user."), role: .cancel) {
                confirm_mute = false
            }
            Button(NSLocalizedString("Mute", comment: "Alert button to mute a user."), role: .destructive) {
                guard let ds = damus_state else {
                    return
                }

                if ds.contacts.mutelist == nil {
                    confirm_overwrite_mutelist = true
                } else {
                    guard let keypair = ds.keypair.to_full() else {
                        return
                    }
                    guard let pubkey = muting else {
                        return
                    }

                    guard let ev = create_or_update_mutelist(keypair: keypair, mprev: ds.contacts.mutelist, to_add: pubkey) else {
                        return
                    }
                    damus_state?.contacts.set_mutelist(ev)
                    ds.postbox.send(ev)
                }
            }
        }, message: {
            if let pubkey = muting {
                let profile = damus_state?.profiles.lookup(id: pubkey)
                let name = Profile.displayName(profile: profile, pubkey: pubkey).username
                Text("Mute \(name)?", comment: "Alert message prompt to ask if a user should be muted.")
            } else {
                Text("Could not find user to mute...", comment: "Alert message to indicate that the muted user could not be found.")
            }
        })
        .alert(NSLocalizedString("Repost", comment: "Title of alert for confirming to repost a post."), isPresented: $current_boost.mappedToBool()) {
            Button(NSLocalizedString("Cancel", comment: "Button to cancel out of reposting a post.")) {
                current_boost = nil
            }
            Button(NSLocalizedString("Repost", comment: "Button to confirm reposting a post.")) {
                if let current_boost {
                    self.damus_state?.pool.send(.event(current_boost))
                }
            }
        } message: {
            Text("Are you sure you want to repost this?", comment: "Alert message to ask if user wants to repost a post.")
        }
    }
    
    func switch_timeline(_ timeline: Timeline) {
        self.isSideBarOpened = false
        
        self.popToRoot()
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
        let metadatas = RelayMetadatas()
        let relay_filters = RelayFilters(our_pubkey: pubkey)
        let bootstrap_relays = load_bootstrap_relays(pubkey: pubkey)
        
        let new_relay_filters = load_relay_filters(pubkey) == nil
        for relay in bootstrap_relays {
            if let url = URL(string: relay) {
                add_new_relay(relay_filters: relay_filters, metadatas: metadatas, pool: pool, url: url, info: .rw, new_relay_filters: new_relay_filters)
            }
        }
        
        pool.register_handler(sub_id: sub_id, handler: home.handle_event)

        self.damus_state = DamusState(pool: pool,
                                      keypair: keypair,
                                      likes: EventCounter(our_pubkey: pubkey),
                                      boosts: EventCounter(our_pubkey: pubkey),
                                      contacts: Contacts(our_pubkey: pubkey),
                                      tips: TipCounter(our_pubkey: pubkey),
                                      profiles: Profiles(),
                                      dms: home.dms,
                                      previews: PreviewCache(),
                                      zaps: Zaps(our_pubkey: pubkey),
                                      lnurls: LNUrls(),
                                      settings: UserSettingsStore(),
                                      relay_filters: relay_filters,
                                      relay_metadata: metadatas,
                                      drafts: Drafts(),
                                      events: EventCache(),
                                      bookmarks: BookmarksManager(pubkey: pubkey),
                                      postbox: PostBox(pool: pool),
                                      bootstrap_relays: bootstrap_relays,
                                      replies: ReplyCounter(our_pubkey: pubkey)
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

func find_event(state: DamusState, evid: String, search_type: SearchType, find_from: [String]?, callback: @escaping (NostrEvent?) -> ()) {
    if let ev = state.events.lookup(evid) {
        callback(ev)
        return
    }
    
    let subid = UUID().description
    
    var has_event = false
    
    var filter = search_type == .event ? NostrFilter.filter_ids([ evid ]) : NostrFilter.filter_authors([ evid ])
    
    if search_type == .profile {
        filter.kinds = [0]
    }
    
    filter.limit = 1
    var attempts = 0
    
    state.pool.subscribe_to(sub_id: subid, filters: [filter], to: find_from) { relay_id, res  in
        guard case .nostr_event(let ev) = res else {
            return
        }
        
        guard ev.subid == subid else {
            return
        }
        
        switch ev {
        case .ok:
            break
        case .event(_, let ev):
            has_event = true
            callback(ev)
            state.pool.unsubscribe(sub_id: subid)
        case .eose:
            if !has_event {
                attempts += 1
                if attempts == state.pool.descriptors.count / 2 {
                    callback(nil)
                }
                state.pool.unsubscribe(sub_id: subid, to: [relay_id])
            }
        case .notice(_):
            break
        }

    }
}


func timeline_name(_ timeline: Timeline?) -> String {
    guard let timeline else {
        return ""
    }
    switch timeline {
    case .home:
        return NSLocalizedString("Home", comment: "Navigation bar title for Home view where posts and replies appear from those who the user is following.")
    case .notifications:
        return NSLocalizedString("Notifications", comment: "Toolbar label for Notifications view.")
    case .search:
        return NSLocalizedString("Universe 🛸", comment: "Toolbar label for the universal view where posts from all connected relay servers appear.")
    case .dms:
        return NSLocalizedString("DMs", comment: "Toolbar label for DMs view, where DM is the English abbreviation for Direct Message.")
    }
}
