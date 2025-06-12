//
//  EventCache.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import Combine
import Foundation
import UIKit
import LinkPresentation
import Kingfisher

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
    case not_needed
}

class TranslationModel: ObservableObject {
    @Published var note_language: String?
    @Published var state: TranslateStatus
    
    init(state: TranslateStatus) {
        self.state = state
        self.note_language = nil
    }
}

class NoteArtifactsModel: ObservableObject {
    @Published var state: NoteArtifactState
    
    init(state: NoteArtifactState) {
        self.state = state
    }
}

class PreviewModel: ObservableObject {
    @Published var state: PreviewState
    
    init(state: PreviewState) {
        self.state = state
    }
}

class RelativeTimeModel: ObservableObject {
    @Published var value: String = ""
}

class MediaMetaModel: ObservableObject {
    @Published var fill: ImageFill? = nil
}

class EventData {
    var translations_model: TranslationModel
    var artifacts_model: NoteArtifactsModel
    var preview_model: PreviewModel
    var zaps_model : ZapsDataModel
    var relative_time: RelativeTimeModel = RelativeTimeModel()
    var validated: ValidationResult
    var media_metadata_model: MediaMetaModel
    
    var translations: TranslateStatus {
        return translations_model.state
    }
    
    var artifacts: NoteArtifactState {
        return artifacts_model.state
    }
    
    var preview: PreviewState {
        return preview_model.state
    }
    
    init(zaps: [Zapping] = []) {
        self.translations_model = .init(state: .havent_tried)
        self.artifacts_model = .init(state: .not_loaded)
        self.zaps_model = .init(zaps)
        self.validated = .unknown
        self.media_metadata_model = MediaMetaModel()
        self.preview_model = .init(state: .not_loaded)
    }
}

class EventCache {
    // TODO: remove me and change code to use ndb directly
    private let ndb: Ndb
    private var events: [NoteId: NostrEvent] = [:]
    private var cancellable: AnyCancellable?
    private var image_metadata: [String: ImageMetadataState] = [:] // lowercased URL key
    private var event_data: [NoteId: EventData] = [:]
    var replies = ReplyMap()

    //private var thread_latest: [String: Int64]

    init(ndb: Ndb) {
        self.ndb = ndb
        cancellable = NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification
        ).sink { [weak self] _ in
            self?.prune()
        }
    }
    
    func get_cache_data(_ evid: NoteId) -> EventData {
        guard let data = event_data[evid] else {
            let data = EventData()
            event_data[evid] = data
            return data
        }
        
        return data
    }
    
    func is_event_valid(_ evid: NoteId) -> ValidationResult {
        return get_cache_data(evid).validated
    }
    
    func store_event_validation(evid: NoteId, validated: ValidationResult) {
        get_cache_data(evid).validated = validated
    }
    
    @discardableResult
    func store_zap(zap: Zapping) -> Bool {
        let data = get_cache_data(NoteId(zap.target.id)).zaps_model
        if let ev = zap.event {
            insert(ev)
        }
        return insert_uniq_sorted_zap_by_amount(zaps: &data.zaps, new_zap: zap)
    }
    
    func remove_zap(zap: Zapping) {
        switch zap.target {
        case .note(let note_target):
            let zaps = get_cache_data(note_target.note_id).zaps_model
            zaps.remove(reqid: zap.request.id)
        case .profile:
            // these aren't stored anywhere yet
            break
        }
    }
    
    func lookup_zaps(target: ZapTarget) -> [Zapping] {
        return get_cache_data(NoteId(target.id)).zaps_model.zaps
    }
    
    func store_img_metadata(url: URL, meta: ImageMetadataState) {
        self.image_metadata[url.absoluteString.lowercased()] = meta
    }
    
    func lookup_img_metadata(url: URL) -> ImageMetadataState? {
        return image_metadata[url.absoluteString.lowercased()]
    }
    
    func parent_events(event: NostrEvent, keypair: Keypair) -> [NostrEvent] {
        var parents: [NostrEvent] = []
        
        var ev = event
        
        while true {
            guard let direct_reply = ev.direct_replies(),
                  let next_ev = lookup(direct_reply), next_ev != ev
            else {
                break
            }
            
            parents.append(next_ev)
            ev = next_ev
        }
        
        return parents.reversed()
    }
    
    func add_replies(ev: NostrEvent, keypair: Keypair) {
        if let reply = ev.direct_replies() {
            replies.add(id: reply, reply_id: ev.id)
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

    /*
    func lookup_by_key(_ key: UInt64) -> NostrEvent? {
        ndb.lookup_note_by_key(key)
    }
     */

    func lookup(_ evid: NoteId) -> NostrEvent? {
        if let ev = events[evid] {
            return ev
        }

        if let ev = self.ndb.lookup_note(evid)?.unsafeUnownedValue?.to_owned() {
            events[ev.id] = ev
            return ev
        }

        return nil
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

func should_translate(event: NostrEvent, our_keypair: Keypair, note_lang: String?) -> Bool {
    // don't translate reposts, longform, etc
    if event.kind != 1 {
        return false;
    }

    // Do not translate self-authored notes if logged in with a private key
    // as we can assume the user can understand their own notes.
    // The detected language prediction could be incorrect and not in the list of preferred languages.
    // Offering a translation in this case is definitely incorrect so let's avoid it altogether.
    if our_keypair.privkey != nil && our_keypair.pubkey == event.pubkey {
        return false
    }

    if let note_lang {
        let currentLanguage = localeToLanguage(Locale.current.identifier)

        // Don't translate if the note is in our current language
        guard currentLanguage != note_lang else {
            return false
        }
    }

    // we should start translating if we have auto_translate on
    return true
}

func can_and_should_translate(event: NostrEvent, our_keypair: Keypair, settings: UserSettingsStore, note_lang: String?) -> Bool {
    guard settings.can_translate else {
        return false
    }

    return should_translate(event: event, our_keypair: our_keypair, note_lang: note_lang)
}

func should_preload_translation(event: NostrEvent, our_keypair: Keypair, current_status: TranslateStatus, settings: UserSettingsStore, note_lang: String?) -> Bool {
    switch current_status {
    case .havent_tried:
        return can_and_should_translate(event: event, our_keypair: our_keypair, settings: settings, note_lang: note_lang) && settings.auto_translate
    case .translating: return false
    case .translated: return false
    case .not_needed: return false
    }
}

struct PreloadPlan {
    let data: EventData
    let img_metadata: [ImageMetadata]
    let event: NostrEvent
    var load_artifacts: Bool
    let load_translations: Bool
    let load_preview: Bool
}

func load_preview(artifacts: NoteArtifactsSeparated) async -> Preview? {
    guard let link = artifacts.links.first else {
        return nil
    }
    let meta = await Preview.fetch_metadata(for: link)
    return Preview(meta: meta)
}

func get_preload_plan(evcache: EventCache, ev: NostrEvent, our_keypair: Keypair, settings: UserSettingsStore) -> PreloadPlan? {
    let cache = evcache.get_cache_data(ev.id)
    let load_artifacts = cache.artifacts.should_preload
    if load_artifacts {
        cache.artifacts_model.state = .loading
    }

    // Cached event might not have the note language determined yet, so determine the language here before figuring out if translations should be preloaded.
    let note_lang = cache.translations_model.note_language ?? /*ev.note_language(our_keypair.privkey)*/ current_language()

    let load_translations = should_preload_translation(event: ev, our_keypair: our_keypair, current_status: cache.translations, settings: settings, note_lang: note_lang)
    if load_translations {
        cache.translations_model.state = .translating
    }
    
    let load_urls = event_image_metadata(ev: ev)
        .reduce(into: [ImageMetadata]()) { to_load, meta in
            let cached = evcache.lookup_img_metadata(url: meta.url)
            guard cached == nil else {
                return
            }
            
            let m = ImageMetadataState(state: .processing, meta: meta)
            evcache.store_img_metadata(url: meta.url, meta: m)
            to_load.append(meta)
    }
    
    let load_preview = cache.preview.should_preload
    if load_preview {
        cache.preview_model.state = .loading
    }
    
    if !load_artifacts && !load_translations && !load_preview && load_urls.count == 0 {
        return nil
    }
    
    return PreloadPlan(data: cache, img_metadata: load_urls, event: ev, load_artifacts: load_artifacts, load_translations: load_translations, load_preview: load_preview)
}

func preload_image(url: URL) {
    if ImageCache.default.isCached(forKey: url.absoluteString) {
        //print("Preloaded image \(url.absoluteString) found in cache")
        // looks like we already have it cached. no download needed
        return
    }
    
    //print("Preloading image \(url.absoluteString)")

    KingfisherManager.shared.retrieveImage(with: Kingfisher.KF.ImageResource(downloadURL: url)) { val in
        //print("Preloaded image \(url.absoluteString)")
    }
}

func is_animated_image(url: URL) -> Bool {
    guard let ext = url.pathComponents.last?.split(separator: ".").last?.lowercased() else {
        return false
    }
    
    return ext == "gif"
}

func preload_event(plan: PreloadPlan, state: DamusState) async {
    var artifacts: NoteArtifacts? = plan.data.artifacts.artifacts
    let settings = state.settings
    let profiles = state.profiles
    let our_keypair = state.keypair
    
    //print("Preloading event \(plan.event.content)")

    if artifacts == nil && plan.load_artifacts {
        let arts = await ContentRenderer().render_note_content(ndb: state.ndb, ev: plan.event, profiles: profiles, keypair: our_keypair)
        artifacts = arts
        
        // we need these asap
        DispatchQueue.main.async {
            plan.data.artifacts_model.state = .loaded(arts)
        }
        
        for url in arts.images {
            guard !is_animated_image(url: url) else {
                // jb55: I have a theory that animated images are not working with the preloader due
                // to some disk-cache write race condition. normal images need not apply
                
                continue
            }
            
            preload_image(url: url)
        }
    }
    
    if plan.load_preview, note_artifact_is_separated(kind: plan.event.known_kind) {
        let arts: NoteArtifacts
        if let artifacts {
            arts = artifacts
        }
        else {
            arts = await ContentRenderer().render_note_content(ndb: state.ndb, ev: plan.event, profiles: profiles, keypair: our_keypair)
        }

        // only separated artifacts have previews
        if case .separated(let sep) = arts {
            let preview = await load_preview(artifacts: sep)
            DispatchQueue.main.async {
                if let preview {
                    plan.data.preview_model.state = .loaded(preview)
                } else {
                    plan.data.preview_model.state = .loaded(.failed)
                }
            }
        }
    }
    
    let note_language = plan.data.translations_model.note_language ?? plan.event.note_language(ndb: state.ndb, our_keypair) ?? current_language()

    var translations: TranslateStatus? = nil
    // We have to recheck should_translate here now that we have note_language
    if plan.load_translations && can_and_should_translate(event: plan.event, our_keypair: our_keypair, settings: settings, note_lang: note_language) && settings.auto_translate
    {
        translations = await translate_note(profiles: profiles, keypair: our_keypair, event: plan.event, settings: settings, note_lang: note_language, purple: state.purple)
    }
    
    let ts = translations
    if plan.data.translations_model.note_language == nil || ts != nil {
        DispatchQueue.main.async {
            if let ts {
                plan.data.translations_model.state = ts
            }
            if plan.data.translations_model.note_language != note_language {
                plan.data.translations_model.note_language = note_language
            }
        }
    }
    
}

func preload_events(state: DamusState, events: [NostrEvent]) {
    let event_cache = state.events
    let our_keypair = state.keypair
    let settings = state.settings
    
    let plans = events.compactMap { ev in
        get_preload_plan(evcache: event_cache, ev: ev, our_keypair: our_keypair, settings: settings)
    }
    
    if plans.count == 0 {
        return
    }
    
    Task {
        for plan in plans {
            await preload_event(plan: plan, state: state)
        }
    }
}

