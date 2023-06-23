//
//  ContentView.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import AVKit

struct TimestampedProfile {
    let profile: Profile
    let timestamp: Int64
    let event: NostrEvent
}

struct ZapSheet {
    let target: ZapTarget
    let lnurl: String
}

struct SelectWallet {
    let invoice: String
}

enum Sheets: Identifiable {
    case post(PostAction)
    case report(ReportTarget)
    case event(NostrEvent)
    case zap(ZapSheet)
    case select_wallet(SelectWallet)
    case filter
    
    static func zap(target: ZapTarget, lnurl: String) -> Sheets {
        return .zap(ZapSheet(target: target, lnurl: lnurl))
    }
    
    static func select_wallet(invoice: String) -> Sheets {
        return .select_wallet(SelectWallet(invoice: invoice))
    }
    
    var id: String {
        switch self {
        case .report: return "report"
        case .post(let action): return "post-" + (action.ev?.id ?? "")
        case .event(let ev): return "event-" + ev.id
        case .zap(let sheet): return "zap-" + sheet.target.id
        case .select_wallet: return "select-wallet"
        case .filter: return "filter"
        }
    }
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
    
    @Environment(\.scenePhase) var scenePhase
    
    @State var active_sheet: Sheets? = nil
    @State var damus_state: DamusState? = nil
    @SceneStorage("ContentView.selected_timeline") var selected_timeline: Timeline = .home
    @State var is_deleted_account: Bool = false
    @State var active_profile: String? = nil
    @State var active_search: NostrFilter? = nil
    @State var active_event: NostrEvent? = nil
    @State var profile_open: Bool = false
    @State var thread_open: Bool = false
    @State var search_open: Bool = false
    @State var wallet_open: Bool = false
    @State var active_nwc: WalletConnectURL? = nil
    @State var muting: String? = nil
    @State var confirm_mute: Bool = false
    @State var user_muted_confirm: Bool = false
    @State var confirm_overwrite_mutelist: Bool = false
    @SceneStorage("ContentView.filter_state") var filter_state : FilterState = .posts_and_replies
    @State private var isSideBarOpened = false
    var home: HomeModel = HomeModel()

    let sub_id = UUID().description
    
    @Environment(\.colorScheme) var colorScheme
    
    // connect retry timer
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var mystery: some View {
        Text("Are you lost?", comment: "Text asking the user if they are lost in the app.")
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
                        self.active_sheet = .post(.posting)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(selection: $filter_state, content: {
                    Text("Notes", comment: "Label for filter for seeing only notes (instead of notes and replies).").tag(FilterState.posts)
                    Text("Notes & Replies", comment: "Label for filter for seeing notes and replies (instead of only notes).").tag(FilterState.posts_and_replies)
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
                TimelineView(events: home.events, loading: .constant(false), damus: damus, show_friend_icon: false, filter: filter)
            }
        }
    }
    
    func popToRoot() {
        profile_open = false
        thread_open = false
        search_open = false
        wallet_open = false
        isSideBarOpened = false
    }
    
    var timelineNavItem: Text {
        return Text(timeline_name(selected_timeline))
            .bold()
    }
    
    func MainContent(damus: DamusState) -> some View {
        VStack {
            NavigationLink(destination: WalletView(damus_state: damus, model: damus_state!.wallet), isActive: $wallet_open) {
                EmptyView()
            }
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
                DirectMessagesView(damus_state: damus_state!, model: damus_state!.dms, settings: damus_state!.settings)
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
                SearchView(appstate: damus_state!, search: SearchModel(state: damus_state!, search: search))
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
    
    func open_event(ev: NostrEvent) {
        popToRoot()
        self.active_event = ev
        self.thread_open = true
    }
    
    func open_wallet(nwc: WalletConnectURL) {
        self.damus_state!.wallet.new(nwc)
        self.wallet_open = true
    }
    
    func open_profile(id: String) {
        popToRoot()
        self.active_profile = id
        self.profile_open = true
    }
    
    func open_search(filt: NostrFilter) {
        popToRoot()
        self.active_search = filt
        self.search_open = true
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
                                        ProfilePicView(pubkey: damus_state!.pubkey, size: 32, highlight: .none, profiles: damus_state!.profiles, disable_animation: damus_state!.settings.disable_animation)
                                            .opacity(isSideBarOpened ? 0 : 1)
                                            .animation(isSideBarOpened ? .none : .default, value: isSideBarOpened)
                                    }
                                    .disabled(isSideBarOpened)
                                }
                                
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    HStack(alignment: .center) {
                                        SignalView(state: damus_state!, signal: home.signal)
                                        
                                        // maybe expand this to other timelines in the future
                                        if selected_timeline == .search {
                                            Button(action: {
                                                //isFilterVisible.toggle()
                                                self.active_sheet = .filter
                                            }) {
                                                // checklist, checklist.checked, lisdt.bullet, list.bullet.circle, line.3.horizontal.decrease...,  line.3.horizontail.decrease
                                                Label(NSLocalizedString("Filter", comment: "Button label text for filtering relay servers."), image: "filter")
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
            
                TabBar(nstatus: home.notification_status, selected: $selected_timeline, settings: damus.settings, action: switch_timeline)
                    .padding([.bottom], 8)
                    .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear() {
            self.connect()
            try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, mode: .default, options: .mixWithOthers)
            setup_notifications()
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .report(let target):
                MaybeReportView(target: target)
            case .post(let action):
                PostView(action: action, damus_state: damus_state!)
            case .event:
                EventDetailView()
            case .zap(let zapsheet):
                CustomizeZapView(state: damus_state!, target: zapsheet.target, lnurl: zapsheet.lnurl)
            case .select_wallet(let select):
                SelectWalletView(default_wallet: damus_state!.settings.default_wallet, active_sheet: $active_sheet, our_pubkey: damus_state!.pubkey, invoice: select.invoice)
            case .filter:
                let timeline = selected_timeline
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
            on_open_url(state: damus_state!, url: url) { res in
                guard let res else {
                    return
                }
                
                switch res {
                case .filter(let filt): self.open_search(filt: filt)
                case .profile(let id):  self.open_profile(id: id)
                case .event(let ev):    self.open_event(ev: ev)
                case .wallet_connect(let nwc): self.open_wallet(nwc: nwc)}
            }
        }
        .onReceive(handle_notify(.compose)) { notif in
            let action = notif.object as! PostAction
            self.active_sheet = .post(action)
        }
        .onReceive(timer) { n in
            self.damus_state?.postbox.try_flushing_events()
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
        .onReceive(handle_notify(.attached_wallet)) { notif in
            // update the lightning address on our profile when we attach a
            // wallet with an associated
            let nwc = notif.object as! WalletConnectURL
            guard let ds = self.damus_state,
                  let lud16 = nwc.lud16,
                  let keypair = ds.keypair.to_full(),
                  let profile = ds.profiles.lookup(id: ds.pubkey),
                  lud16 != profile.lud16
            else {
                return
            }
            
            // clear zapper cache for old lud16
            if profile.lud16 != nil {
                // TODO: should this be somewhere else, where we process profile events!?
                invalidate_zapper_cache(pubkey: keypair.pubkey, profiles: ds.profiles, lnurl: ds.lnurls)
            }
            
            profile.lud16 = lud16
            let ev = make_metadata_event(keypair: keypair, metadata: profile)
            ds.postbox.send(ev)
        }
        .onReceive(handle_notify(.broadcast_event)) { obj in
            let ev = obj.object as! NostrEvent
            guard let ds = self.damus_state else {
                return
            }
            ds.postbox.send(ev)
            if let profile = ds.profiles.lookup_with_timestamp(id: ev.pubkey) {
                ds.postbox.send(profile.event)
            }
        }
        .onReceive(handle_notify(.unfollow)) { notif in
            guard let state = self.damus_state else {
                return
            }
            handle_unfollow(state: state, notif: notif)
        }
        .onReceive(handle_notify(.follow)) { notif in
            guard let state = self.damus_state else {
                return
            }
            handle_follow(state: state, notif: notif)
        }
        .onReceive(handle_notify(.post)) { notif in
            guard let state = self.damus_state,
                  let keypair = state.keypair.to_full() else {
                      return
            }

            if !handle_post_notification(keypair: keypair, postbox: state.postbox, events: state.events, notif: notif) {
                self.active_sheet = nil
            }
        }
        .onReceive(handle_notify(.new_mutes)) { notif in
            home.filter_events()
        }
        .onReceive(handle_notify(.mute_thread)) { notif in
            home.filter_events()
        }
        .onReceive(handle_notify(.unmute_thread)) { notif in
            home.filter_events()
        }
        .onReceive(handle_notify(.present_sheet)) { notif in
            let sheet = notif.object as! Sheets
            self.active_sheet = sheet
        }
        .onReceive(handle_notify(.zapping)) { notif in
            let zap_ev = notif.object as! ZappingEvent
            
            guard !zap_ev.is_custom else {
                return
            }
            
            switch zap_ev.type {
            case .failed:
                break
            case .got_zap_invoice(let inv):
                if damus_state!.settings.show_wallet_selector {
                    present_sheet(.select_wallet(invoice: inv))
                } else {
                    let wallet = damus_state!.settings.default_wallet.model
                    open_with_wallet(wallet: wallet, invoice: inv)
                }
            case .sent_from_nwc:
                break
            }
        }
        .onChange(of: scenePhase) { (phase: ScenePhase) in
            switch phase {
            case .background:
                print("📙 DAMUS BACKGROUNDED")
                break
            case .inactive:
                print("📙 DAMUS INACTIVE")
                break
            case .active:
                print("📙 DAMUS ACTIVE")
                guard let ds = damus_state else { return }
                ds.pool.ping()
            @unknown default:
                break
            }
        }
        .onReceive(handle_notify(.local_notification)) { notif in
            
            guard let local = notif.object as? LossyLocalNotification,
                let damus_state else {
                return
            }

            if local.type == .profile_zap {
                open_profile(id: local.event_id)
                return
            }
            
            guard let target = damus_state.events.lookup(local.event_id) else {
                return
            }
            
            switch local.type {
            case .dm:
                selected_timeline = .dms
                damus_state.dms.open_dm_by_pk(target.pubkey)
                
            case .like: fallthrough
            case .zap: fallthrough
            case .mention: fallthrough
            case .repost:
                open_event(ev: target)
            case .profile_zap:
                // Handled separately above.
                break
            }
        }
        .onReceive(handle_notify(.onlyzaps_mode)) { notif in
            let hide = notif.object as! Bool
            home.filter_events()
            
            guard let damus_state,
                  let profile = damus_state.profiles.lookup(id: damus_state.pubkey),
                  let keypair = damus_state.keypair.to_full()
            else {
                return
            }
            
            profile.reactions = !hide
            let profile_ev = make_metadata_event(keypair: keypair, metadata: profile)
            damus_state.postbox.send(profile_ev)
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
                let name = Profile.displayName(profile: profile, pubkey: pubkey).username.truncate(maxLength: 50)
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
                guard let ds = damus_state,
                      let keypair = ds.keypair.to_full(),
                      let pubkey = muting,
                      let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: pubkey)
                else {
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
                let name = Profile.displayName(profile: profile, pubkey: pubkey).username.truncate(maxLength: 50)
                Text("Mute \(name)?", comment: "Alert message prompt to ask if a user should be muted.")
            } else {
                Text("Could not find user to mute...", comment: "Alert message to indicate that the muted user could not be found.")
            }
        })
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
    }

    func connect() {
        let pool = RelayPool()
        let metadatas = RelayMetadatas()
        let relay_filters = RelayFilters(our_pubkey: pubkey)
        let bootstrap_relays = load_bootstrap_relays(pubkey: pubkey)
        
        let new_relay_filters = load_relay_filters(pubkey) == nil
        for relay in bootstrap_relays {
            if let url = RelayURL(relay) {
                let descriptor = RelayDescriptor(url: url, info: .rw)
                add_new_relay(relay_filters: relay_filters, metadatas: metadatas, pool: pool, descriptor: descriptor, new_relay_filters: new_relay_filters)
            }
        }
        
        pool.register_handler(sub_id: sub_id, handler: home.handle_event)
        
        // dumb stuff needed for property wrappers
        UserSettingsStore.pubkey = pubkey
        let settings = UserSettingsStore()
        UserSettingsStore.shared = settings
        
        if let nwc_str = settings.nostr_wallet_connect,
           let nwc = WalletConnectURL(str: nwc_str) {
            try? pool.add_relay(.nwc(url: nwc.relay))
        }
        
        self.damus_state = DamusState(pool: pool,
                                      keypair: keypair,
                                      likes: EventCounter(our_pubkey: pubkey),
                                      boosts: EventCounter(our_pubkey: pubkey),
                                      contacts: Contacts(our_pubkey: pubkey),
                                      profiles: Profiles(),
                                      dms: home.dms,
                                      previews: PreviewCache(),
                                      zaps: Zaps(our_pubkey: pubkey),
                                      lnurls: LNUrls(),
                                      settings: settings,
                                      relay_filters: relay_filters,
                                      relay_metadata: metadatas,
                                      drafts: Drafts(),
                                      events: EventCache(),
                                      bookmarks: BookmarksManager(pubkey: pubkey),
                                      postbox: PostBox(pool: pool),
                                      bootstrap_relays: bootstrap_relays,
                                      replies: ReplyCounter(our_pubkey: pubkey),
                                      muted_threads: MutedThreadsManager(keypair: keypair),
                                      wallet: WalletModel(settings: settings)
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

func update_filters_with_since(last_of_kind: [Int: NostrEvent], filters: [NostrFilter]) -> [NostrFilter] {
    
    return filters.map { filter in
        let kinds = filter.kinds ?? []
        let initial: Int64? = nil
        let earliest = kinds.reduce(initial) { earliest, kind in
            let last = last_of_kind[kind.rawValue]
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

struct FindEvent {
    let type: FindEventType
    let find_from: [String]?
    
    static func profile(pubkey: String, find_from: [String]? = nil) -> FindEvent {
        return FindEvent(type: .profile(pubkey), find_from: find_from)
    }
    
    static func event(evid: String, find_from: [String]? = nil) -> FindEvent {
        return FindEvent(type: .event(evid), find_from: find_from)
    }
}

enum FindEventType {
    case profile(String)
    case event(String)
}

enum FoundEvent {
    case profile(Profile, NostrEvent)
    case invalid_profile(NostrEvent)
    case event(NostrEvent)
}

func find_event(state: DamusState, query query_: FindEvent, callback: @escaping (FoundEvent?) -> ()) {
    
    var filter: NostrFilter? = nil
    let find_from = query_.find_from
    let query = query_.type
    
    switch query {
    case .profile(let pubkey):
        if let profile = state.profiles.lookup_with_timestamp(id: pubkey) {
            callback(.profile(profile.profile, profile.event))
            return
        }
        filter = NostrFilter(kinds: [.metadata], limit: 1, authors: [pubkey])
        
    case .event(let evid):
        if let ev = state.events.lookup(evid) {
            callback(.event(ev))
            return
        }
    
        filter = NostrFilter(ids: [evid], limit: 1)
    }
    
    let subid = UUID().description
    var attempts: Int = 0
    var has_event = false
    guard let filter else { return }
    
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
            state.pool.unsubscribe(sub_id: subid)
            
            switch query {
            case .profile:
                if ev.known_kind == .metadata {
                    process_metadata_event(events: state.events, our_pubkey: state.pubkey, profiles: state.profiles, ev: ev) { profile in
                        guard let profile else {
                            callback(.invalid_profile(ev))
                            return
                        }
                        callback(.profile(profile, ev))
                        return
                    }
                }
            case .event:
                callback(.event(ev))
            }
        case .eose:
            if !has_event {
                attempts += 1
                if attempts == state.pool.our_descriptors.count / 2 {
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
        return NSLocalizedString("Home", comment: "Navigation bar title for Home view where notes and replies appear from those who the user is following.")
    case .notifications:
        return NSLocalizedString("Notifications", comment: "Toolbar label for Notifications view.")
    case .search:
        return NSLocalizedString("Universe 🛸", comment: "Toolbar label for the universal view where notes from all connected relay servers appear.")
    case .dms:
        return NSLocalizedString("DMs", comment: "Toolbar label for DMs view, where DM is the English abbreviation for Direct Message.")
    }
}

func handle_unfollow(state: DamusState, notif: Notification) {
    guard let privkey = state.keypair.privkey else {
        return
    }
    
    let target = notif.object as! FollowTarget
    let pk = target.pubkey
    
    if let ev = unfollow_user(postbox: state.postbox,
                              our_contacts: state.contacts.event,
                              pubkey: state.pubkey,
                              privkey: privkey,
                              unfollow: pk) {
        notify(.unfollowed, pk)
        
        state.contacts.event = ev
        state.contacts.remove_friend(pk)
        //friend_events = friend_events.filter { $0.pubkey != pk }
    }
}

func handle_follow(state: DamusState, notif: Notification) {
    guard let privkey = state.keypair.privkey else {
        return
    }

    let fnotify = notif.object as! FollowTarget

    if let ev = follow_user(pool: state.pool,
                            our_contacts: state.contacts.event,
                            pubkey: state.pubkey,
                            privkey: privkey,
                            follow: ReferencedId(ref_id: fnotify.pubkey, relay_id: nil, key: "p")) {
        notify(.followed, fnotify.pubkey)
        
        state.contacts.event = ev
        
        switch fnotify {
        case .pubkey(let pk):
            state.contacts.add_friend_pubkey(pk)
        case .contact(let ev):
            state.contacts.add_friend_contact(ev)
        }
    }
}

func handle_post_notification(keypair: FullKeypair, postbox: PostBox, events: EventCache, notif: Notification) -> Bool {
    let post_res = notif.object as! NostrPostResult
    switch post_res {
    case .post(let post):
        //let post = tup.0
        //let to_relays = tup.1
        print("post \(post.content)")
        let new_ev = post_to_event(post: post, privkey: keypair.privkey, pubkey: keypair.pubkey)
        postbox.send(new_ev)
        for eref in new_ev.referenced_ids.prefix(3) {
            // also broadcast at most 3 referenced events
            if let ev = events.lookup(eref.ref_id) {
                postbox.send(ev)
            }
        }
        return true
    case .cancel:
        print("post cancelled")
        return false
    }
}


enum OpenResult {
    case profile(String)
    case filter(NostrFilter)
    case event(NostrEvent)
    case wallet_connect(WalletConnectURL)
}

func on_open_url(state: DamusState, url: URL, result: @escaping (OpenResult?) -> Void) {
    if let nwc = WalletConnectURL(str: url.absoluteString) {
        result(.wallet_connect(nwc))
        return
    }
    
    guard let link = decode_nostr_uri(url.absoluteString) else {
        result(nil)
        return
    }
    
    switch link {
    case .ref(let ref):
        if ref.key == "p" {
            result(.profile(ref.ref_id))
        } else if ref.key == "e" {
            find_event(state: state, query: .event(evid: ref.ref_id)) { res in
                guard let res, case .event(let ev) = res else { return }
                result(.event(ev))
            }
        }
    case .filter(let filt):
        result(.filter(filt))
        break
        // TODO: handle filter searches?
    }
}
