//
//  HomeModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation
import UIKit

enum Resubscribe {
    case following
    case unfollowing(FollowRef)
}

enum HomeResubFilter {
    case pubkey(Pubkey)
    case hashtag(String)

    init?(from: FollowRef) {
        switch from {
        case .hashtag(let ht): self = .hashtag(ht.string())
        case .pubkey(let pk):  self = .pubkey(pk)
        }

        return nil
    }

    func filter(contacts: Contacts, ev: NostrEvent) -> Bool {
        switch self {
        case .pubkey(let pk):
            return ev.pubkey == pk
        case .hashtag(let ht):
            if contacts.is_friend(ev.pubkey) {
                return false
            }
            return ev.referenced_hashtags.contains(where: { ref_ht in
                ht == ref_ht.hashtag
            })
        }
    }
}

class HomeModel: ContactsDelegate {
    // The maximum amount of contacts placed on a home feed subscription filter.
    // If the user has more contacts, chunking or other techniques will be used to avoid sending huge filters
    let MAX_CONTACTS_ON_FILTER = 500
    
    // Don't trigger a user notification for events older than a certain age
    static let event_max_age_for_notification: TimeInterval = EVENT_MAX_AGE_FOR_NOTIFICATION
    
    var damus_state: DamusState {
        didSet {
            self.load_our_stuff_from_damus_state()
        }
    }

    // NDBTODO: let's get rid of this entirely, let nostrdb handle it
    var has_event: [String: Set<NoteId>] = [:]
    var deleted_events: Set<NoteId> = Set()
    var last_event_of_kind: [RelayURL: [UInt32: NostrEvent]] = [:]
    var done_init: Bool = false
    var incoming_dms: [NostrEvent] = []
    let dm_debouncer = Debouncer(interval: 0.5)
    let resub_debouncer = Debouncer(interval: 3.0)
    var should_debounce_dms = true

    let home_subid = UUID().description
    let contacts_subid = UUID().description
    let notifications_subid = UUID().description
    let dms_subid = UUID().description
    let init_subid = UUID().description
    let profiles_subid = UUID().description
    
    var loading: Bool = false

    var signal = SignalModel()
    
    var notifications = NotificationsModel()
    var notification_status = NotificationStatusModel()
    var events: EventHolder = EventHolder()
    var already_reposted: Set<NoteId> = Set()
    var zap_button: ZapButtonModel = ZapButtonModel()
    
    init() {
        self.damus_state = DamusState.empty
        self.setup_debouncer()
        filter_events()
        events.on_queue = preloader
        //self.events = EventHolder(on_queue: preloader)
    }
    
    func preloader(ev: NostrEvent) {
        preload_events(state: self.damus_state, events: [ev])
    }
    
    var pool: RelayPool {
        self.damus_state.nostrNetwork.pool
    }
    
    var dms: DirectMessagesModel {
        return damus_state.dms
    }
    
    func has_sub_id_event(sub_id: String, ev_id: NoteId) -> Bool {
        if !has_event.keys.contains(sub_id) {
            has_event[sub_id] = Set()
            return false
        }

        return has_event[sub_id]!.contains(ev_id)
    }
    
    func setup_debouncer() {
        // turn off debouncer after initial load
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.should_debounce_dms = false
        }
    }
    
    // MARK: - Loading items from DamusState
    
    /// This is called whenever DamusState gets set. This function is used to load or setup anything we need from the new DamusState
    func load_our_stuff_from_damus_state() {
        self.load_latest_contact_event_from_damus_state()
        self.load_drafts_from_damus_state()
    }
    
    /// This loads the latest contact event we have on file from NostrDB. This should be called as soon as we get the new DamusState
    /// Loading the latest contact list event into our `Contacts` instance from storage is important to avoid getting into weird states when the network is unreliable or when relays delete such information
    func load_latest_contact_event_from_damus_state() {
        damus_state.contacts.delegate = self
        guard let latest_contact_event_id_hex = damus_state.settings.latest_contact_event_id_hex else { return }
        guard let latest_contact_event_id = NoteId(hex: latest_contact_event_id_hex) else { return }
        guard let latest_contact_event: NdbNote = damus_state.ndb.lookup_note( latest_contact_event_id)?.unsafeUnownedValue?.to_owned() else { return }
        process_contact_event(state: damus_state, ev: latest_contact_event)
    }
    
    func load_drafts_from_damus_state() {
        damus_state.drafts.load(from: damus_state)
    }
    
    // MARK: - ContactsDelegate functions
    
    func latest_contact_event_changed(new_event: NostrEvent) {
        // When the latest user contact event has changed, save its ID so we know exactly where to find it next time
        damus_state.settings.latest_contact_event_id_hex = new_event.id.hex()
    }
    
    // MARK: - Nostr event and subscription handling

    func resubscribe(_ resubbing: Resubscribe) {
        if self.should_debounce_dms {
            // don't resub on initial load
            return
        }

        print("hit resub debouncer")

        resub_debouncer.debounce {
            print("resub")
            self.unsubscribe_to_home_filters()

            switch resubbing {
            case .following:
                break
            case .unfollowing(let r):
                if let filter = HomeResubFilter(from: r) {
                    self.events.filter { ev in !filter.filter(contacts: self.damus_state.contacts, ev: ev) }
                }
            }

            self.subscribe_to_home_filters()
        }
    }

    @MainActor
    func process_event(sub_id: String, relay_id: RelayURL, ev: NostrEvent) {
        if has_sub_id_event(sub_id: sub_id, ev_id: ev.id) {
            return
        }

        let last_k = get_last_event_of_kind(relay_id: relay_id, kind: ev.kind)
        if last_k == nil || ev.created_at > last_k!.created_at {
            last_event_of_kind[relay_id]?[ev.kind] = ev
        }

        guard let kind = ev.known_kind else {
            return
        }

        switch kind {
        case .chat, .longform, .text, .highlight:
            handle_text_event(sub_id: sub_id, ev)
        case .contacts:
            handle_contact_event(sub_id: sub_id, relay_id: relay_id, ev: ev)
        case .metadata:
            // profile metadata processing is handled by nostrdb
            break
        case .list_deprecated:
            handle_old_list_event(ev)
        case .mute_list:
            handle_mute_list_event(ev)
        case .boost:
            handle_boost_event(sub_id: sub_id, ev)
        case .like:
            handle_like_event(ev)
        case .dm:
            handle_dm(ev)
        case .delete:
            handle_delete_event(ev)
        case .zap:
            handle_zap_event(ev)
        case .zap_request:
            break
        case .nwc_request:
            break
        case .nwc_response:
            handle_nwc_response(ev, relay: relay_id)
        case .http_auth:
            break
        case .status:
            handle_status_event(ev)
        case .draft:
            // TODO: Implement draft syncing with relays. We intentionally do not support that as of writing. See `DraftsModel.swift` for other details
            // try? damus_state.drafts.load(wrapped_draft_note: ev, with: damus_state)
            break
        case .relay_list:
            break   // This will be handled by `UserRelayListManager`
        }
    }

    @MainActor
    func handle_status_event(_ ev: NostrEvent) {
        guard let st = UserStatus(ev: ev) else {
            return
        }

        // don't process expired events
        if let expires = st.expires_at, Date.now >= expires {
            return
        }

        let pdata = damus_state.profiles.profile_data(ev.pubkey)

        // don't use old events
        if st.type == .music,
           let music = pdata.status.music,
           ev.created_at < music.created_at {
            return
        } else if st.type == .general,
                  let general = pdata.status.general,
                  ev.created_at < general.created_at {
            return
        }

        pdata.status.update_status(st)
    }

    func handle_nwc_response(_ ev: NostrEvent, relay: RelayURL) {
        Task { @MainActor in
            // TODO: Adapt KeychainStorage to StringCodable and instead of parsing to WalletConnectURL every time
            guard let nwc_str = damus_state.settings.nostr_wallet_connect,
                  let nwc = WalletConnectURL(str: nwc_str) else {
                return
            }
            
            guard nwc.relay == relay else { return }    // Don't process NWC responses coming from relays other than our designated one
            guard ev.referenced_pubkeys.first == nwc.keypair.pubkey else {
                return      // This message is not for us. Ignore it.
            }
            
            var resp: WalletConnect.FullWalletResponse? = nil
            do {
                resp = try await WalletConnect.FullWalletResponse(from: ev, nwc: nwc)
            } catch {
                Log.error("HomeModel: Error on NWC wallet response handling: %s", for: .nwc, error.localizedDescription)
                if let initError = error as? WalletConnect.FullWalletResponse.InitializationError,
                   let humanReadableError = initError.humanReadableError {
                    present_sheet(.error(humanReadableError))
                }
            }
            guard let resp else { return }
            
            // since command results are not returned for ephemeral events,
            // remove the request from the postbox which is likely failing over and over
            if damus_state.nostrNetwork.postbox.remove_relayer(relay_id: nwc.relay, event_id: resp.req_id) {
                Log.debug("HomeModel: got NWC response, removed %s from the postbox [%s]", for: .nwc, resp.req_id.hex(), relay.absoluteString)
            } else {
                Log.debug("HomeModel: got NWC response, %s not found in the postbox, nothing to remove [%s]", for: .nwc, resp.req_id.hex(), relay.absoluteString)
            }
            
            guard resp.response.error == nil else {
                Log.error("HomeModel: NWC wallet raised an error: %s", for: .nwc, String(describing: resp.response))
                WalletConnect.handle_error(zapcache: self.damus_state.zaps, evcache: self.damus_state.events, resp: resp)
                if let humanReadableError = resp.response.error?.humanReadableError {
                    present_sheet(.error(humanReadableError))
                }
                return
            }
            
            if resp.response.result_type == .list_transactions {
                Log.info("Received NWC transaction list from %s", for: .nwc, relay.absoluteString)
                damus_state.wallet.handle_nwc_response(response: resp)
                return
            }
            
            if resp.response.result_type == .get_balance {
                Log.info("Received NWC balance information from %s", for: .nwc, relay.absoluteString)
                damus_state.wallet.handle_nwc_response(response: resp)
                return
            }

            print("nwc success: \(resp.response.result.debugDescription) [\(relay)]")
            WalletConnect.handle_zap_success(state: self.damus_state, resp: resp)
        }
    }

    @MainActor
    func handle_zap_event(_ ev: NostrEvent) {
        process_zap_event(state: damus_state, ev: ev) { zapres in
            guard case .done(let zap) = zapres,
                  zap.target.pubkey == self.damus_state.keypair.pubkey,
                  should_show_event(state: self.damus_state, ev: zap.request.ev) else {
                return
            }
        
            if !self.notifications.insert_zap(.zap(zap)) {
                return
            }

            guard let new_bits = handle_last_events(new_events: self.notification_status.new_events, ev: ev, timeline: .notifications, shouldNotify: true) else {
                return
            }
            
            if self.damus_state.settings.zap_vibration {
                // Generate zap vibration
                zap_vibrate(zap_amount: zap.invoice.amount)
            }
            
            if self.damus_state.settings.zap_notification {
                // Create in-app local notification for zap received.
                switch zap.target {
                case .profile(let profile_id):
                    create_in_app_profile_zap_notification(profiles: self.damus_state.profiles, zap: zap, profile_id: profile_id)
                case .note(let note_target):
                    create_in_app_event_zap_notification(profiles: self.damus_state.profiles, zap: zap, evId: note_target.note_id)
                }
            }
            
            self.notification_status.new_events = new_bits
        }
        
    }
    
    @MainActor
    func handle_damus_app_notification(_ notification: DamusAppNotification) async {
        if self.notifications.insert_app_notification(notification: notification) {
            let last_notification = get_last_event(.notifications)
            if last_notification == nil || last_notification!.created_at < notification.last_event_at {
                save_last_event(NoteId.empty, created_at: notification.last_event_at, timeline: .notifications)
                // If we successfully inserted a new Damus App notification, switch ON the Damus App notification bit on our NewsEventsBits
                // This will cause the bell icon on the tab bar to display the purple dot indicating there is an unread notification
                self.notification_status.new_events = NewEventsBits(rawValue: self.notification_status.new_events.rawValue | NewEventsBits.damus_app_notifications.rawValue)
            }
            return
        }
    }
    
    func filter_events() {
        events.filter { ev in
            !damus_state.mutelist_manager.is_muted(.user(ev.pubkey, nil))
        }
        
        self.dms.dms = dms.dms.filter { ev in
            !damus_state.mutelist_manager.is_muted(.user(ev.pubkey, nil))
        }
        
        notifications.filter { ev in
            if damus_state.settings.onlyzaps_mode && ev.known_kind == NostrKind.like {
                return false
            }

            let event_muted = damus_state.mutelist_manager.is_event_muted(ev)
            return !event_muted
        }
    }
    
    func handle_delete_event(_ ev: NostrEvent) {
        self.deleted_events.insert(ev.id)
    }

    func handle_contact_event(sub_id: String, relay_id: RelayURL, ev: NostrEvent) {
        process_contact_event(state: self.damus_state, ev: ev)

        if sub_id == init_subid {
            pool.send(.unsubscribe(init_subid), to: [relay_id])
            if !done_init {
                done_init = true
                send_home_filters(relay_id: nil)
            }
        }
    }

    func handle_boost_event(sub_id: String, _ ev: NostrEvent) {
        var boost_ev_id = ev.last_refid()

        if let inner_ev = ev.get_inner_event(cache: damus_state.events) {
            boost_ev_id = inner_ev.id

            Task {
                // NOTE (jb55): remove this after nostrdb update, since nostrdb
                // processess reposts when note is ingested
                guard validate_event(ev: inner_ev) == .ok else {
                    return
                }
                
                if inner_ev.is_textlike {
                    DispatchQueue.main.async {
                        self.handle_text_event(sub_id: sub_id, ev)
                    }
                }
            }
        }

        guard let e = boost_ev_id else {
            return
        }

        switch self.damus_state.boosts.add_event(ev, target: e) {
        case .already_counted:
            break
        case .success(_):
            notify(.update_stats(note_id: e))
        }
    }

    func handle_quote_repost_event(_ ev: NostrEvent, target: NoteId) {
        switch damus_state.quote_reposts.add_event(ev, target: target) {
        case .already_counted:
            break
        case .success(_):
            notify(.update_stats(note_id: target))
        }
    }

    func handle_like_event(_ ev: NostrEvent) {
        guard let e = ev.last_refid() else {
            // no id ref? invalid like event
            return
        }

        if damus_state.settings.onlyzaps_mode {
            return
        }

        switch damus_state.likes.add_event(ev, target: e) {
        case .already_counted:
            break
        case .success(let n):
            handle_notification(ev: ev)
            let liked = Counted(event: ev, id: e, total: n)
            notify(.liked(liked))
            notify(.update_stats(note_id: e))
        }
    }

    @MainActor
    func handle_event(relay_id: RelayURL, conn_event: NostrConnectionEvent) {
        switch conn_event {
        case .ws_event(let ev):
            switch ev {
            case .connected:
                if !done_init {
                    self.loading = true
                    send_initial_filters(relay_id: relay_id)
                } else {
                    //remove_bootstrap_nodes(damus_state)
                    send_home_filters(relay_id: relay_id)
                }
                
                // connect to nwc relays when connected
                if let nwc_str = damus_state.settings.nostr_wallet_connect,
                   let r = pool.get_relay(relay_id),
                   r.descriptor.variant == .nwc,
                   let nwc = WalletConnectURL(str: nwc_str),
                   nwc.relay == relay_id
                {
                    WalletConnect.subscribe(url: nwc, pool: pool)
                }
            case .error(let merr):
                let desc = String(describing: merr)
                if desc.contains("Software caused connection abort") {
                    pool.reconnect(to: [relay_id])
                }
            case .disconnected:
                pool.reconnect(to: [relay_id])
            default:
                break
            }
            
            update_signal_from_pool(signal: self.signal, pool: damus_state.nostrNetwork.pool)
        case .nostr_event(let ev):
            switch ev {
            case .event(let sub_id, let ev):
                // globally handle likes
                /*
                let always_process = sub_id == notifications_subid || sub_id == contacts_subid || sub_id == home_subid || sub_id == dms_subid || sub_id == init_subid || ev.known_kind == .like || ev.known_kind == .boost || ev.known_kind == .zap || ev.known_kind == .contacts || ev.known_kind == .metadata
                if !always_process {
                    // TODO: other views like threads might have their own sub ids, so ignore those events... or should we?
                    return
                }
                */

                self.process_event(sub_id: sub_id, relay_id: relay_id, ev: ev)
            case .notice(let msg):
                print(msg)

            case .eose(let sub_id):
                guard let txn = NdbTxn(ndb: damus_state.ndb) else {
                    return
                }

                if sub_id == dms_subid {
                    var dms = dms.dms.flatMap { $0.events }
                    dms.append(contentsOf: incoming_dms)
                    load_profiles(context: "dms", profiles_subid: profiles_subid, relay_id: relay_id, load: .from_events(dms), damus_state: damus_state, txn: txn)
                } else if sub_id == notifications_subid {
                    load_profiles(context: "notifications", profiles_subid: profiles_subid, relay_id: relay_id, load: .from_keys(notifications.uniq_pubkeys()), damus_state: damus_state, txn: txn)
                } else if sub_id == home_subid {
                    load_profiles(context: "home", profiles_subid: profiles_subid, relay_id: relay_id, load: .from_events(events.events), damus_state: damus_state, txn: txn)
                }
                
                self.loading = false
                break
                
            case .ok:
                break
            case .auth:
                break
            }
            
        }
    }


    /// Send the initial filters, just our contact list mostly
    func send_initial_filters(relay_id: RelayURL) {
        let filter = NostrFilter(kinds: [.contacts], limit: 1, authors: [damus_state.pubkey])
        let subscription = NostrSubscribe(filters: [filter], sub_id: init_subid)
        pool.send(.subscribe(subscription), to: [relay_id])
    }

    /// After initial connection or reconnect, send subscription filters for the home timeline, DMs, and notifications
    func send_home_filters(relay_id: RelayURL?) {
        // TODO: since times should be based on events from a specific relay
        // perhaps we could mark this in the relay pool somehow

        let friends = get_friends()

        var contacts_filter = NostrFilter(kinds: [.metadata])
        contacts_filter.authors = friends

        var our_contacts_filter = NostrFilter(kinds: [.contacts, .metadata])
        our_contacts_filter.authors = [damus_state.pubkey]
        
        var our_old_blocklist_filter = NostrFilter(kinds: [.list_deprecated])
        our_old_blocklist_filter.parameter = ["mute"]
        our_old_blocklist_filter.authors = [damus_state.pubkey]

        var our_blocklist_filter = NostrFilter(kinds: [.mute_list])
        our_blocklist_filter.authors = [damus_state.pubkey]

        var dms_filter = NostrFilter(kinds: [.dm])

        var our_dms_filter = NostrFilter(kinds: [.dm])

        // friends only?...
        //dms_filter.authors = friends
        dms_filter.limit = 500
        dms_filter.pubkeys = [ damus_state.pubkey ]
        our_dms_filter.authors = [ damus_state.pubkey ]

        var notifications_filter_kinds: [NostrKind] = [
            .text,
            .boost,
            .zap,
        ]
        if !damus_state.settings.onlyzaps_mode {
            notifications_filter_kinds.append(.like)
        }
        var notifications_filter = NostrFilter(kinds: notifications_filter_kinds)
        notifications_filter.pubkeys = [damus_state.pubkey]
        notifications_filter.limit = 500

        var notifications_filters = [notifications_filter]
        let contacts_filter_chunks = contacts_filter.chunked(on: .authors, into: MAX_CONTACTS_ON_FILTER)
        var contacts_filters = contacts_filter_chunks + [our_contacts_filter, our_blocklist_filter, our_old_blocklist_filter]
        var dms_filters = [dms_filter, our_dms_filter]
        let last_of_kind = get_last_of_kind(relay_id: relay_id)

        contacts_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: contacts_filters)
        notifications_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: notifications_filters)
        dms_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: dms_filters)

        //print_filters(relay_id: relay_id, filters: [home_filters, contacts_filters, notifications_filters, dms_filters])

        subscribe_to_home_filters(relay_id: relay_id)

        let relay_ids = relay_id.map { [$0] }

        pool.send(.subscribe(.init(filters: contacts_filters, sub_id: contacts_subid)), to: relay_ids)
        pool.send(.subscribe(.init(filters: notifications_filters, sub_id: notifications_subid)), to: relay_ids)
        pool.send(.subscribe(.init(filters: dms_filters, sub_id: dms_subid)), to: relay_ids)
    }

    func get_last_of_kind(relay_id: RelayURL?) -> [UInt32: NostrEvent] {
        return relay_id.flatMap { last_event_of_kind[$0] } ?? [:]
    }

    func unsubscribe_to_home_filters() {
        pool.send(.unsubscribe(home_subid))
    }

    func get_friends() -> [Pubkey] {
        var friends = damus_state.contacts.get_friend_list()
        friends.insert(damus_state.pubkey)
        return Array(friends)
    }

    func subscribe_to_home_filters(friends fs: [Pubkey]? = nil, relay_id: RelayURL? = nil) {
        // TODO: separate likes?
        var home_filter_kinds: [NostrKind] = [
            .text, .longform, .boost, .highlight
        ]
        if !damus_state.settings.onlyzaps_mode {
            home_filter_kinds.append(.like)
        }

        // only pull status data if we care for it
        if damus_state.settings.show_music_statuses || damus_state.settings.show_general_statuses {
            home_filter_kinds.append(.status)
        }

        let friends = fs ?? get_friends()
        var home_filter = NostrFilter(kinds: home_filter_kinds)
        // include our pubkey as well even if we're not technically a friend
        home_filter.authors = friends
        home_filter.limit = 500

        var home_filters = home_filter.chunked(on: .authors, into: MAX_CONTACTS_ON_FILTER)

        let followed_hashtags = Array(damus_state.contacts.get_followed_hashtags())
        if followed_hashtags.count != 0 {
            var hashtag_filter = NostrFilter.filter_hashtag(followed_hashtags)
            hashtag_filter.limit = 100
            home_filters.append(hashtag_filter)
        }

        let relay_ids = relay_id.map { [$0] }
        home_filters = update_filters_with_since(last_of_kind: get_last_of_kind(relay_id: relay_id), filters: home_filters)
        let sub = NostrSubscribe(filters: home_filters, sub_id: home_subid)

        pool.send(.subscribe(sub), to: relay_ids)
    }

    func handle_mute_list_event(_ ev: NostrEvent) {
        // we only care about our mutelist
        guard ev.pubkey == damus_state.pubkey else {
            return
        }

        // we only care about the most recent mutelist
        if let mutelist = damus_state.mutelist_manager.event {
            if ev.created_at <= mutelist.created_at {
                return
            }
        }

        damus_state.mutelist_manager.set_mutelist(ev)

        migrate_old_muted_threads_to_new_mutelist(keypair: damus_state.keypair, damus_state: damus_state)
    }

    func handle_old_list_event(_ ev: NostrEvent) {
        // we only care about our lists
        guard ev.pubkey == damus_state.pubkey else {
            return
        }
        
        // we only care about the most recent mutelist
        if let mutelist = damus_state.mutelist_manager.event {
            if ev.created_at <= mutelist.created_at {
                return
            }
        }
        
        guard ev.referenced_params.contains(where: { p in p.param.matches_str("mute") }) else {
            return
        }

        damus_state.mutelist_manager.set_mutelist(ev)

        migrate_old_muted_threads_to_new_mutelist(keypair: damus_state.keypair, damus_state: damus_state)
    }

    func get_last_event_of_kind(relay_id: RelayURL, kind: UInt32) -> NostrEvent? {
        guard let m = last_event_of_kind[relay_id] else {
            last_event_of_kind[relay_id] = [:]
            return nil
        }

        return m[kind]
    }
    
    func handle_notification(ev: NostrEvent) {
        // don't show notifications from ourselves
        guard ev.pubkey != damus_state.pubkey,
              event_has_our_pubkey(ev, our_pubkey: self.damus_state.pubkey),
              should_show_event(state: damus_state, ev: ev) else {
            return
        }
        
        damus_state.events.insert(ev)
        
        if let inner_ev = ev.get_inner_event(cache: damus_state.events) {
            damus_state.events.insert(inner_ev)
        }
        
        if !notifications.insert_event(ev, damus_state: damus_state) {
            return
        }
        
        if handle_last_event(ev: ev, timeline: .notifications) {
            process_local_notification(state: damus_state, event: ev)
        }
        
    }

    @discardableResult
    func handle_last_event(ev: NostrEvent, timeline: Timeline, shouldNotify: Bool = true) -> Bool {
        if let new_bits = handle_last_events(new_events: self.notification_status.new_events, ev: ev, timeline: timeline, shouldNotify: shouldNotify) {
            self.notification_status.new_events = new_bits
            return true
        } else {
            return false
        }
    }

    func insert_home_event(_ ev: NostrEvent) {
        if events.insert(ev) {
            handle_last_event(ev: ev, timeline: .home)
        }
    }


    func handle_text_event(sub_id: String, _ ev: NostrEvent) {
        guard should_show_event(state: damus_state, ev: ev) else {
            return
        }
        
        // TODO: will we need to process this in other places like zap request contents, etc?
        process_image_metadatas(cache: damus_state.events, ev: ev)
        damus_state.replies.count_replies(ev, keypair: self.damus_state.keypair)
        damus_state.events.insert(ev)

        if let quoted_event = ev.referenced_quote_ids.first {
            handle_quote_repost_event(ev, target: quoted_event.note_id)
        }

        // don't add duplicate reposts to home
        if ev.known_kind == .boost, let target = ev.get_inner_event()?.id {
            if already_reposted.contains(target) {
                Log.info("Skipping duplicate repost for event %s", for: .timeline, target.hex())
                return
            } else {
                already_reposted.insert(target)
            }
        }

        if sub_id == home_subid {
            insert_home_event(ev)
        } else if sub_id == notifications_subid {
            handle_notification(ev: ev)
        }
    }
    
    func got_new_dm(notifs: NewEventsBits, ev: NostrEvent) {
        notification_status.new_events = notifs
        
        guard should_display_notification(state: damus_state, event: ev, mode: .local),
              let notification_object = generate_local_notification_object(ndb: self.damus_state.ndb, from: ev, state: damus_state)
        else {
            return
        }
        
        create_local_notification(profiles: damus_state.profiles, notify: notification_object)
    }
    
    func handle_dm(_ ev: NostrEvent) {
        guard should_show_event(state: damus_state, ev: ev) else {
            return
        }
        
        damus_state.events.insert(ev)
        
        if !should_debounce_dms {
            self.incoming_dms.append(ev)
            if let notifs = handle_incoming_dms(prev_events: notification_status.new_events, dms: self.dms, our_pubkey: self.damus_state.pubkey, evs: self.incoming_dms) {
                got_new_dm(notifs: notifs, ev: ev)
            }
            self.incoming_dms = []
            return
        }
        
        incoming_dms.append(ev)
        
        dm_debouncer.debounce { [self] in
            if let notifs = handle_incoming_dms(prev_events: notification_status.new_events, dms: self.dms, our_pubkey: self.damus_state.pubkey, evs: self.incoming_dms) {
                got_new_dm(notifs: notifs, ev: ev)
            }
            self.incoming_dms = []
        }
    }
}


func update_signal_from_pool(signal: SignalModel, pool: RelayPool) {
    if signal.max_signal != pool.relays.count {
        signal.max_signal = pool.relays.count
    }

    if signal.signal != pool.num_connected {
        signal.signal = pool.num_connected
    }
}

func add_contact_if_friend(contacts: Contacts, ev: NostrEvent) {
    if !contacts.is_friend(ev.pubkey) {
        return
    }

    contacts.add_friend_contact(ev)
}

func load_our_contacts(state: DamusState, m_old_ev: NostrEvent?, ev: NostrEvent) {
    let contacts = state.contacts
    let new_refs = Set<FollowRef>(ev.referenced_follows)
    let old_refs = m_old_ev.map({ old_ev in Set(old_ev.referenced_follows) }) ?? Set()

    let diff = new_refs.symmetricDifference(old_refs)
    for ref in diff {
        if new_refs.contains(ref) {
            notify(.followed(ref))
            switch ref {
            case .pubkey(let pk):
                contacts.add_friend_pubkey(pk)
            case .hashtag:
                // I guess I could cache followed hashtags here... whatever
                break
            }
        } else {
            notify(.unfollowed(ref))
            switch ref {
            case .pubkey(let pk):
                contacts.remove_friend(pk)
            case .hashtag: break
            }
        }
    }
}


func abbrev_ids(_ ids: [String]) -> String {
    if ids.count > 5 {
        let n = ids.count - 5
        return "[" + ids[..<5].joined(separator: ",") + ", ... (\(n) more)]"
    }
    return "\(ids)"
}

func abbrev_field<T: CustomStringConvertible>(_ n: String, _ field: T?) -> String {
    guard let field = field else {
        return ""
    }

    return "\(n):\(field.description)"
}

func abbrev_ids_field(_ n: String, _ ids: [String]?) -> String {
    guard let ids = ids else {
        return ""
    }

    return "\(n): \(abbrev_ids(ids))"
}

/*
func print_filter(_ f: NostrFilter) {
    let fmt = [
        abbrev_ids_field("ids", f.ids),
        abbrev_field("kinds", f.kinds),
        abbrev_ids_field("authors", f.authors),
        abbrev_ids_field("referenced_ids", f.referenced_ids),
        abbrev_ids_field("pubkeys", f.pubkeys),
        abbrev_field("since", f.since),
        abbrev_field("until", f.until),
        abbrev_field("limit", f.limit)
    ].filter({ !$0.isEmpty }).joined(separator: ",")

    print("Filter(\(fmt))")
}

func print_filters(relay_id: String?, filters groups: [[NostrFilter]]) {
    let relays = relay_id ?? "relays"
    print("connected to \(relays) with filters:")
    for group in groups {
        for filter in group {
            print_filter(filter)
        }
    }
    print("-----")
}
 */

// TODO: remove this, let nostrdb handle all validation
func guard_valid_event(events: EventCache, ev: NostrEvent, callback: @escaping () -> Void) {
    let validated = events.is_event_valid(ev.id)
    
    switch validated {
    case .unknown:
        Task.detached(priority: .medium) {
            let result = validate_event(ev: ev)
            
            DispatchQueue.main.async {
                events.store_event_validation(evid: ev.id, validated: result)
                guard result == .ok else {
                    return
                }
                callback()
            }
        }
        
    case .ok:
        callback()
        
    case .bad_id, .bad_sig:
        break
    }
}

func robohash(_ pk: Pubkey) -> String {
    return "https://robohash.org/" + pk.hex()
}

func load_our_stuff(state: DamusState, ev: NostrEvent) {
    guard ev.pubkey == state.pubkey else {
        return
    }
    
    // only use new stuff
    if let current_ev = state.contacts.event {
        guard ev.created_at > current_ev.created_at else {
            return
        }
    }
    
    let m_old_ev = state.contacts.event
    state.contacts.event = ev

    load_our_contacts(state: state, m_old_ev: m_old_ev, ev: ev)
}

func process_contact_event(state: DamusState, ev: NostrEvent) {
    load_our_stuff(state: state, ev: ev)
    add_contact_if_friend(contacts: state.contacts, ev: ev)
}

func fetch_relay_metadata(relay_id: RelayURL) async throws -> RelayMetadata? {
    var urlString = relay_id.absoluteString.replacingOccurrences(of: "wss://", with: "https://")
    urlString = urlString.replacingOccurrences(of: "ws://", with: "http://")

    guard let url = URL(string: urlString) else {
        return nil
    }
    
    var request = URLRequest(url: url)
    request.setValue("application/nostr+json", forHTTPHeaderField: "Accept")
    
    var res: (Data, URLResponse)? = nil
    
    res = try await URLSession.shared.data(for: request)
    
    guard let data = res?.0 else {
        return nil
    }
    
    let nip11 = try JSONDecoder().decode(RelayMetadata.self, from: data)
    return nip11
}

@discardableResult
func handle_incoming_dm(ev: NostrEvent, our_pubkey: Pubkey, dms: DirectMessagesModel, prev_events: NewEventsBits) -> (Bool, NewEventsBits?) {
    var inserted = false
    var found = false
    
    let ours = ev.pubkey == our_pubkey
    var i = 0

    var the_pk = ev.pubkey
    if ours {
        if let ref_pk = ev.referenced_pubkeys.first {
            the_pk = ref_pk
        } else {
            // self dm!?
            print("TODO: handle self dm?")
        }
    }

    for model in dms.dms {
        if model.pubkey == the_pk {
            found = true
            inserted = insert_uniq_sorted_event(events: &(dms.dms[i].events), new_ev: ev) {
                $0.created_at < $1.created_at
            }

            break
        }
        i += 1
    }

    if !found {
        let model = DirectMessageModel(events: [ev], our_pubkey: our_pubkey, pubkey: the_pk)
        dms.dms.append(model)
        inserted = true
    }
    
    var new_bits: NewEventsBits? = nil
    if inserted {
        new_bits = handle_last_events(new_events: prev_events, ev: ev, timeline: .dms, shouldNotify: !ours)
    }
    
    return (inserted, new_bits)
}

@discardableResult
func handle_incoming_dms(prev_events: NewEventsBits, dms: DirectMessagesModel, our_pubkey: Pubkey, evs: [NostrEvent]) -> NewEventsBits? {
    var inserted = false

    var new_events: NewEventsBits? = nil
    
    for ev in evs {
        let res = handle_incoming_dm(ev: ev, our_pubkey: our_pubkey, dms: dms, prev_events: prev_events)
        inserted = res.0 || inserted
        if let new = res.1 {
            new_events = new
        }
    }
    
    if inserted {
        let new_dms = Array(dms.dms.filter({ $0.events.count > 0 })).sorted { a, b in
            return a.events.last!.created_at > b.events.last!.created_at
        }
        
        dms.dms = new_dms
    }
    
    return new_events
}

func determine_event_notifications(_ ev: NostrEvent) -> NewEventsBits {
    guard let kind = ev.known_kind else {
        return []
    }
    
    if kind == .zap {
        return [.zaps]
    }
    
    if kind == .boost {
        return [.reposts]
    }
    
    if kind == .text {
        return [.mentions]
    }
    
    if kind == .like {
        return [.likes]
    }
    
    return []
}

func timeline_to_notification_bits(_ timeline: Timeline, ev: NostrEvent?) -> NewEventsBits {
    switch timeline {
    case .home:
        return [.home]
    case .notifications:
        if let ev {
            return determine_event_notifications(ev)
        }
        return [.notifications]
    case .search:
        return [.search]
    case .dms:
        return [.dms]
    }
}

/// A helper to determine if we need to notify the user of new events
func handle_last_events(new_events: NewEventsBits, ev: NostrEvent, timeline: Timeline, shouldNotify: Bool = true) -> NewEventsBits? {
    let last_ev = get_last_event(timeline)

    if last_ev == nil || last_ev!.created_at < ev.created_at {
        save_last_event(ev, timeline: timeline)
        if shouldNotify {
            return new_events.union(timeline_to_notification_bits(timeline, ev: ev))
        }
    }
    
    return nil
}


/// Sometimes we get garbage in our notifications. Ensure we have our pubkey on this event
func event_has_our_pubkey(_ ev: NostrEvent, our_pubkey: Pubkey) -> Bool {
    return ev.referenced_pubkeys.contains(our_pubkey)
}

func should_show_event(event: NostrEvent, damus_state: DamusState) -> Bool {
    return should_show_event(
        state: damus_state,
        ev: event
    )
}

func should_show_event(state: DamusState, ev: NostrEvent) -> Bool {
    let event_muted = state.mutelist_manager.is_event_muted(ev)
    if event_muted {
        return false
    }

    return ev.should_show_event
}

func zap_vibrate(zap_amount: Int64) {
    let sats = zap_amount / 1000
    var vibration_generator: UIImpactFeedbackGenerator
    if sats >= 10000 {
        vibration_generator = UIImpactFeedbackGenerator(style: .heavy)
    } else if sats >= 1000 {
        vibration_generator = UIImpactFeedbackGenerator(style: .medium)
    } else {
        vibration_generator = UIImpactFeedbackGenerator(style: .light)
    }
    vibration_generator.impactOccurred()
}

func create_in_app_profile_zap_notification(profiles: Profiles, zap: Zap, locale: Locale = Locale.current, profile_id: Pubkey) {
    let content = UNMutableNotificationContent()

    content.title = NotificationFormatter.zap_notification_title(zap)
    content.body = NotificationFormatter.zap_notification_body(profiles: profiles, zap: zap, locale: locale)
    content.sound = UNNotificationSound.default
    content.userInfo = LossyLocalNotification(type: .profile_zap, mention: .init(nip19: .npub(profile_id))).to_user_info()

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

    let request = UNNotificationRequest(identifier: "myZapNotification", content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Error: \(error)")
        } else {
            print("Local notification scheduled")
        }
    }
}

func create_in_app_event_zap_notification(profiles: Profiles, zap: Zap, locale: Locale = Locale.current, evId: NoteId) {
    let content = UNMutableNotificationContent()

    content.title = NotificationFormatter.zap_notification_title(zap)
    content.body = NotificationFormatter.zap_notification_body(profiles: profiles, zap: zap, locale: locale)
    content.sound = UNNotificationSound.default
    content.userInfo = LossyLocalNotification(type: .zap, mention: .note(evId)).to_user_info()

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

    let request = UNNotificationRequest(identifier: "myZapNotification", content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Error: \(error)")
        } else {
            print("Local notification scheduled")
        }
    }
}

