//
//  NotificationsModel.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import Foundation

enum NotificationItem {
    case repost(String, EventGroup)
    case reaction(String, EventGroup)
    case profile_zap(ZapGroup)
    case event_zap(String, ZapGroup)
    case reply(NostrEvent)
    
    var is_reply: NostrEvent? {
        if case .reply(let ev) = self {
            return ev
        }
        return nil
    }
    
    var is_zap: ZapGroup? {
        switch self {
        case .profile_zap(let zapgrp):
            return zapgrp
        case .event_zap(_, let zapgrp):
            return zapgrp
        case .reaction:
            return nil
        case .reply:
            return nil
        case .repost:
            return nil
        }
    }
    
    var id: String {
        switch self {
        case .repost(let evid, _):
            return "repost_" + evid
        case .reaction(let evid, _):
            return "reaction_" + evid
        case .profile_zap:
            return "profile_zap"
        case .event_zap(let evid, _):
            return "event_zap_" + evid
        case .reply(let ev):
            return "reply_" + ev.id
        }
    }
    
    var last_event_at: Int64 {
        switch self {
        case .reaction(_, let evgrp):
            return evgrp.last_event_at
        case .repost(_, let evgrp):
            return evgrp.last_event_at
        case .profile_zap(let zapgrp):
            return zapgrp.last_event_at
        case .event_zap(_, let zapgrp):
            return zapgrp.last_event_at
        case .reply(let reply):
            return reply.created_at
        }
    }
    
    func would_filter(_ isIncluded: (NostrEvent) -> Bool) -> Bool {
        switch self {
        case .repost(_, let evgrp):
            return evgrp.would_filter(isIncluded)
        case .reaction(_, let evgrp):
            return evgrp.would_filter(isIncluded)
        case .profile_zap(let zapgrp):
            return zapgrp.would_filter(isIncluded)
        case .event_zap(_, let zapgrp):
            return zapgrp.would_filter(isIncluded)
        case .reply(let ev):
            return !isIncluded(ev)
        }
    }
    
    func filter(_ isIncluded: (NostrEvent) -> Bool) -> NotificationItem? {
        switch self {
        case .repost(let evid, let evgrp):
            return evgrp.filter(isIncluded).map { .repost(evid, $0) }
        case .reaction(let evid, let evgrp):
            return evgrp.filter(isIncluded).map { .reaction(evid, $0) }
        case .profile_zap(let zapgrp):
            return zapgrp.filter(isIncluded).map { .profile_zap($0) }
        case .event_zap(let evid, let zapgrp):
            return zapgrp.filter(isIncluded).map { .event_zap(evid, $0) }
        case .reply(let ev):
            if isIncluded(ev) { return .reply(ev) }
            return nil
        }
    }
}

class NotificationsModel: ObservableObject, ScrollQueue {
    var incoming_zaps: [Zapping]
    var incoming_events: [NostrEvent]
    var should_queue: Bool
    
    // mappings from events to
    var zaps: [String: ZapGroup]
    var profile_zaps: ZapGroup
    var reactions: [String: EventGroup]
    var reposts: [String: EventGroup]
    var replies: [NostrEvent]
    var has_reply: Set<String>
    var has_ev: Set<String>
    
    @Published var notifications: [NotificationItem]
    
    init() {
        self.zaps = [:]
        self.reactions = [:]
        self.reposts = [:]
        self.replies = []
        self.has_reply = Set()
        self.should_queue = true
        self.incoming_zaps = []
        self.incoming_events = []
        self.profile_zaps = ZapGroup()
        self.notifications = []
        self.has_ev = Set()
    }
    
    func set_should_queue(_ val: Bool) {
        self.should_queue = val
    }
    
    func uniq_pubkeys() -> [String] {
        var pks = Set<String>()
        
        for ev in incoming_events {
            pks.insert(ev.pubkey)
        }
        
        for grp in reposts {
            for ev in grp.value.events {
                pks.insert(ev.pubkey)
            }
        }
        
        for ev in replies {
            pks.insert(ev.pubkey)
        }
        
        for zap in incoming_zaps {
            pks.insert(zap.request.pubkey)
        }
        
        return Array(pks)
    }
    
    func build_notifications() -> [NotificationItem] {
        var notifs: [NotificationItem] = []
        
        for el in zaps {
            let evid = el.key
            let zapgrp = el.value

            let notif: NotificationItem = .event_zap(evid, zapgrp)
            notifs.append(notif)
        }
        
        if !profile_zaps.zaps.isEmpty {
            notifs.append(.profile_zap(profile_zaps))
        }
        
        for el in reposts {
            let evid = el.key
            let evgrp = el.value
            
            notifs.append(.repost(evid, evgrp))
        }
        
        for el in reactions {
            let evid = el.key
            let evgrp = el.value
            
            notifs.append(.reaction(evid, evgrp))
        }
        
        for reply in replies {
            notifs.append(.reply(reply))
        }
        
        notifs.sort { $0.last_event_at > $1.last_event_at }
        return notifs
    }
    
    
    private func insert_repost(_ ev: NostrEvent, cache: EventCache) -> Bool {
        guard let reposted_ev = ev.get_inner_event(cache: cache) else {
            return false
        }
        
        let id = reposted_ev.id
        
        if let evgrp = self.reposts[id] {
            return evgrp.insert(ev)
        } else {
            let evgrp = EventGroup()
            self.reposts[id] = evgrp
            return evgrp.insert(ev)
        }
    }
    
    private func insert_text(_ ev: NostrEvent) -> Bool {
        guard !has_reply.contains(ev.id) else {
            return false
        }
        
        has_reply.insert(ev.id)
        replies.append(ev)
        
        return true
    }
    
    private func insert_reaction(_ ev: NostrEvent) -> Bool {
        guard let ref_id = ev.referenced_ids.last else {
            return false
        }
        
        let id = ref_id.id
        
        if let evgrp = self.reactions[id] {
            return evgrp.insert(ev)
        } else {
            let evgrp = EventGroup()
            self.reactions[id] = evgrp
            return evgrp.insert(ev)
        }
    }
    
    private func insert_event_immediate(_ ev: NostrEvent, cache: EventCache) -> Bool {
        if ev.known_kind == .boost {
            return insert_repost(ev, cache: cache)
        } else if ev.known_kind == .like {
            return insert_reaction(ev)
        } else if ev.known_kind == .text {
            return insert_text(ev)
        }
        
        return false
    }
    
    private func insert_zap_immediate(_ zap: Zapping) -> Bool {
        switch zap.target {
        case .note(let notezt):
            let id = notezt.note_id
            if let zapgrp = self.zaps[notezt.note_id] {
                return zapgrp.insert(zap)
            } else {
                let zapgrp = ZapGroup()
                self.zaps[id] = zapgrp
                return zapgrp.insert(zap)
            }
            
        case .profile:
            return profile_zaps.insert(zap)
        }
    }
    
    func insert_event(_ ev: NostrEvent, damus_state: DamusState) -> Bool {
        if has_ev.contains(ev.id) {
            return false
        }
        
        if should_queue {
            incoming_events.append(ev)
            has_ev.insert(ev.id)
            return true
        }
        
        if insert_event_immediate(ev, cache: damus_state.events) {
            self.notifications = build_notifications()
            return true
        }
        
        return false
    }
    
    func insert_zap(_ zap: Zapping) -> Bool {
        if should_queue {
            return insert_uniq_sorted_zap_by_created(zaps: &incoming_zaps, new_zap: zap)
        }
        
        if insert_zap_immediate(zap) {
            self.notifications = build_notifications()
            return true
        }
        
        return false
    }
    
    func filter(_ isIncluded: (NostrEvent) -> Bool)  {
        var changed = false
        var count = 0
        
        count = incoming_events.count
        incoming_events = incoming_events.filter(isIncluded)
        changed = changed || incoming_events.count != count
        
        count = profile_zaps.zaps.count
        profile_zaps.zaps = profile_zaps.zaps.filter { zap in isIncluded(zap.request) }
        changed = changed || profile_zaps.zaps.count != count
        
        for el in reactions {
            count = el.value.events.count
            el.value.events = el.value.events.filter(isIncluded)
            changed = changed || el.value.events.count != count
        }
        
        for el in reposts {
            count = el.value.events.count
            el.value.events = el.value.events.filter(isIncluded)
            changed = changed || el.value.events.count != count
        }
        
        for el in zaps {
            count = el.value.zaps.count
            el.value.zaps = el.value.zaps.filter {
                isIncluded($0.request)
            }
            changed = changed || el.value.zaps.count != count
        }
        
        count = replies.count
        replies = replies.filter(isIncluded)
        changed = changed || replies.count != count
        
        if changed {
            self.notifications = build_notifications()
        }
    }
    
    func flush(_ damus_state: DamusState) -> Bool {
        var inserted = false
        
        for zap in incoming_zaps {
            inserted = insert_zap_immediate(zap) || inserted
        }
        
        for event in incoming_events {
            inserted = insert_event_immediate(event, cache: damus_state.events) || inserted
        }
        
        if inserted {
            self.notifications = build_notifications()
        }
        
        return inserted
    }
}
