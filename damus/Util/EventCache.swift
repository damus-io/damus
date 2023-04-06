//
//  EventCache.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import Combine
import Foundation
import UIKit

class EventCache {
    private var events: [String: NostrEvent] = [:]
    private var replies = ReplyMap()
    private var cancellable: AnyCancellable?
    private var translations: [String: TranslateStatus] = [:]
    private var artifacts: [String: NoteArtifacts] = [:]
    
    //private var thread_latest: [String: Int64]
    
    init() {
        cancellable = NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification
        ).sink { [weak self] _ in
            self?.prune()
        }
    }
    
    func store_translation_artifacts(evid: String, translated: TranslateStatus) {
        self.translations[evid] = translated
    }
    
    func store_artifacts(evid: String, artifacts: NoteArtifacts) {
        self.artifacts[evid] = artifacts
    }
    
    func lookup_artifacts(evid: String) -> NoteArtifacts? {
        return self.artifacts[evid]
    }
    
    func lookup_translated_artifacts(evid: String) -> TranslateStatus? {
        return self.translations[evid]
    }
    
    func parent_events(event: NostrEvent) -> [NostrEvent] {
        var parents: [NostrEvent] = []
        
        var ev = event
        
        while true {
            guard let direct_reply = ev.direct_replies(nil).first else {
                break
            }
            
            guard let next_ev = lookup(direct_reply.ref_id), next_ev != ev else {
                break
            }
            
            parents.append(next_ev)
            ev = next_ev
        }
        
        return parents.reversed()
    }
    
    func add_replies(ev: NostrEvent) {
        for reply in ev.direct_replies(nil) {
            replies.add(id: reply.ref_id, reply_id: ev.id)
        }
    }
    
    func child_events(event: NostrEvent) -> [NostrEvent] {
        guard let xs = replies.lookup(event.id) else {
            return []
        }
        let evs: [NostrEvent] = xs.reduce(into: [], { evs, evid in
            guard let ev = self.lookup(evid) else {
                return
            }
            
            evs.append(ev)
        }).sorted(by: { $0.created_at < $1.created_at })
        return evs
    }
    
    func upsert(_ ev: NostrEvent) -> NostrEvent {
        if let found = lookup(ev.id) {
            return found
        }
        
        insert(ev)
        return ev
    }
    
    func lookup(_ evid: String) -> NostrEvent? {
        return events[evid]
    }
    
    func insert(_ ev: NostrEvent) {
        guard events[ev.id] == nil else {
            return
        }
        events[ev.id] = ev
    }
    
    private func prune() {
        events = [:]
        translations = [:]
        artifacts = [:]
        replies.replies = [:]
    }
}
