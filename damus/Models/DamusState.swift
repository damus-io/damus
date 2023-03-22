//
//  DamusState.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation
import LinkPresentation

struct DamusState {
    let pool: RelayPool
    let keypair: Keypair
    let likes: EventCounter
    let boosts: EventCounter
    let contacts: Contacts
    let profiles: Profiles
    let dms: DirectMessagesModel
    let previews: PreviewCache
    let zaps: Zaps
    let lnurls: LNUrls
    let settings: UserSettingsStore
    let relay_filters: RelayFilters
    let relay_model_cache: RelayModelCache
    let drafts: Drafts
    let events: EventCache
    let bookmarks: BookmarksManager
    let postbox: PostBox
    let bootstrap_relays: [String]
    let replies: ReplyCounter
    let muted_threads: MutedThreadsManager
    let wallet: WalletModel
    let nav: NavigationCoordinator
    let music: MusicController?
    let video: VideoController
    let ndb: Ndb
    var purple: DamusPurple
    
    init(pool: RelayPool, keypair: Keypair, likes: EventCounter, boosts: EventCounter, contacts: Contacts, profiles: Profiles, dms: DirectMessagesModel, previews: PreviewCache, zaps: Zaps, lnurls: LNUrls, settings: UserSettingsStore, relay_filters: RelayFilters, relay_model_cache: RelayModelCache, drafts: Drafts, events: EventCache, bookmarks: BookmarksManager, postbox: PostBox, bootstrap_relays: [String], replies: ReplyCounter, muted_threads: MutedThreadsManager, wallet: WalletModel, nav: NavigationCoordinator, music: MusicController?, video: VideoController, ndb: Ndb, purple: DamusPurple? = nil) {
        self.pool = pool
        self.keypair = keypair
        self.likes = likes
        self.boosts = boosts
        self.contacts = contacts
        self.profiles = profiles
        self.dms = dms
        self.previews = previews
        self.zaps = zaps
        self.lnurls = lnurls
        self.settings = settings
        self.relay_filters = relay_filters
        self.relay_model_cache = relay_model_cache
        self.drafts = drafts
        self.events = events
        self.bookmarks = bookmarks
        self.postbox = postbox
        self.bootstrap_relays = bootstrap_relays
        self.replies = replies
        self.muted_threads = muted_threads
        self.wallet = wallet
        self.nav = nav
        self.music = music
        self.video = video
        self.ndb = ndb
        self.purple = purple ?? DamusPurple(
            environment: settings.purple_api_local_test_mode ? .local_test : .production,
            keypair: keypair
        )
    }

    @discardableResult
    func add_zap(zap: Zapping) -> Bool {
        // store generic zap mapping
        self.zaps.add_zap(zap: zap)
        let stored = self.events.store_zap(zap: zap)
        
        // thread zaps
        if let ev = zap.event, !settings.nozaps, zap.is_in_thread {
            // [nozaps]: thread zaps are only available outside of the app store
            replies.count_replies(ev, keypair: self.keypair)
            events.add_replies(ev: ev, keypair: self.keypair)
        }

        // associate with events as well
        return stored
    }
    
    var pubkey: Pubkey {
        return keypair.pubkey
    }
    
    var is_privkey_user: Bool {
        keypair.privkey != nil
    }
    
    static var empty: DamusState {
        let empty_pub: Pubkey = .empty
        let empty_sec: Privkey = .empty
        let kp = Keypair(pubkey: empty_pub, privkey: nil)
        
        return DamusState.init(
            pool: RelayPool(ndb: .empty),
            keypair: Keypair(pubkey: empty_pub, privkey: empty_sec),
            likes: EventCounter(our_pubkey: empty_pub),
            boosts: EventCounter(our_pubkey: empty_pub),
            contacts: Contacts(our_pubkey: empty_pub),
            profiles: Profiles(ndb: .empty),
            dms: DirectMessagesModel(our_pubkey: empty_pub),
            previews: PreviewCache(),
            zaps: Zaps(our_pubkey: empty_pub),
            lnurls: LNUrls(),
            settings: UserSettingsStore(),
            relay_filters: RelayFilters(our_pubkey: empty_pub),
            relay_model_cache: RelayModelCache(),
            drafts: Drafts(),
            events: EventCache(ndb: .empty),
            bookmarks: BookmarksManager(pubkey: empty_pub),
            postbox: PostBox(pool: RelayPool(ndb: .empty)),
            bootstrap_relays: [],
            replies: ReplyCounter(our_pubkey: empty_pub),
            muted_threads: MutedThreadsManager(keypair: kp),
            wallet: WalletModel(settings: UserSettingsStore()),
            nav: NavigationCoordinator(),
            music: nil,
            video: VideoController(),
            ndb: .empty
        )
    }
}
