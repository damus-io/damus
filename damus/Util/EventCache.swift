//
//  EventCache.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import Combine
import Foundation
import UIKit

class ImageMetadataState {
    var state: ImageMetaProcessState
    var meta: ImageMetadata
    
    init(state: ImageMetaProcessState, meta: ImageMetadata) {
        self.state = state
        self.meta = meta
    }
}

enum ImageMetaProcessState {
    case processing
    case failed
    case processed(UIImage)
    
    var img: UIImage? {
        switch self {
        case .processed(let img):
            return img
        default:
            return nil
        }
    }
}

class EventData: ObservableObject {
    @Published var translations: TranslateStatus?
    @Published var artifacts: NoteArtifacts?
    @Published var zaps: [Zap]
    var validated: ValidationResult
    
    init(zaps: [Zap] = []) {
        self.translations = nil
        self.artifacts = nil
        self.zaps = zaps
        self.validated = .unknown
    }
}

class EventCache {
    private var events: [String: NostrEvent] = [:]
    private var replies = ReplyMap()
    private var cancellable: AnyCancellable?
    private var image_metadata: [String: ImageMetadataState] = [:]
    private var event_data: [String: EventData] = [:]
    
    //private var thread_latest: [String: Int64]
    
    init() {
        cancellable = NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification
        ).sink { [weak self] _ in
            self?.prune()
        }
    }
    
    private func get_cache_data(_ evid: String) -> EventData {
        guard let data = event_data[evid] else {
            let data = EventData()
            event_data[evid] = data
            return data
        }
        
        return data
    }
    
    func is_event_valid(_ evid: String) -> ValidationResult {
        return get_cache_data(evid).validated
    }
    
    func store_event_validation(evid: String, validated: ValidationResult) {
        get_cache_data(evid).validated = validated
    }
    
    func store_translation_artifacts(evid: String, translated: TranslateStatus) {
        get_cache_data(evid).translations = translated
    }
    
    func store_artifacts(evid: String, artifacts: NoteArtifacts) {
        get_cache_data(evid).artifacts = artifacts
    }
    
    @discardableResult
    func store_zap(zap: Zap) -> Bool {
        var data = get_cache_data(zap.target.id)
        return insert_uniq_sorted_zap_by_amount(zaps: &data.zaps, new_zap: zap)
    }
    
    func lookup_zaps(target: ZapTarget) -> [Zap] {
        return get_cache_data(target.id).zaps
    }
    
    func store_img_metadata(url: URL, meta: ImageMetadataState) {
        self.image_metadata[url.absoluteString.lowercased()] = meta
    }
    
    func lookup_artifacts(evid: String) -> NoteArtifacts? {
        return get_cache_data(evid).artifacts
    }
    
    func lookup_img_metadata(url: URL) -> ImageMetadataState? {
        return image_metadata[url.absoluteString.lowercased()]
    }
    
    func lookup_translated_artifacts(evid: String) -> TranslateStatus? {
        return get_cache_data(evid).translations
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
        event_data = [:]
        replies.replies = [:]
    }
}
