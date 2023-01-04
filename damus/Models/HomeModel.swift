//
//  HomeModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation
import UIKit

struct NewEventsBits {
    let bits: Int

    init() {
        bits = 0
    }

    init (prev: NewEventsBits, setting: Timeline) {
        self.bits = prev.bits | timeline_bit(setting)
    }

    init (prev: NewEventsBits, unsetting: Timeline) {
        self.bits = prev.bits & ~timeline_bit(unsetting)
    }

    func is_set(_ timeline: Timeline) -> Bool {
        let notification_bit = timeline_bit(timeline)
        return (bits & notification_bit) == notification_bit
    }

}

class HomeModel: ObservableObject {
    var damus_state: DamusState

    var has_event: [String: Set<String>] = [:]
    var deleted_events: Set<String> = Set()
    var channels: [String: NostrEvent] = [:]
    var last_event_of_kind: [String: [Int: NostrEvent]] = [:]
    var done_init: Bool = false

    let home_subid = UUID().description
    let contacts_subid = UUID().description
    let notifications_subid = UUID().description
    let dms_subid = UUID().description
    let init_subid = UUID().description
    let profiles_subid = UUID().description

    @Published var new_events: NewEventsBits = NewEventsBits()
    @Published var notifications: [NostrEvent] = []
    @Published var dms: DirectMessagesModel = DirectMessagesModel()
    @Published var events: [NostrEvent] = []
    @Published var loading: Bool = false
    @Published var signal: SignalModel = SignalModel()

    init() {
        self.damus_state = DamusState.empty
    }

    init(damus_state: DamusState) {
        self.damus_state = damus_state
    }

    var pool: RelayPool {
        return damus_state.pool
    }

    func has_sub_id_event(sub_id: String, ev_id: String) -> Bool {
        if !has_event.keys.contains(sub_id) {
            has_event[sub_id] = Set()
            return false
        }

        return has_event[sub_id]!.contains(ev_id)
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
            handle_channel_meta(ev)
        }
    }
    
    func handle_channel_create(_ ev: NostrEvent) {
        guard ev.is_valid else {
            return
        }
        
        self.channels[ev.id] = ev
    }
    
    func handle_channel_meta(_ ev: NostrEvent) {
    }
    
    func handle_delete_event(_ ev: NostrEvent) {
        guard ev.is_valid else {
            return
        }
        
        self.deleted_events.insert(ev.id)
    }

    func handle_contact_event(sub_id: String, relay_id: String, ev: NostrEvent) {
        process_contact_event(pool: damus_state.pool, contacts: damus_state.contacts, pubkey: damus_state.pubkey, ev: ev)

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

        if let inner_ev = ev.inner_event {
            boost_ev_id = inner_ev.id
            
            guard inner_ev.is_valid else {
                return
            }

            if inner_ev.is_textlike {
                handle_text_event(sub_id: sub_id, ev)
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
        }
    }

    func handle_like_event(_ ev: NostrEvent) {
        guard let e = ev.last_refid() else {
            // no id ref? invalid like event
            return
        }

        // CHECK SIGS ON THESE

        switch damus_state.likes.add_event(ev, target: e.ref_id) {
        case .already_counted:
            break
        case .success(let n):
            let liked = Counted(event: ev, id: e.ref_id, total: n)
            notify(.liked, liked)
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
            case .error(let merr):
                let desc = merr.debugDescription
                if desc.contains("Software caused connection abort") {
                    pool.reconnect(to: [relay_id])
                }
            case .disconnected: fallthrough
            case .cancelled:
                pool.reconnect(to: [relay_id])
            case .reconnectSuggested(let t):
                if t {
                    pool.reconnect(to: [relay_id])
                }
            default:
                break
            }
            
            update_signal_from_pool(signal: signal, pool: damus_state.pool)

            print("ws_event \(ev)")

        case .nostr_event(let ev):
            switch ev {
            case .event(let sub_id, let ev):
                // globally handle likes
                let always_process = sub_id == notifications_subid || sub_id == contacts_subid || sub_id == home_subid || sub_id == dms_subid || sub_id == init_subid || ev.known_kind == .like || ev.known_kind == .contacts || ev.known_kind == .metadata
                if !always_process {
                    // TODO: other views like threads might have their own sub ids, so ignore those events... or should we?
                    return
                }

                self.process_event(sub_id: sub_id, relay_id: relay_id, ev: ev)
            case .notice(let msg):
                //self.events.insert(NostrEvent(content: "NOTICE from \(relay_id): \(msg)", pubkey: "system"), at: 0)
                print(msg)

            case .eose(let sub_id):
                
                if sub_id == dms_subid {
                    let dms = dms.dms.flatMap { $0.1.events }
                    load_profiles(profiles_subid: profiles_subid, relay_id: relay_id, events: dms, damus_state: damus_state)
                } else if sub_id == notifications_subid {
                    load_profiles(profiles_subid: profiles_subid, relay_id: relay_id, events: notifications, damus_state: damus_state)
                }
                
                self.loading = false
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

        var contacts_filter = NostrFilter.filter_kinds([0])
        contacts_filter.authors = friends
        
        var our_contacts_filter = NostrFilter.filter_kinds([3, 0])
        our_contacts_filter.authors = [damus_state.pubkey]

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
        var home_filter = NostrFilter.filter_kinds([
            NostrKind.text.rawValue,
            NostrKind.chat.rawValue,
            NostrKind.like.rawValue,
            NostrKind.boost.rawValue,
        ])
        // include our pubkey as well even if we're not technically a friend
        home_filter.authors = friends
        home_filter.limit = 500

        var notifications_filter = NostrFilter.filter_kinds([
            NostrKind.text.rawValue,
            NostrKind.chat.rawValue,
            NostrKind.like.rawValue,
            NostrKind.boost.rawValue,
        ])
        notifications_filter.pubkeys = [damus_state.pubkey]
        notifications_filter.limit = 100

        var home_filters = [home_filter]
        var notifications_filters = [notifications_filter]
        var contacts_filters = [contacts_filter, our_contacts_filter]
        var dms_filters = [dms_filter, our_dms_filter]

        let last_of_kind = relay_id.flatMap { last_event_of_kind[$0] } ?? [:]

        home_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: home_filters)
        contacts_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: contacts_filters)
        notifications_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: notifications_filters)
        dms_filters = update_filters_with_since(last_of_kind: last_of_kind, filters: dms_filters)

        print_filters(relay_id: relay_id, filters: [home_filters, contacts_filters, notifications_filters, dms_filters])

        if let relay_id = relay_id {
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

    func handle_metadata_event(_ ev: NostrEvent) {
        process_metadata_event(profiles: damus_state.profiles, ev: ev)
    }

    func get_last_event_of_kind(relay_id: String, kind: Int) -> NostrEvent? {
        guard let m = last_event_of_kind[relay_id] else {
            last_event_of_kind[relay_id] = [:]
            return nil
        }

        return m[kind]
    }

    func handle_last_event(ev: NostrEvent, timeline: Timeline, shouldNotify: Bool = true) {
        let last_ev = get_last_event(timeline)

        if last_ev == nil || last_ev!.created_at < ev.created_at {
            save_last_event(ev, timeline: timeline)
            if shouldNotify {
                new_events = NewEventsBits(prev: new_events, setting: timeline)
            }
        }
    }

    func handle_notification(ev: NostrEvent) {
        if !insert_uniq_sorted_event(events: &notifications, new_ev: ev, cmp: { $0.created_at > $1.created_at }) {
            return
        }

        handle_last_event(ev: ev, timeline: .notifications)
    }

    func insert_home_event(_ ev: NostrEvent) -> Bool {
        let ok = insert_uniq_sorted_event(events: &self.events, new_ev: ev, cmp: { $0.created_at > $1.created_at })
        if ok {
            handle_last_event(ev: ev, timeline: .home)
        }
        return ok
    }

    func should_hide_event(_ ev: NostrEvent) -> Bool {
        return !ev.should_show_event
    }

    func handle_text_event(sub_id: String, _ ev: NostrEvent) {
        if should_hide_event(ev) {
            return
        }

        if sub_id == home_subid {
            let _ = insert_home_event(ev)
        } else if sub_id == notifications_subid {
            handle_notification(ev: ev)
        }
    }

    func handle_dm(_ ev: NostrEvent) {

        var inserted = false
        var found = false
        let ours = ev.pubkey == self.damus_state.pubkey
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

        for (pk, _) in dms.dms {
            if pk == the_pk {
                found = true
                inserted = insert_uniq_sorted_event(events: &(dms.dms[i].1.events), new_ev: ev) {
                    $0.created_at < $1.created_at
                }

                break
            }
            i += 1
        }

        if !found {
            inserted = true
            let model = DirectMessageModel(events: [ev])
            dms.dms.append((the_pk, model))
        }

        if inserted {
            handle_last_event(ev: ev, timeline: .dms, shouldNotify: !ours)

            dms.dms = dms.dms.sorted { a, b in
                if a.1.events.count > 0 && b.1.events.count > 0 {
                    return a.1.events.last!.created_at > b.1.events.last!.created_at
                }
                return false
            }
        }
    }
}


func update_signal_from_pool(signal: SignalModel, pool: RelayPool) {
    if signal.max_signal != pool.relays.count {
        signal.max_signal = pool.relays.count
    }

    if signal.signal != pool.num_connecting {
        signal.signal = signal.max_signal - pool.num_connecting
    }
}

func add_contact_if_friend(contacts: Contacts, ev: NostrEvent) {
    if !contacts.is_friend(ev.pubkey) {
        return
    }

    contacts.add_friend_contact(ev)
}

func load_our_contacts(contacts: Contacts, our_pubkey: String, m_old_ev: NostrEvent?, ev: NostrEvent) {
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

func process_metadata_event(profiles: Profiles, ev: NostrEvent) {
    guard let profile: Profile = decode_data(Data(ev.content.utf8)) else {
        return
    }

    var old_nip05: String? = nil
    if let mprof = profiles.lookup_with_timestamp(id: ev.pubkey) {
        old_nip05 = mprof.profile.nip05
        if mprof.timestamp > ev.created_at {
            // skip if we already have an newer profile
            return
        }
    }

    let tprof = TimestampedProfile(profile: profile, timestamp: ev.created_at)
    profiles.add(id: ev.pubkey, profile: tprof)
    
    if let nip05 = profile.nip05, old_nip05 != profile.nip05 {
        Task.detached(priority: .background) {
            let validated = await validate_nip05(pubkey: ev.pubkey, nip05_str: nip05)
            if validated != nil {
                print("validated nip05 for '\(nip05)'")
            }
            
            DispatchQueue.main.async {
                profiles.validated[ev.pubkey] = validated
                notify(.profile_updated, ProfileUpdate(pubkey: ev.pubkey, profile: profile))
            }
        }
    }
    
    // load pfps asap
    let picture = tprof.profile.picture ?? robohash(ev.pubkey)
    if let _ = URL(string: picture) {
        DispatchQueue.main.async {
            notify(.profile_updated, ProfileUpdate(pubkey: ev.pubkey, profile: profile))
        }
    }
    
    notify(.profile_updated, ProfileUpdate(pubkey: ev.pubkey, profile: profile))
}

func robohash(_ pk: String) -> String {
    return "https://robohash.org/" + pk
}

func load_our_stuff(pool: RelayPool, contacts: Contacts, pubkey: String, ev: NostrEvent) {
    guard ev.pubkey == pubkey else {
        return
    }
    
    // only use new stuff
    if let current_ev = contacts.event {
        guard ev.created_at > current_ev.created_at else {
            return
        }
    }
    
    let m_old_ev = contacts.event
    contacts.event = ev

    load_our_contacts(contacts: contacts, our_pubkey: pubkey, m_old_ev: m_old_ev, ev: ev)
    load_our_relays(contacts: contacts, our_pubkey: pubkey, pool: pool, m_old_ev: m_old_ev, ev: ev)
}

func process_contact_event(pool: RelayPool, contacts: Contacts, pubkey: String, ev: NostrEvent) {
    load_our_stuff(pool: pool, contacts: contacts, pubkey: pubkey, ev: ev)
    add_contact_if_friend(contacts: contacts, ev: ev)
}

func load_our_relays(contacts: Contacts, our_pubkey: String, pool: RelayPool, m_old_ev: NostrEvent?, ev: NostrEvent) {
    let bootstrap_dict: [String: RelayInfo] = [:]
    let old_decoded = m_old_ev.flatMap { decode_json_relays($0.content) } ?? BOOTSTRAP_RELAYS.reduce(into: bootstrap_dict) { (d, r) in
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
    
    for d in diff {
        changed = true
        if new.contains(d) {
            if let url = URL(string: d) {
                try? pool.add_relay(url, info: decoded[d] ?? .rw)
            }
        } else {
            pool.remove_relay(d)
        }
    }
    
    if changed {
        notify(.relays_changed, ())
    }
}


