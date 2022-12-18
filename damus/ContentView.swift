//
//  ContentView.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import Starscream
import Kingfisher

struct ContentView: View {
    
    @EnvironmentObject var viewModel: DamusViewModel

    // connect retry timer
    let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    let sub_id = UUID().description
    
    @Environment(\.colorScheme) var colorScheme

    var PostingTimelineView: some View {
        VStack{
            ZStack {
                if let damus = self.damus_state {
                    TimelineView(events: viewModel.$home.events, loading: viewModel.$home.loading, damus: damus, show_friend_icon: false, filter: filter_event)
                }
                if viewModel.privkey != nil {
                    PostButtonContainer {
                        self.active_sheet = .post
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                FiltersView
                    //.frame(maxWidth: 275)
                    .padding()
                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }
    
    var FiltersView: some View {
        VStack{
            Picker("Filter State", selection: $viewModel.filter_state) {
                Text("Posts").tag(FilterState.posts)
                Text("Posts & Replies").tag(FilterState.posts_and_replies)
            }
            .pickerStyle(.segmented)
        }
    }
    
    func filter_event(_ ev: NostrEvent) -> Bool {
        if viewModel.filter_state == .posts {
            return !ev.is_reply(nil)
        }
        
        return true
    }
    
    func MainContent(damus: DamusState) -> some View {
        VStack {
            NavigationLink(destination: MaybeProfileView, isActive: $viewModel.profile_open) {
                EmptyView()
            }
            NavigationLink(destination: MaybeThreadView, isActive: $viewModel.thread_open) {
                EmptyView()
            }
            NavigationLink(destination: MaybeSearchView, isActive: $viewModel.search_open) {
                EmptyView()
            }
            switch selected_timeline {
            case .search:
                SearchHomeView(damus_state: viewModel.state!, model: SearchHomeModel(damus_state: damus_state!))
                
            case .home:
                PostingTimelineView
                
            case .notifications:
                TimelineView(events: $home.notifications, loading: $home.loading, damus: damus, show_friend_icon: true, filter: { _ in true })
                    .navigationTitle("Notifications")
                
            case .dms:
                DirectMessagesView(damus_state: damus_state!)
                    .environmentObject(home.dms)
            
            case .none:
                EmptyView()
            }
        }
        .navigationBarTitle(selected_timeline == .home ?  "Home" : "Global", displayMode: .inline)
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
                let thread_model = ThreadModel(evid: evid, damus_state: damus_state!)
                ThreadView(thread: thread_model, damus: damus_state!, is_chatroom: false)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let damus = self.damus_state {
                NavigationView {
                    MainContent(damus: damus)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                let profile_model = ProfileModel(pubkey: damus_state!.pubkey, damus: damus_state!)
                                let followers_model = FollowersModel(damus_state: damus_state!, target: damus_state!.pubkey)
                                let prof_dest = ProfileView(damus_state: damus_state!, profile: profile_model, followers: followers_model)

                                NavigationLink(destination: prof_dest) {
                                    /// Verify that the user has a profile picture, if not display a generic SF Symbol
                                    /// (Resolves an in-app error where ``Robohash`` pictures are not generated so the button dissapears
                                    if let picture = damus_state?.profiles.lookup(id: pubkey)?.picture {
                                        ProfilePicView(pubkey: damus_state!.pubkey, size: 32, highlight: .none, profiles: damus_state!.profiles, picture: picture)
                                    } else {
                                        Image(systemName: "person.fill")
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            ToolbarItem(placement: .navigationBarTrailing) {
                                    NavigationLink(destination: ConfigView(state: damus_state!)) {
                                        if #available(iOS 16.0, *) {
                                            Image(systemName: "chart.bar.fill", variableValue: Double(home.signal.signal) / Double(home.signal.max_signal))
                                                .font(.body.weight(.ultraLight))
                                                .symbolRenderingMode(.hierarchical)
                                        } else {
                                            // Fallback on earlier versions
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                            }
                        }
                }
                .navigationViewStyle(.stack)
            }

            TabBar(new_events: $home.new_events, selected: $selected_timeline, action: switch_timeline)
        }
        .onAppear() {
            self.connect()
            //KingfisherManager.shared.cache.clearDiskCache()
            setup_notifications()
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .post:
                PostView(replying_to: nil, references: [])
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
