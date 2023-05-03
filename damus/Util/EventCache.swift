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
    
    var img: UIImage? {
        switch self {
        case .processed(let img):
            return img
        default:
            return nil
        }
    }
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
    
    func store(preview: LPLinkMetadata?)  {
        state = .loaded(Preview(meta: preview))
    }
    
    init(state: PreviewState) {
        self.state = state
    }
}

class ZapsDataModel: ObservableObject {
    @Published var zaps: [Zap]
    
    init(_ zaps: [Zap]) {
        self.zaps = zaps
    }
}

class RelativeTimeModel: ObservableObject {
    private(set) var last_update: Int64
    @Published var value: String {
        didSet {
            self.last_update = Int64(Date().timeIntervalSince1970)
        }
    }
    
    init(value: String) {
        self.last_update = 0
        self.value = ""
    }
}

class EventData {
    var translations_model: TranslationModel
    var artifacts_model: NoteArtifactsModel
    var preview_model: PreviewModel
    var zaps_model : ZapsDataModel
    var relative_time: RelativeTimeModel
    var validated: ValidationResult
    
    var translations: TranslateStatus {
        return translations_model.state
    }
    
    var artifacts: NoteArtifactState {
        return artifacts_model.state
    }
    
    var preview: PreviewState {
        return preview_model.state
    }
    
    var zaps: [Zap] {
        return zaps_model.zaps
    }
    
    init(zaps: [Zap] = []) {
        self.translations_model = .init(state: .havent_tried)
        self.artifacts_model = .init(state: .not_loaded)
        self.zaps_model = .init(zaps)
        self.validated = .unknown
        self.preview_model = .init(state: .not_loaded)
        self.relative_time = .init(value: "")
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
    
    func get_cache_data(_ evid: String) -> EventData {
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
        get_cache_data(evid).translations_model.state = translated
    }
    
    func store_artifacts(evid: String, artifacts: NoteArtifacts) {
        get_cache_data(evid).artifacts_model.state = .loaded(artifacts)
    }
    
    @discardableResult
    func store_zap(zap: Zap) -> Bool {
        let data = get_cache_data(zap.target.id).zaps_model
        return insert_uniq_sorted_zap_by_amount(zaps: &data.zaps, new_zap: zap)
    }
    
    func lookup_zaps(target: ZapTarget) -> [Zap] {
        return get_cache_data(target.id).zaps_model.zaps
    }
    
    func store_img_metadata(url: URL, meta: ImageMetadataState) {
        self.image_metadata[url.absoluteString.lowercased()] = meta
    }
    
    func lookup_artifacts(evid: String) -> NoteArtifactState {
        return get_cache_data(evid).artifacts_model.state
    }
    
    func lookup_img_metadata(url: URL) -> ImageMetadataState? {
        return image_metadata[url.absoluteString.lowercased()]
    }
    
    func lookup_translated_artifacts(evid: String) -> TranslateStatus? {
        return get_cache_data(evid).translations_model.state
    }
    
    func parent_events(event: NostrEvent) -> [NostrEvent] {
        var parents: [NostrEvent] = []
        
        var ev = event
        
        while true {
            guard let direct_reply = ev.direct_replies(nil).last else {
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

func should_translate(event: NostrEvent, our_keypair: Keypair, settings: UserSettingsStore, note_lang: String?) -> Bool {
    guard settings.can_translate else {
        return false
    }
    
    // Do not translate self-authored notes if logged in with a private key
    // as we can assume the user can understand their own notes.
    // The detected language prediction could be incorrect and not in the list of preferred languages.
    // Offering a translation in this case is definitely incorrect so let's avoid it altogether.
    if our_keypair.privkey != nil && our_keypair.pubkey == event.pubkey {
        return false
    }
    
    if let note_lang {
        let preferredLanguages = Set(Locale.preferredLanguages.map { localeToLanguage($0) })
        
        // Don't translate if its in our preferred languages
        guard !preferredLanguages.contains(note_lang) else {
            // if its the same, give up and don't retry
            return false
        }
    }
    
    // we should start translating if we have auto_translate on
    return true
}

func should_preload_translation(event: NostrEvent, our_keypair: Keypair, current_status: TranslateStatus, settings: UserSettingsStore, note_lang: String?) -> Bool {
    
    switch current_status {
    case .havent_tried:
        return should_translate(event: event, our_keypair: our_keypair, settings: settings, note_lang: note_lang) && settings.auto_translate
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

func load_preview(artifacts: NoteArtifacts) async -> Preview? {
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
    
    let load_translations = should_preload_translation(event: ev, our_keypair: our_keypair, current_status: cache.translations, settings: settings, note_lang: cache.translations_model.note_language)
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
        print("Preloaded image \(url.absoluteString) found in cache")
        // looks like we already have it cached. no download needed
        return
    }
    
    print("Preloading image \(url.absoluteString)")
    
    KingfisherManager.shared.retrieveImage(with: ImageResource(downloadURL: url)) { val in
        print("Preloaded image \(url.absoluteString)")
    }
}

func preload_pfp(profiles: Profiles, pubkey: String) {
    // preload pfp
    if let profile = profiles.lookup(id: pubkey),
       let picture = profile.picture,
       let url = URL(string: picture) {
        preload_image(url: url)
    }
}

func preload_event(plan: PreloadPlan, state: DamusState) async {
    var artifacts: NoteArtifacts? = plan.data.artifacts.artifacts
    let settings = state.settings
    let profiles = state.profiles
    let our_keypair = state.keypair
    
    print("Preloading event \(plan.event.content)")
    
    for meta in plan.img_metadata {
        process_image_metadata(cache: state.events, meta: meta, ev: plan.event)
    }
    
    preload_pfp(profiles: profiles, pubkey: plan.event.pubkey)
    if let inner_ev = plan.event.get_inner_event(cache: state.events), inner_ev.pubkey != plan.event.pubkey {
        preload_pfp(profiles: profiles, pubkey: inner_ev.pubkey)
    }
    
    if artifacts == nil && plan.load_artifacts {
        let arts = render_note_content(ev: plan.event, profiles: profiles, privkey: our_keypair.privkey)
        artifacts = arts
        
        // we need these asap
        DispatchQueue.main.async {
            plan.data.artifacts_model.state = .loaded(arts)
        }
        
        for url in arts.images {
            preload_image(url: url)
        }
    }
    
    if plan.load_preview {
        let arts = artifacts ?? render_note_content(ev: plan.event, profiles: profiles, privkey: our_keypair.privkey)
        let preview = await load_preview(artifacts: arts)
        DispatchQueue.main.async {
            if let preview {
                plan.data.preview_model.state = .loaded(preview)
            } else {
                plan.data.preview_model.state = .loaded(.failed)
            }
        }
    }
    
    let note_language = plan.data.translations_model.note_language ?? plan.event.note_language(our_keypair.privkey) ?? current_language()
    
    var translations: TranslateStatus? = nil
    // We have to recheck should_translate here now that we have note_language
    if plan.load_translations && should_translate(event: plan.event, our_keypair: our_keypair, settings: settings, note_lang: note_language) && settings.auto_translate
    {
        translations = await translate_note(profiles: profiles, privkey: our_keypair.privkey, event: plan.event, settings: settings, note_lang: note_language)
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
    
    Task.init {
        for plan in plans {
            await preload_event(plan: plan, state: state)
        }
    }
}

