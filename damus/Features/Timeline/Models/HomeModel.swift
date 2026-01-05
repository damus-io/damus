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

@MainActor
class HomeModel: ContactsDelegate, ObservableObject {
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
    let notifications_resub_debouncer = Debouncer(interval: 2.0)
    var should_debounce_dms = true

    var homeHandlerTask: Task<Void, Never>?
    var notificationsHandlerTask: Task<Void, Never>?
    var generalHandlerTask: Task<Void, Never>?
    var ndbOnlyHandlerTask: Task<Void, Never>?
    var nwcHandlerTask: Task<Void, Never>?
    
    @Published var loading: Bool = true

    var signal = SignalModel()
    
    var notifications = NotificationsModel()
    var notification_status = NotificationStatusModel()
    var events: EventHolder = EventHolder()
    var already_reposted: Set<NoteId> = Set()
    var zap_button: ZapButtonModel = ZapButtonModel()

    /// IDs of our own notes, used to detect quote notifications.
    ///
    /// When a third-party client quotes one of our notes, they may only include
    /// a `q` tag without a separate `p` tag for us. By tracking our note IDs,
    /// we can match incoming events with `#q` filters and verify they quote our posts.
    ///
    /// The set is capped at `maxOurNoteIds` to prevent unbounded growth during long
    /// sessions. When the cap is exceeded, the oldest entries are evicted.
    var our_note_ids: Set<NoteId> = Set()

    /// Tracks insertion order for our_note_ids to enable FIFO eviction when capped.
    private var our_note_ids_order: [NoteId] = []

    /// Maximum number of note IDs to track for quote notification detection.
    /// This prevents unbounded memory growth and keeps relay filter sizes reasonable.
    static let maxOurNoteIds = 1000
    
    init() {
        self.damus_state = DamusState.empty
        self.setup_debouncer()
        DispatchQueue.main.async {
            self.filter_events()
        }
        events.on_queue = preloader
        //self.events = EventHolder(on_queue: preloader)
    }
    
    func preloader(ev: NostrEvent) {
        preload_events(state: self.damus_state, events: [ev])
    }
    
    var dms: DirectMessagesModel {
        return damus_state.dms
    }
    
    func setup_debouncer() {
        // turn off debouncer after initial load
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.should_debounce_dms = false
        }
    }
    
    // MARK: - Loading items from DamusState
    
    /// This is called whenever DamusState gets set. This function is used to load or setup anything we need from the new DamusState
    @MainActor
    func load_our_stuff_from_damus_state() {
        self.load_latest_contact_event_from_damus_state()
        self.load_latest_mutelist_event_from_damus_state()
        self.load_drafts_from_damus_state()
        self.load_our_note_ids_from_nostrdb()
    }
    
    /// This loads the latest contact event we have on file from NostrDB. This should be called as soon as we get the new DamusState
    /// Loading the latest contact list event into our `Contacts` instance from storage is important to avoid getting into weird states when the network is unreliable or when relays delete such information
    @MainActor
    func load_latest_contact_event_from_damus_state() {
        damus_state.contacts.delegate = self
        guard let latest_contact_event_id_hex = damus_state.settings.latest_contact_event_id_hex else { return }
        guard let latest_contact_event_id = NoteId(hex: latest_contact_event_id_hex) else { return }
        guard let latest_contact_event: NdbNote = try? damus_state.ndb.lookup_note_and_copy(latest_contact_event_id) else { return }
        process_contact_event(state: damus_state, ev: latest_contact_event)
    }
    
    /// Loads the latest mute list event we have stored locally so that the mutelist manager is immediately aware of previous mutes.
    @MainActor
    func load_latest_mutelist_event_from_damus_state() {
        if damus_state.mutelist_manager.event != nil {
            return
        }

        if let latest_event = load_latest_mutelist_event_from_db() {
            damus_state.mutelist_manager.set_mutelist(latest_event)
            return
        }

        if let legacy_event = load_latest_legacy_mutelist_event_from_db() {
            damus_state.mutelist_manager.set_mutelist(legacy_event)
        }
    }
    
    @MainActor
    private func load_latest_mutelist_event_from_db(limit: Int = 5) -> NostrEvent? {
        guard let filter = try? NdbFilter(from: NostrFilter(kinds: [.mute_list], limit: UInt32(limit), authors: [damus_state.pubkey])) else { return nil }
        
        guard let note_keys = try? damus_state.ndb.query(filters: [filter], maxResults: limit) else { return nil }
        
        var candidates: [NostrEvent] = []
        for key in note_keys {
            guard let note = try? damus_state.ndb.lookup_note_by_key_and_copy(key) else { continue }
            candidates.append(note)
        }
        return candidates.max(by: { $0.created_at < $1.created_at })
    }
    
    @MainActor
    private func load_latest_legacy_mutelist_event_from_db(limit: Int = 20) -> NostrEvent? {
        guard let filter = try? NdbFilter(from: NostrFilter(kinds: [.list_deprecated], limit: UInt32(limit), authors: [damus_state.pubkey])) else { return nil }
        guard let note_keys = try? damus_state.ndb.query(filters: [filter], maxResults: limit) else { return nil }
        
        var candidates: [NostrEvent] = []
        for key in note_keys {
            guard let note = try? damus_state.ndb.lookup_note_by_key_and_copy(key) else { continue }
            if note.referenced_params.contains(where: { $0.param.matches_str("mute") }) {
                candidates.append(note)
            }
        }
        
        return candidates.max(by: { $0.created_at < $1.created_at })
    }
    
    func load_drafts_from_damus_state() {
        damus_state.drafts.load(from: damus_state)
    }

    /// Kinds that can be quoted and should be tracked for quote notification detection.
    ///
    /// Per NIP-18, any event can be quoted. We track text notes, longform articles,
    /// and highlights since these are the most commonly quoted content types.
    static let quotableKinds: [NostrKind] = [.text, .longform, .highlight]

    /// Loads our note IDs from nostrdb to enable quote notification detection.
    ///
    /// Per NIP-18, quote posts use `q` tags: `["q", "<event-id>", "<relay-url>", "<pubkey>"]`.
    /// Third-party clients may not include a separate `p` tag for the quoted note's author,
    /// so we need to match quote notifications by checking if the quoted note ID is ours.
    ///
    /// This queries nostrdb for our recent quotable notes (text, longform, highlights)
    /// and caches their IDs for efficient lookup during notification validation.
    func load_our_note_ids_from_nostrdb() {
        do {
            var filter = NostrFilter(kinds: Self.quotableKinds)
            filter.authors = [damus_state.pubkey]
            filter.limit = UInt32(Self.maxOurNoteIds)

            let ndbFilter = try NdbFilter(from: filter)
            let noteKeys = try damus_state.ndb.query(filters: [ndbFilter], maxResults: Self.maxOurNoteIds)

            var loadedIds: Set<NoteId> = Set()
            var loadedOrder: [NoteId] = []
            for noteKey in noteKeys {
                damus_state.ndb.lookup_note_by_key(noteKey, borrow: { maybeUnownedNote in
                    switch maybeUnownedNote {
                    case .none:
                        break
                    case .some(let unownedNote):
                        loadedIds.insert(unownedNote.id)
                        loadedOrder.append(unownedNote.id)
                    }
                })
            }

            self.our_note_ids = loadedIds
            self.our_note_ids_order = loadedOrder
            Log.info("Loaded %d of our note IDs for quote notification detection", for: .timeline, loadedIds.count)
        } catch {
            Log.error("Failed to load our note IDs from nostrdb: %@", for: .timeline, String(describing: error))
        }
    }

    /// Adds a note ID to our tracked set when we post a new note.
    ///
    /// This keeps the quote notification detection up-to-date as we create new posts.
    /// After adding, triggers a debounced resubscription to include the new ID in the
    /// quotes notification filter.
    ///
    /// If the set exceeds `maxOurNoteIds`, the oldest entries are evicted (FIFO) to
    /// keep the filter size bounded and prevent relay filter limits from being exceeded.
    func track_our_new_note(_ noteId: NoteId) {
        let wasInserted = our_note_ids.insert(noteId).inserted
        guard wasInserted else { return }

        our_note_ids_order.append(noteId)

        // Evict oldest entries if we exceed the cap (FIFO eviction).
        while our_note_ids.count > Self.maxOurNoteIds && !our_note_ids_order.isEmpty {
            let oldest = our_note_ids_order.removeFirst()
            our_note_ids.remove(oldest)
        }

        // Debounce resubscription to avoid excessive churn when posting multiple notes.
        notifications_resub_debouncer.debounce {
            self.subscribe_to_notifications()
        }
    }

    /// Subscribes to notification events, including quote notifications.
    ///
    /// This method builds notification filters and starts the notification handler task.
    /// It can be called multiple times to refresh the subscription when our note IDs
    /// change (e.g., after posting a new note that could be quoted).
    ///
    /// The subscription includes:
    /// 1. Standard notifications: events with our pubkey in a p tag
    /// 2. Quote notifications: text events with our note IDs in a q tag
    ///
    /// - Note: There is a brief gap during subscription refresh where events could
    ///   theoretically be missed (between cancel and new stream start). However:
    ///   1. The gap is very short (milliseconds)
    ///   2. Events arriving during this time are still stored in nostrdb
    ///   3. They will be picked up on the next app launch or subscription refresh
    ///   4. The debouncer minimizes refresh frequency to reduce this window
    func subscribe_to_notifications() {
        // Build the standard notification filter (events mentioning our pubkey).
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

        // Build the quotes notification filter.
        //
        // Per NIP-18, quote posts use `q` tags: ["q", "<event-id>", "<relay-url>", "<pubkey>"].
        // Third-party clients may only include the q tag without a separate p tag for us.
        // This filter catches text events (kind 1) that quote one of our notes.
        var notifications_filters = [notifications_filter]
        if !our_note_ids.isEmpty {
            var quotes_filter = NostrFilter(kinds: [.text])
            quotes_filter.quotes = Array(our_note_ids)
            quotes_filter.limit = 500
            notifications_filters.append(quotes_filter)
            Log.info("Added quotes notification filter with %d note IDs", for: .timeline, our_note_ids.count)
        }

        // Cancel existing subscription and start new one.
        self.notificationsHandlerTask?.cancel()
        self.notificationsHandlerTask = Task {
            // Use advancedStream (not streamIndefinitely) so we receive EOSE signals.
            // This lets us flush queued notifications once the local database finishes loading,
            // fixing the race condition where onAppear fires before events arrive.
            for await item in damus_state.nostrNetwork.reader.advancedStream(
                filters: notifications_filters,
                streamMode: .ndbAndNetworkParallel(optimizeNetworkFilter: true)
            ) {
                switch item {
                case .event(let lender):
                    await lender.justUseACopy({ await process_event(ev: $0, context: .notifications) })

                case .ndbEose:
                    // Local database finished loading. Flush any queued notifications
                    // and disable queuing so subsequent events display immediately.
                    await MainActor.run {
                        self.notifications.flush(damus_state)
                        self.notifications.set_should_queue(false)
                    }

                case .eose, .networkEose:
                    break
                }
            }
        }
    }

    enum RelayListLoadingError: Error {
        case noRelayList
        case relayListParseError
        
        var humanReadableError: ErrorView.UserPresentableError {
            switch self {
            case .noRelayList:
                return ErrorView.UserPresentableError(
                    user_visible_description: NSLocalizedString("Your relay list could not be found, so we cannot connect you to your Nostr network.", comment: "Human readable error description for a failure to find the relay list"),
                    tip: NSLocalizedString("Please check your internet connection and restart the app. If the error persists, please go to Settings > First Aid.", comment: "Human readable tips for what to do for a failure to find the relay list"),
                    technical_info: "No NIP-65 relay list or legacy kind:3 contact event could be found."
                )
            case .relayListParseError:
                return ErrorView.UserPresentableError(
                    user_visible_description: NSLocalizedString("Your relay list appears to be broken, so we cannot connect you to your Nostr network.", comment: "Human readable error description for a failure to parse the relay list due to a bad relay list"),
                    tip: NSLocalizedString("Please contact support for further help.", comment: "Human readable tips for what to do for a failure to find the relay list"),
                    technical_info: "Relay list could not be parsed."
                )
            }
        }
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
    func process_event(ev: NostrEvent, context: SubscriptionContext) {
        guard let kind = ev.known_kind else {
            return
        }

        switch kind {
        case .chat, .longform, .text, .highlight:
            handle_text_event(ev, context: context)
        case .contacts:
            handle_contact_event(ev: ev)
        case .metadata:
            // profile metadata processing is handled by nostrdb
            break
        case .list_deprecated:
            handle_old_list_event(ev)
        case .mute_list:
            handle_mute_list_event(ev)
        case .contact_card:
            damus_state.contactCards.loadEvent(ev, pubkey: damus_state.pubkey)
        case .boost:
            handle_boost_event(ev, context: context)
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
            handle_nwc_response(ev)
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
        case .follow_list:
            break
        case .interest_list:
            break   // Don't care for now
        case .live, .live_chat:
            break
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

    func handle_nwc_response(_ ev: NostrEvent) {
        Task { @MainActor in
            // TODO: Adapt KeychainStorage to StringCodable and instead of parsing to WalletConnectURL every time
            guard let nwc_str = damus_state.settings.nostr_wallet_connect,
                  let nwc = WalletConnectURL(str: nwc_str) else {
                return
            }
            
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
                Log.debug("HomeModel: got NWC response, removed %s from the postbox", for: .nwc, resp.req_id.hex())
            } else {
                Log.debug("HomeModel: got NWC response, %s not found in the postbox, nothing to remove", for: .nwc, resp.req_id.hex())
            }
            
            damus_state.wallet.handle_nwc_response(response: resp)  // This can handle success or error cases
            
            guard resp.response.error == nil else {
                Log.error("HomeModel: NWC wallet raised an error: %s", for: .nwc, String(describing: resp.response))
                WalletConnect.handle_error(zapcache: self.damus_state.zaps, evcache: self.damus_state.events, resp: resp)
                
                return
            }

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

            guard let new_bits = handle_last_events(new_events: self.notification_status.new_events, ev: ev, timeline: .notifications, shouldNotify: true, pubkey: self.damus_state.pubkey) else {
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
            let last_notification = get_last_event(.notifications, pubkey: self.damus_state.pubkey)
            if last_notification == nil || last_notification!.created_at < notification.last_event_at {
                save_last_event(NoteId.empty, created_at: notification.last_event_at, timeline: .notifications, pubkey: self.damus_state.pubkey)
                // If we successfully inserted a new Damus App notification, switch ON the Damus App notification bit on our NewsEventsBits
                // This will cause the bell icon on the tab bar to display the purple dot indicating there is an unread notification
                self.notification_status.new_events = NewEventsBits(rawValue: self.notification_status.new_events.rawValue | NewEventsBits.damus_app_notifications.rawValue)
            }
            return
        }
    }
    
    @MainActor
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

    func handle_contact_event(ev: NostrEvent) {
        process_contact_event(state: self.damus_state, ev: ev)
    }

    func handle_boost_event(_ ev: NostrEvent, context: SubscriptionContext) {
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
                        self.handle_text_event(ev, context: context)
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

    @MainActor
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

    /// Send the initial filters, just our contact list and relay list mostly
    func send_initial_filters() {
        Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            let id = UUID()
            Log.info("Initial filter task started with ID %s", for: .homeModel, id.uuidString)
            let filter = NostrFilter(kinds: [.contacts], limit: 1, authors: [damus_state.pubkey])
            for await event in damus_state.nostrNetwork.reader.streamExistingEvents(filters: [filter]) {
                await event.justUseACopy({ await process_event(ev: $0, context: .other) })
                if !done_init {
                    done_init = true
                    Log.info("Initial filter task %s: Done initialization; Elapsed time: %.2f seconds", for: .homeModel, id.uuidString, CFAbsoluteTimeGetCurrent() - startTime)
                    send_home_filters()
                }
            }
            
        }
    }

    /// After initial connection or reconnect, send subscription filters for the home timeline, DMs, and notifications
    func send_home_filters() {
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

        var contact_cards_filter = NostrFilter(kinds: [.contact_card])
        contact_cards_filter.authors = [damus_state.pubkey]

        var our_blocklist_filter = NostrFilter(kinds: [.mute_list])
        our_blocklist_filter.authors = [damus_state.pubkey]

        var dms_filter = NostrFilter(kinds: [.dm])

        var our_dms_filter = NostrFilter(kinds: [.dm])

        // friends only?...
        //dms_filter.authors = friends
        dms_filter.limit = 500
        dms_filter.pubkeys = [ damus_state.pubkey ]
        our_dms_filter.authors = [ damus_state.pubkey ]

        let contacts_filter_chunks = contacts_filter.chunked(on: .authors, into: MAX_CONTACTS_ON_FILTER)
        let low_volume_important_filters = [our_contacts_filter, our_blocklist_filter, our_old_blocklist_filter, contact_cards_filter]
        let contacts_filters = contacts_filter_chunks + low_volume_important_filters
        let dms_filters = [dms_filter, our_dms_filter]

        //print_filters(relay_id: relay_id, filters: [home_filters, contacts_filters, notifications_filters, dms_filters])

        subscribe_to_home_filters()
        subscribe_to_notifications()

        self.generalHandlerTask?.cancel()
        self.generalHandlerTask = Task {
            for await item in damus_state.nostrNetwork.reader.advancedStream(filters: dms_filters + contacts_filters, streamMode: .ndbAndNetworkParallel(optimizeNetworkFilter: true)) {
                switch item {
                case .event(let lender):
                    await lender.justUseACopy({ await process_event(ev: $0, context: .other) })
                case .eose:
                    var dms = dms.dms.flatMap { $0.events }
                    dms.append(contentsOf: incoming_dms)
                case .ndbEose:
                    var dms = dms.dms.flatMap { $0.events }
                    dms.append(contentsOf: incoming_dms)
                case .networkEose: break
                }
            }
        }
        // Due to subscription volume limits in ndb and in relays, some important events may get clipped in the `generalHandlerTask` above.
        // This could lead to issues (e.g. The app overriding a mutelist because it does not have it)
        // Therefore, we have this ndb-only stream for some low volume important items.
        // The reason we do not separate into two complete streams is because
        // we need to keep total relay subscription down to avoid relay subscription limits.
        self.ndbOnlyHandlerTask?.cancel()
        self.ndbOnlyHandlerTask = Task {
            for await eventLender in damus_state.nostrNetwork.reader.streamIndefinitely(filters: low_volume_important_filters, streamMode: .ndbOnly) {
                await eventLender.justUseACopy({ await process_event(ev: $0, context: .other) })
            }
        }
        self.nwcHandlerTask?.cancel()
        self.nwcHandlerTask = Task {
            if let nwc_str = damus_state.settings.nostr_wallet_connect,
               let nwc = WalletConnectURL(str: nwc_str)
            {
                var filter = NostrFilter(kinds: [.nwc_response])
                filter.authors = [nwc.pubkey]
                filter.limit = 0
                for await event in damus_state.nostrNetwork.reader.streamIndefinitely(filters: [filter], to: [nwc.relay]) {
                    await event.justUseACopy({ await process_event(ev: $0, context: .other) })
                }
            }
            
        }
    }

    func get_last_of_kind(relay_id: RelayURL?) -> [UInt32: NostrEvent] {
        return relay_id.flatMap { last_event_of_kind[$0] } ?? [:]
    }

    func get_friends() -> [Pubkey] {
        var friends = damus_state.contacts.get_friend_list()
        friends.insert(damus_state.pubkey)
        return Array(friends)
    }

    func subscribe_to_home_filters(friends fs: [Pubkey]? = nil) {
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

        // Add filter for favorited users who we dont follow
        if damus_state.settings.enable_favourites_feature {
            let all_favorites = damus_state.contactCards.favorites
            let favorited_not_followed = Array(all_favorites.subtracting(Set(friends)))
            if !favorited_not_followed.isEmpty {
                var favorites_filter = NostrFilter(kinds: home_filter_kinds)
                favorites_filter.authors = favorited_not_followed
                favorites_filter.limit = 500
                home_filters.append(favorites_filter)
            }
        }

        self.homeHandlerTask?.cancel()
        self.homeHandlerTask = Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            let id = UUID()
            Log.info("Home handler task: Starting home handler task with ID %s", for: .homeModel, id.uuidString)
    
            DispatchQueue.main.async {
                self.loading = true
            }
            for await item in damus_state.nostrNetwork.reader.advancedStream(filters: home_filters, streamMode: .ndbAndNetworkParallel(optimizeNetworkFilter: true), id: id) {
                switch item {
                case .event(let lender):
                    let currentTime = CFAbsoluteTimeGetCurrent()
                    // Process events in parallel on a separate task, to avoid holding up upcoming signals
                    // Empirical evidence has shown that in at least one instance this technique saved up to 5 seconds of load time!
                    Task { await lender.justUseACopy({ await process_event(ev: $0, context: .home) }) }
                case .eose:
                    let eoseTime = CFAbsoluteTimeGetCurrent()
                    Log.info("Home handler task %s: Received general EOSE after %.2f seconds", for: .homeModel, id.uuidString, eoseTime - startTime)
            
                    let finishTime = CFAbsoluteTimeGetCurrent()
                    Log.info("Home handler task %s: Completed initial loading task after %.2f seconds", for: .homeModel, id.uuidString, eoseTime - startTime)
                case .ndbEose:
                    let eoseTime = CFAbsoluteTimeGetCurrent()
                    Log.info("Home handler task %s: Received NDB EOSE after %.2f seconds", for: .homeModel, id.uuidString, eoseTime - startTime)
                    
                    DispatchQueue.main.async {
                        self.loading = false
                    }
            
                    let finishTime = CFAbsoluteTimeGetCurrent()
                    Log.info("Home handler task %s: Completed initial NDB loading task after %.2f seconds", for: .homeModel, id.uuidString, eoseTime - startTime)
                case .networkEose:
                    break
                }
            }
        }
    }
    
    /// Adapter pattern to make migration easier
    enum SubscriptionContext {
        case home
        case notifications
        case other
    }

    @MainActor
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

    @MainActor
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
    
    @MainActor
    func handle_notification(ev: NostrEvent) {
        // Don't show notifications from ourselves.
        guard ev.pubkey != damus_state.pubkey else {
            return
        }

        // Validate that this notification is relevant to us.
        //
        // An event is relevant if:
        // 1. It references our pubkey in a p tag (replies, mentions, boosts, zaps, likes)
        // 2. OR it quotes one of our notes via a q tag (quote posts from third-party clients)
        //
        // This dual check is necessary because per NIP-18, quote posts may only include
        // a q tag without a separate p tag for the quoted note's author.
        let has_our_pubkey = event_has_our_pubkey(ev, our_pubkey: damus_state.pubkey)
        let quotes_our_note = ev.referenced_quote_ids.contains { our_note_ids.contains($0.note_id) }

        guard has_our_pubkey || quotes_our_note else {
            return
        }

        guard should_show_event(state: damus_state, ev: ev) else {
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
            Task { await process_local_notification(state: damus_state, event: ev) }
        }
        
    }

    @discardableResult
    func handle_last_event(ev: NostrEvent, timeline: Timeline, shouldNotify: Bool = true) -> Bool {
        if let new_bits = handle_last_events(new_events: self.notification_status.new_events, ev: ev, timeline: timeline, shouldNotify: shouldNotify, pubkey: self.damus_state.pubkey) {
            self.notification_status.new_events = new_bits
            return true
        } else {
            return false
        }
    }

    @MainActor
    func insert_home_event(_ ev: NostrEvent) {
        if events.insert(ev) {
            handle_last_event(ev: ev, timeline: .home)
        }
    }


    @MainActor
    func handle_text_event(_ ev: NostrEvent, context: SubscriptionContext) {
        guard should_show_event(state: damus_state, ev: ev) else {
            return
        }

        // Track our own quotable notes for quote notification detection.
        //
        // When we post a new note, it comes back through the subscription.
        // By tracking it here, we ensure our quote notification filter stays
        // current even for notes posted during this session. The track_our_new_note
        // function handles debounced resubscription to include the new ID.
        if let kind = ev.known_kind,
           Self.quotableKinds.contains(kind),
           ev.pubkey == damus_state.pubkey {
            track_our_new_note(ev.id)
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

        switch context {
        case .home:
            Task { await insert_home_event(ev) }
        case .notifications:
            handle_notification(ev: ev)
        case .other:
            break
        }
    }
    
    func got_new_dm(notifs: NewEventsBits, ev: NostrEvent) {
        Task {
            notification_status.new_events = notifs
            
            
            guard await should_display_notification(state: damus_state, event: ev, mode: .local),
                  let notification_object = generate_local_notification_object(ndb: self.damus_state.ndb, from: ev, state: damus_state)
            else {
                return
            }
            
            create_local_notification(profiles: damus_state.profiles, notify: notification_object)
        }
    }
    
    @MainActor
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


func update_signal_from_pool(signal: SignalModel, pool: RelayPool) async {
    let relayCount = await pool.relays.count
    if signal.max_signal != relayCount {
        signal.max_signal = relayCount
    }

    let numberOfConnectedRelays = await pool.num_connected
    if signal.signal != numberOfConnectedRelays {
        signal.signal = numberOfConnectedRelays
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
        new_bits = handle_last_events(new_events: prev_events, ev: ev, timeline: .dms, shouldNotify: !ours, pubkey: our_pubkey)
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
func handle_last_events(new_events: NewEventsBits, ev: NostrEvent, timeline: Timeline, shouldNotify: Bool = true, pubkey: Pubkey) -> NewEventsBits? {
    let last_ev = get_last_event(timeline, pubkey: pubkey)

    if last_ev == nil || last_ev!.created_at < ev.created_at {
        save_last_event(ev, timeline: timeline, pubkey: pubkey)
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

@MainActor
func should_show_event(event: NostrEvent, damus_state: DamusState) -> Bool {
    return should_show_event(
        state: damus_state,
        ev: event
    )
}

@MainActor
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

// MARK: - Extension to bridge NIP-65 relay list structs with app-native objects
// TODO: Do we need this??

//extension NIP65.RelayList {
//    static func fromLegacyContactList(_ contactList: NdbNote) throws(BridgeError) -> Self {
//        guard let relayListInfo = decode_json_relays(contactList.content) else { throw .couldNotDecodeRelayListInfo }
//        let relayItems = relayListInfo.map({ url, rwConfiguration in
//            return RelayItem(url: url, rwConfiguration: rwConfiguration.toNIP65RWConfiguration() ?? .readWrite)
//        })
//        return NIP65.RelayList(relays: relayItems)
//    }
//    
//    static func fromLegacyContactList(_ contactList: NdbNote?) throws(BridgeError) -> Self? {
//        guard let contactList = contactList else { return nil }
//        return try fromLegacyContactList(contactList)
//    }
//    
//    enum BridgeError: Error {
//        case couldNotDecodeRelayListInfo
//    }
//}
