//
//  HomeModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation
import UIKit

struct NewEventsBits: OptionSet {
    let rawValue: Int
    
    static let home = NewEventsBits(rawValue: 1 << 0)
    static let zaps = NewEventsBits(rawValue: 1 << 1)
    static let mentions = NewEventsBits(rawValue: 1 << 2)
    static let reposts = NewEventsBits(rawValue: 1 << 3)
    static let likes = NewEventsBits(rawValue: 1 << 4)
    static let search = NewEventsBits(rawValue: 1 << 5)
    static let dms = NewEventsBits(rawValue: 1 << 6)
    
    static let all = NewEventsBits(rawValue: 0xFFFFFFFF)
    static let notifications: NewEventsBits = [.zaps, .likes, .reposts, .mentions]
}

class HomeModel: ObservableObject {
    // Don't trigger a user notification for events older than a certain age
    static let event_max_age_for_notification: TimeInterval = 12 * 60 * 60
    
    var damus_state: DamusState

    var has_event: [String: Set<String>] = [:]
    var deleted_events: Set<String> = Set()
    var channels: [String: NostrEvent] = [:]
    var last_event_of_kind: [String: [Int: NostrEvent]] = [:]
    var done_init: Bool = false
    var incoming_dms: [NostrEvent] = []
    let dm_debouncer = Debouncer(interval: 0.5)
    var should_debounce_dms = true

    let home_subid = UUID().description
    let contacts_subid = UUID().description
    let notifications_subid = UUID().description
    let dms_subid = UUID().description
    let init_subid = UUID().description
    let profiles_subid = UUID().description
    
    var loading: Bool = false

    var signal = SignalModel()
    
    @Published var new_events: NewEventsBits = NewEventsBits()
    @Published var notifications = NotificationsModel()
    @Published var events: EventHolder = EventHolder()
    
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
        return damus_state.pool
    }
    
    var dms: DirectMessagesModel {
        return damus_state.dms
    }

    func has_sub_id_event(sub_id: String, ev_id: String) -> Bool {
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

    func process_event(sub_id: String, relay_id: String, ev: NostrEvent) {
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
        case .chat: fallthrough
        case .text:
            handle_text_event(sub_id: sub_id, ev)
        case .contacts:
            handle_contact_event(sub_id: sub_id, relay_id: relay_id, ev: ev)
        case .metadata:
            handle_metadata_event(ev)
        case .list:
            handle_list_event(ev)
        case .boost:
            handle_boost_event(sub_id: sub_id, ev)
        case .like:
            handle_like_event(ev)
        case .dm:
            handle_dm(ev)
        case .delete:
            handle_delete_event(ev)
        case .channel_create:
            handle_channel_create(ev)
        case .channel_meta:
            break
        case .zap:
            handle_zap_event(ev)
        case .zap_request:
            break
        case .nwc_request:
            break
        case .nwc_response:
            handle_nwc_response(ev)
        }
    }
    
    func handle_nwc_response(_ ev: NostrEvent) {
        Task { @MainActor in
            // TODO: Adapt KeychainStorage to StringCodable and instead of parsing to WalletConnectURL every time
            guard let nwc_str = damus_state.settings.nostr_wallet_connect,
                  let nwc = WalletConnectURL(str: nwc_str),
                  let resp = await FullWalletResponse(from: ev, nwc: nwc) else {
                return
            }
            
            // since command results are not returned for ephemeral events,
            // remove the request from the postbox which is likely failing over and over
            if damus_state.postbox.remove_relayer(relay_id: nwc.relay.id, event_id: resp.req_id) {
                print("nwc: got response, removed \(resp.req_id) from the postbox")
            } else {
                print("nwc: \(resp.req_id) not found in the postbox, nothing to remove")
            }
            
            if resp.response.error == nil {
            }
            
            guard let err = resp.response.error else {
                nwc_success(state: self.damus_state, resp: resp)
                return
            }
            
            print("nwc error: \(err)")
            nwc_error(zapcache: self.damus_state.zaps, evcache: self.damus_state.events, resp: resp)
        }
    }
    
    func handle_zap_event_with_zapper(profiles: Profiles, ev: NostrEvent, our_keypair: Keypair, zapper: String) {
        guard let zap = Zap.from_zap_event(zap_ev: ev, zapper: zapper, our_privkey: our_keypair.privkey) else {
            return
        }
        
        damus_state.add_zap(zap: .zap(zap))
        
        guard zap.target.pubkey == our_keypair.pubkey else {
            return
        }
        
        if !notifications.insert_zap(.zap(zap)) {
            return
        }

        if handle_last_event(ev: ev, timeline: .notifications) {
            if damus_state.settings.zap_vibration {
                // Generate zap vibration
                zap_vibrate(zap_amount: zap.invoice.amount)
            }
            if damus_state.settings.zap_notification {
                // Create in-app local notification for zap received.
                create_in_app_zap_notification(profiles: profiles, zap: zap, evId: ev.referenced_ids.first?.id ?? "")
            }
        }

        return
    }

    func handle_zap_event(_ ev: NostrEvent) {
        // These are zap notifications
        guard let ptag = event_tag(ev, name: "p") else {
            return
        }
        
        let our_keypair = damus_state.keypair
        if let local_zapper = damus_state.profiles.lookup_zapper(pubkey: ptag) {
            handle_zap_event_with_zapper(profiles: self.damus_state.profiles, ev: ev, our_keypair: our_keypair, zapper: local_zapper)
            return
        }
        
        guard let profile = damus_state.profiles.lookup(id: ptag) else {
            return
        }
        
        guard let lnurl = profile.lnurl else {
            return
        }
        
        Task {
            guard let zapper = await fetch_zapper_from_lnurl(lnurl) else {
                return
            }
            
            DispatchQueue.main.async {
                self.damus_state.profiles.zappers[ptag] = zapper
                self.handle_zap_event_with_zapper(profiles: self.damus_state.profiles, ev: ev, our_keypair: our_keypair, zapper: zapper)
            }
        }
        
    }
    
    func handle_channel_create(_ ev: NostrEvent) {
        self.channels[ev.id] = ev
    }
    
    func filter_events() {
        events.filter { ev in
            !damus_state.contacts.is_muted(ev.pubkey)
        }
        
        self.dms.dms = dms.dms.filter { ev in
            !damus_state.contacts.is_muted(ev.pubkey)
        }
        
        notifications.filter { ev in
            if damus_state.settings.onlyzaps_mode && ev.known_kind == NostrKind.like {
                return false
            }

            return !damus_state.contacts.is_muted(ev.pubkey) && !damus_state.muted_threads.isMutedThread(ev, privkey: damus_state.keypair.privkey)
        }
    }
    
    func handle_delete_event(_ ev: NostrEvent) {
        self.deleted_events.insert(ev.id)
    }

    func handle_contact_event(sub_id: String, relay_id: String, ev: NostrEvent) {
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
        var boost_ev_id = ev.last_refid()?.ref_id

        if let inner_ev = ev.get_inner_event(cache: damus_state.events) {
            boost_ev_id = inner_ev.id
            
            
            Task.init {
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
        case .success(let n):
            let boosted = Counted(event: ev, id: e, total: n)
            notify(.boosted, boosted)
            notify(.update_stats, e)
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

        switch damus_state.likes.add_event(ev, target: e.ref_id) {
        case .already_counted:
            break
        case .success(let n):
            handle_notification(ev: ev)
            let liked = Counted(event: ev, id: e.ref_id, total: n)
            notify(.liked, liked)
            notify(.update_stats, e.ref_id)
        }
    }


    func handle_event(relay_id: String, conn_event: NostrConnectionEvent) {
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
                   nwc.relay.id == relay_id
                {
                    subscribe_to_nwc(url: nwc, pool: pool)
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
            
            update_signal_from_pool(signal: self.signal, pool: damus_state.pool)
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
                
                if sub_id == dms_subid {
                    var dms = dms.dms.flatMap { $0.events }
                    dms.append(contentsOf: incoming_dms)
                    load_profiles(profiles_subid: profiles_subid, relay_id: relay_id, load: .from_events(dms), damus_state: damus_state)
                } else if sub_id == notifications_subid {
                    load_profiles(profiles_subid: profiles_subid, relay_id: relay_id, load: .from_keys(notifications.uniq_pubkeys()), damus_state: damus_state)
                } else if sub_id == home_subid {
                    load_profiles(profiles_subid: profiles_subid, relay_id: relay_id, load: .from_events(events.events), damus_state: damus_state)
                }
                
                self.loading = false
                break
                
            case .ok:
                break
            }
            
        }
    }


    /// Send the initial filters, just our contact list mostly
    func send_initial_filters(relay_id: String) {
        var filter = NostrFilter.filter_contacts
        filter.authors = [self.damus_state.pubkey]
        filter.limit = 1

        pool.send(.subscribe(.init(filters: [filter], sub_id: init_subid)), to: [relay_id])
    }

    func send_home_filters(relay_id: String?) {
        // TODO: since times should be based on events from a specific relay
        // perhaps we could mark this in the relay pool somehow

        var friends = damus_state.contacts.get_friend_list()
        friends.append(damus_state.pubkey)

        var contacts_filter = NostrFilter.filter_kinds([NostrKind.metadata.rawValue])
        contacts_filter.authors = friends
        
        var our_contacts_filter = NostrFilter.filter_kinds([NostrKind.contacts.rawValue, NostrKind.metadata.rawValue])
        our_contacts_filter.authors = [damus_state.pubkey]
        
        var our_blocklist_filter = NostrFilter.filter_kinds([NostrKind.list.rawValue])
        our_blocklist_filter.parameter = ["mute"]
        our_blocklist_filter.authors = [damus_state.pubkey]
        
        var dms_filter = NostrFilter.filter_kinds([
            NostrKind.dm.rawValue,
        ])

        var our_dms_filter = NostrFilter.filter_kinds([
            NostrKind.dm.rawValue,
        ])

        // friends only?...
        //dms_filter.authors = friends
        dms_filter.limit = 500
        dms_filter.pubkeys = [ damus_state.pubkey ]
        our_dms_filter.authors = [ damus_state.pubkey ]

        // TODO: separate likes?
        var home_filter_kinds = [
            NostrKind.text.rawValue,
            NostrKind.boost.rawValue
        ]
        if !damus_state.settings.onlyzaps_mode {
            home_filter_kinds.append(NostrKind.like.rawValue)
        }
        var home_filter = NostrFilter.filter_kinds(home_filter_kinds)
        // include our pubkey as well even if we're not technically a friend
        home_filter.authors = friends
        home_filter.limit = 500

        var notifications_filter_kinds = [
            NostrKind.text.rawValue,
            NostrKind.boost.rawValue,
            NostrKind.zap.rawValue,
        ]
        if !damus_state.settings.onlyzaps_mode {
            notifications_filter_kinds.append(NostrKind.like.rawValue)
        }
        var notifications_filter = NostrFilter.filter_kinds(notifications_filter_kinds)
        notifications_filter.pubkeys = [damus_state.pubkey]
        notifications_filter.limit = 500

        var home_filters = [home_filter]
        var notifications_filters = [notifications_filter]
        var contacts_filters = [contacts_filter, our_contacts_filter, our_blocklist_filter]
        var dms_filters = [dms_filter, our_dms_filter]

        let last_of_kind = relay_id.flatMap { last_event_of_kind[$0] } ?? [:]

        home_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: home_filters)
        contacts_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: contacts_filters)
        notifications_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: notifications_filters)
        dms_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: dms_filters)

        print_filters(relay_id: relay_id, filters: [home_filters, contacts_filters, notifications_filters, dms_filters])

        if let relay_id {
            pool.send(.subscribe(.init(filters: home_filters, sub_id: home_subid)), to: [relay_id])
            pool.send(.subscribe(.init(filters: contacts_filters, sub_id: contacts_subid)), to: [relay_id])
            pool.send(.subscribe(.init(filters: notifications_filters, sub_id: notifications_subid)), to: [relay_id])
            pool.send(.subscribe(.init(filters: dms_filters, sub_id: dms_subid)), to: [relay_id])
        } else {
            pool.send(.subscribe(.init(filters: home_filters, sub_id: home_subid)))
            pool.send(.subscribe(.init(filters: contacts_filters, sub_id: contacts_subid)))
            pool.send(.subscribe(.init(filters: notifications_filters, sub_id: notifications_subid)))
            pool.send(.subscribe(.init(filters: dms_filters, sub_id: dms_subid)))
        }
    }
    
    func handle_list_event(_ ev: NostrEvent) {
        // we only care about our lists
        guard ev.pubkey == damus_state.pubkey else {
            return
        }
        
        if let mutelist = damus_state.contacts.mutelist {
            if ev.created_at <= mutelist.created_at {
                return
            }
        }
        
        guard let name = get_referenced_ids(tags: ev.tags, key: "d").first else {
            return
        }
        
        guard name.ref_id == "mute" else {
            return
        }
        
        damus_state.contacts.set_mutelist(ev)
    }
    
    func handle_metadata_event(_ ev: NostrEvent) {
        process_metadata_event(events: damus_state.events, our_pubkey: damus_state.pubkey, profiles: damus_state.profiles, ev: ev)
    }

    func get_last_event_of_kind(relay_id: String, kind: Int) -> NostrEvent? {
        guard let m = last_event_of_kind[relay_id] else {
            last_event_of_kind[relay_id] = [:]
            return nil
        }

        return m[kind]
    }
    
    func handle_notification(ev: NostrEvent) {
        // don't show notifications from ourselves
        guard ev.pubkey != damus_state.pubkey else {
            return
        }
        
        guard event_has_our_pubkey(ev, our_pubkey: self.damus_state.pubkey) else {
            return
        }
        
        guard should_show_event(contacts: damus_state.contacts, ev: ev) && !damus_state.muted_threads.isMutedThread(ev, privkey: damus_state.keypair.privkey) else {
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
            process_local_notification(damus_state: damus_state, event: ev)
        }
        
    }

    @discardableResult
    func handle_last_event(ev: NostrEvent, timeline: Timeline, shouldNotify: Bool = true) -> Bool {
        if let new_bits = handle_last_events(new_events: self.new_events, ev: ev, timeline: timeline, shouldNotify: shouldNotify) {
            new_events = new_bits
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
        guard should_show_event(contacts: damus_state.contacts, ev: ev) else {
            return
        }
        
        // TODO: will we need to process this in other places like zap request contents, etc?
        process_image_metadatas(cache: damus_state.events, ev: ev)
        damus_state.replies.count_replies(ev)
        damus_state.events.insert(ev)

        if sub_id == home_subid {
            insert_home_event(ev)
        } else if sub_id == notifications_subid {
            handle_notification(ev: ev)
        }
    }
    
    func got_new_dm(notifs: NewEventsBits, ev: NostrEvent) {
        self.new_events = notifs
        
        if damus_state.settings.dm_notification && ev.age < HomeModel.event_max_age_for_notification {
            let convo = ev.decrypted(privkey: self.damus_state.keypair.privkey) ?? NSLocalizedString("New encrypted direct message", comment: "Notification that the user has received a new direct message")
            let notify = LocalNotification(type: .dm, event: ev, target: ev, content: convo)
            create_local_notification(profiles: damus_state.profiles, notify: notify)
        }
    }
    
    func handle_dm(_ ev: NostrEvent) {
        guard should_show_event(contacts: damus_state.contacts, ev: ev) else {
            return
        }
        
        damus_state.events.insert(ev)
        
        if !should_debounce_dms {
            self.incoming_dms.append(ev)
            if let notifs = handle_incoming_dms(prev_events: self.new_events, dms: self.dms, our_pubkey: self.damus_state.pubkey, evs: self.incoming_dms) {
                got_new_dm(notifs: notifs, ev: ev)
            }
            self.incoming_dms = []
            return
        }
        
        incoming_dms.append(ev)
        
        dm_debouncer.debounce { [self] in
            if let notifs = handle_incoming_dms(prev_events: self.new_events, dms: self.dms, our_pubkey: self.damus_state.pubkey, evs: self.incoming_dms) {
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

func load_our_contacts(contacts: Contacts, m_old_ev: NostrEvent?, ev: NostrEvent) {
    var new_pks = Set<String>()
    // our contacts
    for tag in ev.tags {
        if tag.count >= 2 && tag[0] == "p" {
            new_pks.insert(tag[1])
        }
    }
    
    var old_pks = Set<String>()
    // find removed contacts
    if let old_ev = m_old_ev {
        for tag in old_ev.tags {
            if tag.count >= 2 && tag[0] == "p" {
                old_pks.insert(tag[1])
            }
        }
    }
    
    let diff = new_pks.symmetricDifference(old_pks)
    for pk in diff {
        if new_pks.contains(pk) {
            notify(.followed, pk)
            contacts.add_friend_pubkey(pk)
        } else {
            notify(.unfollowed, pk)
            contacts.remove_friend(pk)
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

func process_metadata_profile(our_pubkey: String, profiles: Profiles, profile: Profile, ev: NostrEvent) {
    if our_pubkey == ev.pubkey && (profile.deleted ?? false) {
        notify(.deleted_account, ())
        return
    }

    var old_nip05: String? = nil
    if let mprof = profiles.lookup_with_timestamp(id: ev.pubkey) {
        old_nip05 = mprof.profile.nip05
        if mprof.event.created_at > ev.created_at {
            // skip if we already have an newer profile
            return
        }
    }

    let tprof = TimestampedProfile(profile: profile, timestamp: ev.created_at, event: ev)
    profiles.add(id: ev.pubkey, profile: tprof)
    
    if let nip05 = profile.nip05, old_nip05 != profile.nip05 {
        
        Task.detached(priority: .background) {
            let validated = await validate_nip05(pubkey: ev.pubkey, nip05_str: nip05)
            if validated != nil {
                print("validated nip05 for '\(nip05)'")
            }
            
            Task { @MainActor in
                profiles.validated[ev.pubkey] = validated
                profiles.nip05_pubkey[nip05] = ev.pubkey
                notify(.profile_updated, ProfileUpdate(pubkey: ev.pubkey, profile: profile))
            }
        }
    }
    
    // load pfps asap
    
    var changed = false
    
    let picture = tprof.profile.picture ?? robohash(ev.pubkey)
    if URL(string: picture) != nil {
        changed = true
    }
    
    let banner = tprof.profile.banner ?? ""
    if URL(string: banner) != nil {
        changed = true
    }
    
    if changed {
        notify(.profile_updated, ProfileUpdate(pubkey: ev.pubkey, profile: profile))
    }
}

func guard_valid_event(events: EventCache, ev: NostrEvent, callback: @escaping () -> Void) {
    let validated = events.is_event_valid(ev.id)
    
    switch validated {
    case .unknown:
        Task {
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
        
    case .bad_id: fallthrough
    case .bad_sig:
        break
    }
}

func process_metadata_event(events: EventCache, our_pubkey: String, profiles: Profiles, ev: NostrEvent, completion: (() -> Void)? = nil) {
    guard_valid_event(events: events, ev: ev) {
        DispatchQueue.global(qos: .background).async {
            guard let profile: Profile = decode_data(Data(ev.content.utf8)) else {
                completion?()
                return
            }
            
            profile.cache_lnurl()
            
            DispatchQueue.main.async {
                process_metadata_profile(our_pubkey: our_pubkey, profiles: profiles, profile: profile, ev: ev)
                completion?()
            }
        }
    }
}

func robohash(_ pk: String) -> String {
    return "https://robohash.org/" + pk
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

    load_our_contacts(contacts: state.contacts, m_old_ev: m_old_ev, ev: ev)
    load_our_relays(state: state, m_old_ev: m_old_ev, ev: ev)
}

func process_contact_event(state: DamusState, ev: NostrEvent) {
    load_our_stuff(state: state, ev: ev)
    add_contact_if_friend(contacts: state.contacts, ev: ev)
}

func load_our_relays(state: DamusState, m_old_ev: NostrEvent?, ev: NostrEvent) {
    let bootstrap_dict: [String: RelayInfo] = [:]
    let old_decoded = m_old_ev.flatMap { decode_json_relays($0.content) } ?? state.bootstrap_relays.reduce(into: bootstrap_dict) { (d, r) in
        d[r] = .rw
    }
    
    guard let decoded = decode_json_relays(ev.content) else {
        return
    }
    
    var changed = false
    
    var new = Set<String>()
    for key in decoded.keys {
        new.insert(key)
    }
    
    var old = Set<String>()
    for key in old_decoded.keys {
        old.insert(key)
    }
    
    let diff = old.symmetricDifference(new)
    
    let new_relay_filters = load_relay_filters(state.pubkey) == nil
    for d in diff {
        changed = true
        if new.contains(d) {
            if let url = RelayURL(d) {
                let descriptor = RelayDescriptor(url: url, info: decoded[d] ?? .rw)
                add_new_relay(relay_filters: state.relay_filters, metadatas: state.relay_metadata, pool: state.pool, descriptor: descriptor, new_relay_filters: new_relay_filters)
            }
        } else {
            state.pool.remove_relay(d)
        }
    }
    
    if changed {
        save_bootstrap_relays(pubkey: state.pubkey, relays: Array(new))
        notify(.relays_changed, ())
    }
}

func add_new_relay(relay_filters: RelayFilters, metadatas: RelayMetadatas, pool: RelayPool, descriptor: RelayDescriptor, new_relay_filters: Bool) {
    try? pool.add_relay(descriptor)
    let url = descriptor.url
    
    let relay_id = url.id
    guard metadatas.lookup(relay_id: relay_id) == nil else {
        return
    }
    
    Task.detached(priority: .background) {
        guard let meta = try? await fetch_relay_metadata(relay_id: relay_id) else {
            return
        }
        
        DispatchQueue.main.async {
            metadatas.insert(relay_id: relay_id, metadata: meta)
            
            // if this is the first time adding filters, we should filter non-paid relays
            if new_relay_filters && !meta.is_paid {
                relay_filters.insert(timeline: .search, relay_id: relay_id)
            }
        }
    }
}

func fetch_relay_metadata(relay_id: String) async throws -> RelayMetadata? {
    var urlString = relay_id.replacingOccurrences(of: "wss://", with: "https://")
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
func handle_incoming_dm(ev: NostrEvent, our_pubkey: String, dms: DirectMessagesModel, prev_events: NewEventsBits) -> (Bool, NewEventsBits?) {
    var inserted = false
    var found = false
    
    let ours = ev.pubkey == our_pubkey
    var i = 0

    var the_pk = ev.pubkey
    if ours {
        if let ref_pk = ev.referenced_pubkeys.first {
            the_pk = ref_pk.ref_id
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
func handle_incoming_dms(prev_events: NewEventsBits, dms: DirectMessagesModel, our_pubkey: String, evs: [NostrEvent]) -> NewEventsBits? {
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
func event_has_our_pubkey(_ ev: NostrEvent, our_pubkey: String) -> Bool {
    for tag in ev.tags {
        if tag.count >= 2 && tag[0] == "p" && tag[1] == our_pubkey {
            return true
        }
    }
    
    return false
}


func should_show_event(contacts: Contacts, ev: NostrEvent) -> Bool {
    if contacts.is_muted(ev.pubkey) {
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

func zap_notification_title(_ zap: Zap) -> String {
    if zap.private_request != nil {
        return NSLocalizedString("Private Zap", comment: "Title of notification when a private zap is received.")
    } else {
        return NSLocalizedString("Zap", comment: "Title of notification when a non-private zap is received.")
    }
}

func zap_notification_body(profiles: Profiles, zap: Zap, locale: Locale = Locale.current) -> String {
    let src = zap.private_request ?? zap.request.ev
    let anon = event_is_anonymous(ev: src)
    let pk = anon ? "anon" : src.pubkey
    let profile = profiles.lookup(id: pk)
    let sats = NSNumber(value: (Double(zap.invoice.amount) / 1000.0))
    let formattedSats = format_msats_abbrev(zap.invoice.amount)
    let name = Profile.displayName(profile: profile, pubkey: pk).display_name

    if src.content.isEmpty {
        let format = localizedStringFormat(key: "zap_notification_no_message", locale: locale)
        return String(format: format, locale: locale, sats.decimalValue as NSDecimalNumber, formattedSats, name)
    } else {
        let format = localizedStringFormat(key: "zap_notification_with_message", locale: locale)
        return String(format: format, locale: locale, sats.decimalValue as NSDecimalNumber, formattedSats, name, src.content)
    }
}

func create_in_app_zap_notification(profiles: Profiles, zap: Zap, locale: Locale = Locale.current, evId: String) {
    let content = UNMutableNotificationContent()

    content.title = zap_notification_title(zap)
    content.body = zap_notification_body(profiles: profiles, zap: zap, locale: locale)
    content.sound = UNNotificationSound.default
    content.userInfo = LossyLocalNotification(type: .zap, event_id: evId).to_user_info()

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

    
func process_local_notification(damus_state: DamusState, event ev: NostrEvent) {
    guard let type = ev.known_kind else {
        return
    }

    if damus_state.settings.notification_only_from_following,
       damus_state.contacts.follow_state(ev.pubkey) != .follows
        {
        return
    }

    // Don't show notifications from muted threads.
    if damus_state.muted_threads.isMutedThread(ev, privkey: damus_state.keypair.privkey) {
        return
    }
    
    // Don't show notifications for old events
    guard ev.age < HomeModel.event_max_age_for_notification else {
        return
    }

    if type == .text && damus_state.settings.mention_notification {
        let blocks = ev.blocks(damus_state.keypair.privkey)
        for case .mention(let mention) in blocks where mention.ref.ref_id == damus_state.keypair.pubkey {
            let content = NSAttributedString(render_note_content(ev: ev, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey).content.attributed).string
            
            let notify = LocalNotification(type: .mention, event: ev, target: ev, content: content)
            create_local_notification(profiles: damus_state.profiles, notify: notify )
        }
    } else if type == .boost && damus_state.settings.repost_notification, let inner_ev = ev.get_inner_event(cache: damus_state.events) {
        let notify = LocalNotification(type: .repost, event: ev, target: inner_ev, content: inner_ev.content)
        create_local_notification(profiles: damus_state.profiles, notify: notify)
    } else if type == .like && damus_state.settings.like_notification,
              let evid = ev.referenced_ids.last?.ref_id,
              let liked_event = damus_state.events.lookup(evid)
    {
        let notify = LocalNotification(type: .like, event: ev, target: liked_event, content: liked_event.content)
        create_local_notification(profiles: damus_state.profiles, notify: notify)
    }

}

func create_local_notification(profiles: Profiles, notify: LocalNotification) {
    let content = UNMutableNotificationContent()
    var title = ""
    var identifier = ""
    
    let displayName = event_author_name(profiles: profiles, pubkey: notify.event.pubkey)
    
    switch notify.type {
    case .mention:
        title = String(format: NSLocalizedString("Mentioned by %@", comment: "Mentioned by heading in local notification"), displayName)
        identifier = "myMentionNotification"
    case .repost:
        title = String(format: NSLocalizedString("Reposted by %@", comment: "Reposted by heading in local notification"), displayName)
        identifier = "myBoostNotification"
    case .like:
        title = String(format: NSLocalizedString("%@ reacted with %@", comment: "Reacted by heading in local notification"), displayName, notify.event.content)
        identifier = "myLikeNotification"
    case .dm:
        title = displayName
        identifier = "myDMNotification"
    case .zap:
        // not handled here
        break
    }
    content.title = title
    content.body = notify.content
    content.sound = UNNotificationSound.default
    content.userInfo = notify.to_lossy().to_user_info()

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Error: \(error)")
        } else {
            print("Local notification scheduled")
        }
    }
}

