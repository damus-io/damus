//
//  ContentView.swift
//  damus
//
//  Created by William Casarin on 2022-04-01.
//

import SwiftUI
import AVKit
import MediaPlayer
import EmojiPicker

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
    case profile_action(Pubkey)
    case zap(ZapSheet)
    case select_wallet(SelectWallet)
    case filter
    case user_status
    case onboardingSuggestions
    case purple(DamusPurpleURL)
    case purple_onboarding
    
    static func zap(target: ZapTarget, lnurl: String) -> Sheets {
        return .zap(ZapSheet(target: target, lnurl: lnurl))
    }
    
    static func select_wallet(invoice: String) -> Sheets {
        return .select_wallet(SelectWallet(invoice: invoice))
    }
    
    var id: String {
        switch self {
        case .report: return "report"
        case .user_status: return "user_status"
        case .post(let action): return "post-" + (action.ev?.id.hex() ?? "")
        case .event(let ev): return "event-" + ev.id.hex()
        case .profile_action(let pubkey): return "profile-action-" + pubkey.npub
        case .zap(let sheet): return "zap-" + hex_encode(sheet.target.id)
        case .select_wallet: return "select-wallet"
        case .filter: return "filter"
        case .onboardingSuggestions: return "onboarding-suggestions"
        case .purple(let purple_url): return "purple" + purple_url.url_string()
        case .purple_onboarding: return "purple_onboarding"
        }
    }
}

func present_sheet(_ sheet: Sheets) {
    notify(.present_sheet(sheet))
}

struct ContentView: View {
    let keypair: Keypair
    let appDelegate: AppDelegate?
    
    var pubkey: Pubkey {
        return keypair.pubkey
    }
    
    var privkey: Privkey? {
        return keypair.privkey
    }
    
    @Environment(\.scenePhase) var scenePhase
    
    @State var active_sheet: Sheets? = nil
    @State var damus_state: DamusState!
    @SceneStorage("ContentView.selected_timeline") var selected_timeline: Timeline = .home
    @State var muting: MuteItem? = nil
    @State var confirm_mute: Bool = false
    @State var hide_bar: Bool = false
    @State var user_muted_confirm: Bool = false
    @State var confirm_overwrite_mutelist: Bool = false
    @SceneStorage("ContentView.filter_state") var filter_state : FilterState = .posts_and_replies
    @State private var isSideBarOpened = false
    var home: HomeModel = HomeModel()
    @StateObject var navigationCoordinator: NavigationCoordinator = NavigationCoordinator()
    @AppStorage("has_seen_suggested_users") private var hasSeenOnboardingSuggestions = false
    let sub_id = UUID().description

    @Environment(\.colorScheme) var colorScheme
    
    // connect retry timer
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var mystery: some View {
        Text("Are you lost?", comment: "Text asking the user if they are lost in the app.")
        .id("what")
    }

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state!)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
    }

    var PostingTimelineView: some View {
        VStack {
            ZStack {
                TabView(selection: $filter_state) {
                    // This is needed or else there is a bug when switching from the 3rd or 2nd tab to first. no idea why.
                    mystery
                    
                    contentTimelineView(filter: content_filter(.posts))
                        .tag(FilterState.posts)
                        .id(FilterState.posts)
                    contentTimelineView(filter: content_filter(.posts_and_replies))
                        .tag(FilterState.posts_and_replies)
                        .id(FilterState.posts_and_replies)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                if privkey != nil {
                    PostButtonContainer(is_left_handed: damus_state?.settings.left_handed ?? false) {
                        self.active_sheet = .post(.posting(.none))
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(tabs:
                  [("Notes", FilterState.posts),
                   ("Notes & Replies", FilterState.posts_and_replies)
                  ],
                selection: $filter_state)

                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }
    
    func contentTimelineView(filter: (@escaping (NostrEvent) -> Bool)) -> some View {
        TimelineView(events: home.events, loading: .constant(false), damus: damus_state, show_friend_icon: false, filter: filter) {
            PullDownSearchView(state: damus_state, on_cancel: {})
        }
    }
    
    func navIsAtRoot() -> Bool {
        return navigationCoordinator.isAtRoot()
    }
    
    func popToRoot() {
        navigationCoordinator.popToRoot()
        isSideBarOpened = false
    }
    
    var timelineNavItem: Text {
        return Text(timeline_name(selected_timeline))
            .bold()
    }
    
    func MainContent(damus: DamusState) -> some View {
        VStack {
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
                            .onTapGesture {
                                isSideBarOpened.toggle()
                            }
                    } else {
                        timelineNavItem
                            .opacity(isSideBarOpened ? 0 : 1)
                            .animation(isSideBarOpened ? .none : .default, value: isSideBarOpened)
                    }
                }
            }
        }
    }
    
    func MaybeReportView(target: ReportTarget) -> some View {
        Group {
            if let keypair = damus_state.keypair.to_full() {
                ReportView(postbox: damus_state.postbox, target: target, keypair: keypair)
            } else {
                EmptyView()
            }
        }
    }
    
    func open_event(ev: NostrEvent) {
        let thread = ThreadModel(event: ev, damus_state: damus_state!)
        navigationCoordinator.push(route: Route.Thread(thread: thread))
    }
    
    func open_wallet(nwc: WalletConnectURL) {
        self.damus_state!.wallet.new(nwc)
        navigationCoordinator.push(route: Route.Wallet(wallet: damus_state!.wallet))
    }
    
    func open_script(_ script: [UInt8]) {
        print("pushing script nav")
        let model = ScriptModel(data: script, state: .not_loaded)
        navigationCoordinator.push(route: Route.Script(script: model))
    }
    
    func open_profile(pubkey: Pubkey) {
        let profile_model = ProfileModel(pubkey: pubkey, damus: damus_state!)
        let followers = FollowersModel(damus_state: damus_state!, target: pubkey)
        navigationCoordinator.push(route: Route.Profile(profile: profile_model, followers: followers))
    }
    
    func open_search(filt: NostrFilter) {
        let search = SearchModel(state: damus_state!, search: filt)
        navigationCoordinator.push(route: Route.Search(search: search))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let damus = self.damus_state {
                NavigationStack(path: $navigationCoordinator.path) {
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
                                                present_sheet(.filter)
                                            }, label: {
                                                Image("filter")
                                                    .foregroundColor(.gray)
                                            })
                                        }
                                    }
                                }
                            }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .overlay(
                        SideMenuView(damus_state: damus_state!, isSidebarVisible: $isSideBarOpened.animation())
                    )
                    .navigationDestination(for: Route.self) { route in
                        route.view(navigationCoordinator: navigationCoordinator, damusState: damus_state!)
                    }
                    .onReceive(handle_notify(.switched_timeline)) { _ in
                        navigationCoordinator.popToRoot()
                    }
                }
                .navigationViewStyle(.stack)
            
                if !hide_bar {
                    TabBar(nstatus: home.notification_status, selected: $selected_timeline, settings: damus.settings, action: switch_timeline)
                        .padding([.bottom], 8)
                        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
                } else {
                    Text("")
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .edgesIgnoringSafeArea(hide_bar ? [.bottom] : [])
        .onAppear() {
            self.connect()
            try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, mode: .default, options: .mixWithOthers)
            setup_notifications()
            if !hasSeenOnboardingSuggestions || damus_state!.settings.always_show_onboarding_suggestions {
                active_sheet = .onboardingSuggestions
                hasSeenOnboardingSuggestions = true
            }
            self.appDelegate?.state = damus_state
        }
        .sheet(item: $active_sheet) { item in
            switch item {
            case .report(let target):
                MaybeReportView(target: target)
            case .post(let action):
                PostView(action: action, damus_state: damus_state!)
            case .user_status:
                UserStatusSheet(damus_state: damus_state!, postbox: damus_state!.postbox, keypair: damus_state!.keypair, status: damus_state!.profiles.profile_data(damus_state!.pubkey).status)
                    .presentationDragIndicator(.visible)
            case .event:
                EventDetailView()
            case .profile_action(let pubkey):
                ProfileActionSheetView(damus_state: damus_state!, pubkey: pubkey)
            case .zap(let zapsheet):
                CustomizeZapView(state: damus_state!, target: zapsheet.target, lnurl: zapsheet.lnurl)
            case .select_wallet(let select):
                SelectWalletView(default_wallet: damus_state!.settings.default_wallet, active_sheet: $active_sheet, our_pubkey: damus_state!.pubkey, invoice: select.invoice)
            case .filter:
                let timeline = selected_timeline
                RelayFilterView(state: damus_state!, timeline: timeline)
                    .presentationDetents([.height(550)])
                    .presentationDragIndicator(.visible)
            case .onboardingSuggestions:
                OnboardingSuggestionsView(model: SuggestedUsersViewModel(damus_state: damus_state!))
            case .purple(let purple_url):
                DamusPurpleURLSheetView(damus_state: damus_state!, purple_url: purple_url)
            case .purple_onboarding:
                DamusPurpleNewUserOnboardingView(damus_state: damus_state)
            }
        }
        .onOpenURL { url in
            on_open_url(state: damus_state!, url: url) { res in
                guard let res else {
                    return
                }
                
                switch res {
                    case .filter(let filt): self.open_search(filt: filt)
                    case .profile(let pk):  self.open_profile(pubkey: pk)
                    case .event(let ev):    self.open_event(ev: ev)
                    case .wallet_connect(let nwc): self.open_wallet(nwc: nwc)
                    case .script(let data): self.open_script(data)
                    case .purple(let purple_url):
                        if case let .welcome(checkout_id) = purple_url.variant {
                            // If this is a welcome link, do the following before showing the onboarding screen:
                            // 1. Check if this is legitimate and good to go.
                            // 2. Mark as complete if this is good to go.
                            Task {
                                let is_good_to_go = try? await damus_state.purple.check_and_mark_ln_checkout_is_good_to_go(checkout_id: checkout_id)
                                if is_good_to_go == true {
                                    self.active_sheet = .purple(purple_url)
                                }
                            }
                        }
                        else {
                            self.active_sheet = .purple(purple_url)
                        }
                }
            }
        }
        .onReceive(handle_notify(.compose)) { action in
            self.active_sheet = .post(action)
        }
        .onReceive(handle_notify(.display_tabbar)) { display in
            let show = display
            self.hide_bar = !show
        }
        .onReceive(timer) { n in
            self.damus_state?.postbox.try_flushing_events()
            self.damus_state!.profiles.profile_data(self.damus_state!.pubkey).status.try_expire()
        }
        .onReceive(handle_notify(.report)) { target in
            self.active_sheet = .report(target)
        }
        .onReceive(handle_notify(.mute)) { mute_item in
            self.muting = mute_item
            self.confirm_mute = true
        }
        .onReceive(handle_notify(.attached_wallet)) { nwc in
            // update the lightning address on our profile when we attach a
            // wallet with an associated
            guard let ds = self.damus_state,
                  let lud16 = nwc.lud16,
                  let keypair = ds.keypair.to_full(),
                  let profile_txn = ds.profiles.lookup(id: ds.pubkey),
                  let profile = profile_txn.unsafeUnownedValue,
                  lud16 != profile.lud16 else {
                return
            }

            // clear zapper cache for old lud16
            if profile.lud16 != nil {
                // TODO: should this be somewhere else, where we process profile events!?
                invalidate_zapper_cache(pubkey: keypair.pubkey, profiles: ds.profiles, lnurl: ds.lnurls)
            }
            
            let prof = Profile(name: profile.name, display_name: profile.display_name, about: profile.about, picture: profile.picture, banner: profile.banner, website: profile.website, lud06: profile.lud06, lud16: lud16, nip05: profile.nip05, damus_donation: profile.damus_donation, reactions: profile.reactions)

            guard let ev = make_metadata_event(keypair: keypair, metadata: prof) else { return }
            ds.postbox.send(ev)
        }
        .onReceive(handle_notify(.broadcast)) { ev in
            guard let ds = self.damus_state else { return }

            ds.postbox.send(ev)
        }
        .onReceive(handle_notify(.unfollow)) { target in
            guard let state = self.damus_state else { return }
            _ = handle_unfollow(state: state, unfollow: target.follow_ref)
        }
        .onReceive(handle_notify(.unfollowed)) { unfollow in
            home.resubscribe(.unfollowing(unfollow))
        }
        .onReceive(handle_notify(.follow)) { target in
            guard let state = self.damus_state else { return }
            handle_follow_notif(state: state, target: target)
        }
        .onReceive(handle_notify(.followed)) { _ in
            home.resubscribe(.following)
        }
        .onReceive(handle_notify(.post)) { post in
            guard let state = self.damus_state,
                  let keypair = state.keypair.to_full() else {
                      return
            }

            if !handle_post_notification(keypair: keypair, postbox: state.postbox, events: state.events, post: post) {
                self.active_sheet = nil
            }
        }
        .onReceive(handle_notify(.new_mutes)) { _ in
            home.filter_events()
        }
        .onReceive(handle_notify(.mute_thread)) { _ in
            home.filter_events()
        }
        .onReceive(handle_notify(.unmute_thread)) { _ in
            home.filter_events()
        }
        .onReceive(handle_notify(.present_sheet)) { sheet in
            self.active_sheet = sheet
        }
        .onReceive(handle_notify(.zapping)) { zap_ev in
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
                    do {
                        try open_with_wallet(wallet: wallet, invoice: inv)
                    }
                    catch {
                        present_sheet(.select_wallet(invoice: inv))
                    }
                }
            case .sent_from_nwc:
                break
            }
        }
        .onReceive(handle_notify(.disconnect_relays)) { () in
            damus_state.pool.disconnect()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { obj in
            print("txn: 📙 DAMUS ACTIVE NOTIFY")
            if damus_state.ndb.reopen() {
                print("txn: NOSTRDB REOPENED")
            } else {
                print("txn: NOSTRDB FAILED TO REOPEN closed:\(damus_state.ndb.is_closed)")
            }
            if damus_state.purple.checkout_ids_in_progress.count > 0 {
                // For extra assurance, run this after one second, to avoid race conditions if the app is also handling a damus purple welcome url.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    Task {
                        let freshly_completed_checkout_ids = try? await damus_state.purple.check_status_of_checkouts_in_progress()
                        let there_is_a_completed_checkout: Bool = (freshly_completed_checkout_ids?.count ?? 0) > 0
                        let account_info = try await damus_state.purple.fetch_account(pubkey: self.keypair.pubkey)
                        if there_is_a_completed_checkout == true && account_info?.active == true {
                            if damus_state.purple.onboarding_status.user_has_never_seen_the_onboarding_before() {
                                // Show welcome sheet
                                self.active_sheet = .purple_onboarding
                            }
                            else {
                                self.active_sheet = .purple(DamusPurpleURL.init(is_staging: damus_state.purple.environment == .staging, variant: .landing))
                            }
                        }
                    }
                }
            }
            Task {
                await damus_state.purple.check_and_send_app_notifications_if_needed(handler: home.handle_damus_app_notification)
            }
        }
        .onChange(of: scenePhase) { (phase: ScenePhase) in
            guard let damus_state else { return }
            switch phase {
            case .background:
                print("txn: 📙 DAMUS BACKGROUNDED")
                Task { @MainActor in
                    damus_state.ndb.close()
                }
                break
            case .inactive:
                print("txn: 📙 DAMUS INACTIVE")
                break
            case .active:
                print("txn: 📙 DAMUS ACTIVE")
                damus_state.pool.ping()
            @unknown default:
                break
            }
        }
        .onReceive(handle_notify(.local_notification)) { local in
            guard let damus_state else { return }

            switch local.mention {
            case .pubkey(let pubkey):
                open_profile(pubkey: pubkey)

            case .note(let noteId):
                openEvent(noteId: noteId, notificationType: local.type)
            case .nevent(let nevent):
                openEvent(noteId: nevent.noteid, notificationType: local.type)
            case .nprofile(let nprofile):
                open_profile(pubkey: nprofile.author)
            case .nrelay(_):
                break
            case .naddr(let naddr):
                break
            }


        }
        .onReceive(handle_notify(.onlyzaps_mode)) { hide in
            home.filter_events()

            guard let ds = damus_state,
                  let profile_txn = ds.profiles.lookup(id: ds.pubkey),
                  let profile = profile_txn.unsafeUnownedValue,
                  let keypair = ds.keypair.to_full()
            else {
                return
            }

            let prof = Profile(name: profile.name, display_name: profile.display_name, about: profile.about, picture: profile.picture, banner: profile.banner, website: profile.website, lud06: profile.lud06, lud16: profile.lud16, nip05: profile.nip05, damus_donation: profile.damus_donation, reactions: !hide)

            guard let profile_ev = make_metadata_event(keypair: keypair, metadata: prof) else { return }
            ds.postbox.send(profile_ev)
        }
        .alert(NSLocalizedString("User muted", comment: "Alert message to indicate the user has been muted"), isPresented: $user_muted_confirm, actions: {
            Button(NSLocalizedString("Thanks!", comment: "Button to close out of alert that informs that the action to muted a user was successful.")) {
                user_muted_confirm = false
            }
        }, message: {
            if case let .user(pubkey, _) = self.muting {
                let profile_txn = damus_state!.profiles.lookup(id: pubkey)
                let profile = profile_txn?.unsafeUnownedValue
                let name = Profile.displayName(profile: profile, pubkey: pubkey).username.truncate(maxLength: 50)
                Text("\(name) has been muted", comment: "Alert message that informs a user was muted.")
            } else {
                Text("User has been muted", comment: "Alert message that informs a user was muted.")
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
                      let muting,
                      let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: muting)
                else {
                    return
                }
                
                ds.mutelist_manager.set_mutelist(mutelist)
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

                if ds.mutelist_manager.event == nil {
                    confirm_overwrite_mutelist = true
                } else {
                    guard let keypair = ds.keypair.to_full(),
                          let muting
                    else {
                        return
                    }

                    guard let ev = create_or_update_mutelist(keypair: keypair, mprev: ds.mutelist_manager.event, to_add: muting) else {
                        return
                    }

                    ds.mutelist_manager.set_mutelist(ev)
                    ds.postbox.send(ev)
                }
            }
        }, message: {
            if case let .user(pubkey, _) = muting {
                let profile_txn = damus_state?.profiles.lookup(id: pubkey)
                let profile = profile_txn?.unsafeUnownedValue
                let name = Profile.displayName(profile: profile, pubkey: pubkey).username.truncate(maxLength: 50)
                Text("Mute \(name)?", comment: "Alert message prompt to ask if a user should be muted.")
            } else {
                Text("Could not find user to mute...", comment: "Alert message to indicate that the muted user could not be found.")
            }
        })
    }
    
    func switch_timeline(_ timeline: Timeline) {
        self.isSideBarOpened = false
        let navWasAtRoot = self.navIsAtRoot()
        self.popToRoot()

        notify(.switched_timeline(timeline))

        if timeline == self.selected_timeline && navWasAtRoot {
            notify(.scroll_to_top)
            return
        }
        
        self.selected_timeline = timeline
    }

    func connect() {
        // nostrdb
        var mndb = Ndb()
        if mndb == nil {
            // try recovery
            print("DB ISSUE! RECOVERING")
            mndb = Ndb.safemode()

            // out of space or something?? maybe we need a in-memory fallback
            if mndb == nil {
                logout(nil)
                return
            }
        }

        guard let ndb = mndb else { return  }

        let pool = RelayPool(ndb: ndb, keypair: keypair)
        let model_cache = RelayModelCache()
        let relay_filters = RelayFilters(our_pubkey: pubkey)
        let bootstrap_relays = load_bootstrap_relays(pubkey: pubkey)
        
        let settings = UserSettingsStore.globally_load_for(pubkey: pubkey)

        let new_relay_filters = load_relay_filters(pubkey) == nil
        for relay in bootstrap_relays {
            let descriptor = RelayDescriptor(url: relay, info: .rw)
            add_new_relay(model_cache: model_cache, relay_filters: relay_filters, pool: pool, descriptor: descriptor, new_relay_filters: new_relay_filters, logging_enabled: settings.developer_mode)
        }

        pool.register_handler(sub_id: sub_id, handler: home.handle_event)
        
        if let nwc_str = settings.nostr_wallet_connect,
           let nwc = WalletConnectURL(str: nwc_str) {
            try? pool.add_relay(.nwc(url: nwc.relay))
        }

        self.damus_state = DamusState(pool: pool,
                                      keypair: keypair,
                                      likes: EventCounter(our_pubkey: pubkey),
                                      boosts: EventCounter(our_pubkey: pubkey),
                                      contacts: Contacts(our_pubkey: pubkey),
                                      mutelist_manager: MutelistManager(user_keypair: keypair),
                                      profiles: Profiles(ndb: ndb),
                                      dms: home.dms,
                                      previews: PreviewCache(),
                                      zaps: Zaps(our_pubkey: pubkey),
                                      lnurls: LNUrls(),
                                      settings: settings,
                                      relay_filters: relay_filters,
                                      relay_model_cache: model_cache,
                                      drafts: Drafts(),
                                      events: EventCache(ndb: ndb),
                                      bookmarks: BookmarksManager(pubkey: pubkey),
                                      postbox: PostBox(pool: pool),
                                      bootstrap_relays: bootstrap_relays,
                                      replies: ReplyCounter(our_pubkey: pubkey),
                                      wallet: WalletModel(settings: settings),
                                      nav: self.navigationCoordinator,
                                      music: MusicController(onChange: music_changed),
                                      video: VideoController(),
                                      ndb: ndb,
                                      quote_reposts: .init(our_pubkey: pubkey),
                                      emoji_provider: DefaultEmojiProvider(showAllVariations: true)
        )
        
        home.damus_state = self.damus_state!
        
        if let damus_state, damus_state.purple.enable_purple {
            // Assign delegate so that we can send receipts to the Purple API server as soon as we get updates from user's purchases
            StoreObserver.standard.delegate = damus_state.purple
            Task {
                await damus_state.purple.check_and_send_app_notifications_if_needed(handler: home.handle_damus_app_notification)
            }
        }
        else {
            // Purple API is an experimental feature. If not enabled, do not connect `StoreObserver` with Purple API to avoid leaking receipts
        }
        
        pool.connect()
    }

    func music_changed(_ state: MusicState) {
        guard let damus_state else { return }
        switch state {
        case .playback_state:
            break
        case .song(let song):
            guard let song, let kp = damus_state.keypair.to_full() else { return }

            let pdata = damus_state.profiles.profile_data(damus_state.pubkey)

            let desc = "\(song.title ?? "Unknown") - \(song.artist ?? "Unknown")"
            let encodedDesc = desc.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            let url = encodedDesc.flatMap { enc in
                URL(string: "spotify:search:\(enc)")
            }
            let music = UserStatus(type: .music, expires_at: Date.now.addingTimeInterval(song.playbackDuration), content: desc, created_at: UInt32(Date.now.timeIntervalSince1970), url: url)

            pdata.status.music = music

            guard let ev = music.to_note(keypair: kp) else { return }
            damus_state.postbox.send(ev)
        }
    }

    private func openEvent(noteId: NoteId, notificationType: LocalNotificationType) {
        guard let target = damus_state.events.lookup(noteId) else {
            return
        }

        switch notificationType {
        case .dm:
            selected_timeline = .dms
            damus_state.dms.set_active_dm(target.pubkey)
            navigationCoordinator.push(route: Route.DMChat(dms: damus_state.dms.active_model))
        case .like, .zap, .mention, .repost:
            open_event(ev: target)
        case .profile_zap:
            break
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(keypair: Keypair(pubkey: test_pubkey, privkey: nil), appDelegate: nil)
    }
}

func get_since_time(last_event: NostrEvent?) -> UInt32? {
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
    let id: NoteId
    let created_at: Int64
}

func get_last_event(_ timeline: Timeline) -> LastNotification? {
    let str = timeline.rawValue
    let last = UserDefaults.standard.string(forKey: "last_\(str)")
    let last_created = UserDefaults.standard.string(forKey: "last_\(str)_time")
        .flatMap { Int64($0) }

    guard let last,
          let note_id = NoteId(hex: last),
          let last_created
    else {
        return nil
    }

    return LastNotification(id: note_id, created_at: last_created)
}

func save_last_event(_ ev: NostrEvent, timeline: Timeline) {
    let str = timeline.rawValue
    UserDefaults.standard.set(ev.id.hex(), forKey: "last_\(str)")
    UserDefaults.standard.set(String(ev.created_at), forKey: "last_\(str)_time")
}

func save_last_event(_ ev_id: NoteId, created_at: UInt32, timeline: Timeline) {
    let str = timeline.rawValue
    UserDefaults.standard.set(ev_id.hex(), forKey: "last_\(str)")
    UserDefaults.standard.set(String(created_at), forKey: "last_\(str)_time")
}

func update_filters_with_since(last_of_kind: [UInt32: NostrEvent], filters: [NostrFilter]) -> [NostrFilter] {

    return filters.map { filter in
        let kinds = filter.kinds ?? []
        let initial: UInt32? = nil
        let earliest = kinds.reduce(initial) { earliest, kind in
            let last = last_of_kind[kind.rawValue]
            let since: UInt32? = get_since_time(last_event: last)

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
    this_app.registerForRemoteNotifications()
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
    let find_from: [RelayURL]?

    static func profile(pubkey: Pubkey, find_from: [RelayURL]? = nil) -> FindEvent {
        return FindEvent(type: .profile(pubkey), find_from: find_from)
    }

    static func event(evid: NoteId, find_from: [RelayURL]? = nil) -> FindEvent {
        return FindEvent(type: .event(evid), find_from: find_from)
    }
}

enum FindEventType {
    case profile(Pubkey)
    case event(NoteId)
}

enum FoundEvent {
    case profile(Pubkey)
    case invalid_profile(NostrEvent)
    case event(NostrEvent)
}

func find_event(state: DamusState, query query_: FindEvent, callback: @escaping (FoundEvent?) -> ()) {
    return find_event_with_subid(state: state, query: query_, subid: UUID().description, callback: callback)
}

func find_event_with_subid(state: DamusState, query query_: FindEvent, subid: String, callback: @escaping (FoundEvent?) -> ()) {

    var filter: NostrFilter? = nil
    let find_from = query_.find_from
    let query = query_.type
    
    switch query {
    case .profile(let pubkey):
        if let profile_txn = state.ndb.lookup_profile(pubkey),
           let record = profile_txn.unsafeUnownedValue,
           record.profile != nil
        {
            callback(.profile(pubkey))
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
                    guard state.ndb.lookup_profile_key(ev.pubkey) != nil else {
                        callback(.invalid_profile(ev))
                        return
                    }
                    callback(.profile(ev.pubkey))
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
        case .notice:
            break
        case .auth:
            break
        }

    }
}

func naddrLookup(damus_state: DamusState, naddr: NAddr, callback: @escaping (NostrEvent?) -> ()) {
    var nostrKinds: [NostrKind]? = NostrKind(rawValue: naddr.kind).map { [$0] }

    let filter = NostrFilter(kinds: nostrKinds, authors: [naddr.author])
    
    let subid = UUID().description
    
    damus_state.pool.subscribe_to(sub_id: subid, filters: [filter], to: nil) { relay_id, res  in
        guard case .nostr_event(let ev) = res else {
            damus_state.pool.unsubscribe(sub_id: subid, to: [relay_id])
            return
        }
        
        if case .event(_, let ev) = ev {
            for tag in ev.tags {
                if(tag.count >= 2 && tag[0].string() == "d"){
                    if (tag[1].string() == naddr.identifier){
                        damus_state.pool.unsubscribe(sub_id: subid, to: [relay_id])
                        callback(ev)
                        return
                    }
                }
            }
        }
        damus_state.pool.unsubscribe(sub_id: subid, to: [relay_id])
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

@discardableResult
func handle_unfollow(state: DamusState, unfollow: FollowRef) -> Bool {
    guard let keypair = state.keypair.to_full() else {
        return false
    }

    let old_contacts = state.contacts.event

    guard let ev = unfollow_reference(postbox: state.postbox, our_contacts: old_contacts, keypair: keypair, unfollow: unfollow)
    else {
        return false
    }

    notify(.unfollowed(unfollow))

    state.contacts.event = ev

    switch unfollow {
    case .pubkey(let pk):
        state.contacts.remove_friend(pk)
    case .hashtag:
        // nothing to handle here really
        break
    }

    return true
}

@discardableResult
func handle_follow(state: DamusState, follow: FollowRef) -> Bool {
    guard let keypair = state.keypair.to_full() else {
        return false
    }

    guard let ev = follow_reference(box: state.postbox, our_contacts: state.contacts.event, keypair: keypair, follow: follow)
    else {
        return false
    }

    notify(.followed(follow))

    state.contacts.event = ev
    switch follow {
    case .pubkey(let pubkey):
        state.contacts.add_friend_pubkey(pubkey)
    case .hashtag:
        // nothing to do
        break
    }

    return true
}

@discardableResult
func handle_follow_notif(state: DamusState, target: FollowTarget) -> Bool {
    switch target {
    case .pubkey(let pk):
        state.contacts.add_friend_pubkey(pk)
    case .contact(let ev):
        state.contacts.add_friend_contact(ev)
    }

    return handle_follow(state: state, follow: target.follow_ref)
}

func handle_post_notification(keypair: FullKeypair, postbox: PostBox, events: EventCache, post: NostrPostResult) -> Bool {
    switch post {
    case .post(let post):
        //let post = tup.0
        //let to_relays = tup.1
        print("post \(post.content)")
        guard let new_ev = post.to_event(keypair: keypair) else {
            return false
        }
        postbox.send(new_ev)
        for eref in new_ev.referenced_ids.prefix(3) {
            // also broadcast at most 3 referenced events
            if let ev = events.lookup(eref) {
                postbox.send(ev)
            }
        }
        for qref in new_ev.referenced_quote_ids.prefix(3) {
            // also broadcast at most 3 referenced quoted events
            if let ev = events.lookup(qref.note_id) {
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
    case profile(Pubkey)
    case filter(NostrFilter)
    case event(NostrEvent)
    case wallet_connect(WalletConnectURL)
    case script([UInt8])
    case purple(DamusPurpleURL)
}

func on_open_url(state: DamusState, url: URL, result: @escaping (OpenResult?) -> Void) {
    if let purple_url = DamusPurpleURL(url: url) {
        result(.purple(purple_url))
        return
    }
    
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
        switch ref {
        case .pubkey(let pk):
            result(.profile(pk))
        case .event(let noteid):
            find_event(state: state, query: .event(evid: noteid)) { res in
                guard let res, case .event(let ev) = res else { return }
                result(.event(ev))
            }
        case .hashtag(let ht):
            result(.filter(.filter_hashtag([ht.hashtag])))
        case .param, .quote, .reference:
            // doesn't really make sense here
            break
        case .naddr(let naddr):
            naddrLookup(damus_state: state, naddr: naddr) { res in
                guard let res = res else { return }
                result(.event(res))
            }
        }
    case .filter(let filt):
        result(.filter(filt))
        break
        // TODO: handle filter searches?
    case .script(let script):
        result(.script(script))
        break
    }
}


func logout(_ state: DamusState?)
{
    state?.close()
    notify(.logout)
}

