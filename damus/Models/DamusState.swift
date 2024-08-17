//
//  DamusState.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation
import LinkPresentation
import EmojiPicker

class DamusState: HeadlessDamusState {
    let pool: RelayPool
    let keypair: Keypair
    let likes: EventCounter
    let boosts: EventCounter
    let quote_reposts: EventCounter
    let contacts: Contacts
    let mutelist_manager: MutelistManager
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
    let bootstrap_relays: [RelayURL]
    let replies: ReplyCounter
    let wallet: WalletModel
    let nav: NavigationCoordinator
    let music: MusicController?
    let video: VideoController
    let ndb: Ndb
    var purple: DamusPurple
    var push_notification_client: PushNotificationClient
    let emoji_provider: EmojiProvider

    init(pool: RelayPool, keypair: Keypair, likes: EventCounter, boosts: EventCounter, contacts: Contacts, mutelist_manager: MutelistManager, profiles: Profiles, dms: DirectMessagesModel, previews: PreviewCache, zaps: Zaps, lnurls: LNUrls, settings: UserSettingsStore, relay_filters: RelayFilters, relay_model_cache: RelayModelCache, drafts: Drafts, events: EventCache, bookmarks: BookmarksManager, postbox: PostBox, bootstrap_relays: [RelayURL], replies: ReplyCounter, wallet: WalletModel, nav: NavigationCoordinator, music: MusicController?, video: VideoController, ndb: Ndb, purple: DamusPurple? = nil, quote_reposts: EventCounter, emoji_provider: EmojiProvider) {
        self.pool = pool
        self.keypair = keypair
        self.likes = likes
        self.boosts = boosts
        self.contacts = contacts
        self.mutelist_manager = mutelist_manager
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
        self.wallet = wallet
        self.nav = nav
        self.music = music
        self.video = video
        self.ndb = ndb
        self.purple = purple ?? DamusPurple(
            settings: settings,
            keypair: keypair
        )
        self.quote_reposts = quote_reposts
        self.push_notification_client = PushNotificationClient(keypair: keypair, settings: settings)
        self.emoji_provider = emoji_provider
    }
    
    @MainActor
    convenience init?(keypair: Keypair) {
        // nostrdb
        var mndb = Ndb()
        if mndb == nil {
            // try recovery
            print("DB ISSUE! RECOVERING")
            mndb = Ndb.safemode()

            // out of space or something?? maybe we need a in-memory fallback
            if mndb == nil {
                logout(nil)
                return nil
            }
        }
        
        let navigationCoordinator: NavigationCoordinator = NavigationCoordinator()
        let home: HomeModel = HomeModel()
        let sub_id = UUID().uuidString

        guard let ndb = mndb else { return nil }
        let pubkey = keypair.pubkey

        let pool = RelayPool(ndb: ndb, keypair: keypair)
        let model_cache = RelayModelCache()
        let relay_filters = RelayFilters(our_pubkey: pubkey)
        let bootstrap_relays = load_bootstrap_relays(pubkey: pubkey)
        
        let settings = UserSettingsStore.globally_load_for(pubkey: pubkey)

        let new_relay_filters = load_relay_filters(pubkey) == nil
        for relay in bootstrap_relays {
            let descriptor = RelayDescriptor(url: relay, info: .rw)
            add_new_relay(model_cache: model_cache, relay_filters: relay_filters, pool: pool, descriptor: descriptor, new_relay_filters: new_relay_filters, logging_enabled: settings.developer_mode)
        }

        pool.register_handler(sub_id: sub_id, handler: home.handle_event)
        
        if let nwc_str = settings.nostr_wallet_connect,
           let nwc = WalletConnectURL(str: nwc_str) {
            try? pool.add_relay(.nwc(url: nwc.relay))
        }
        self.init(
            pool: pool,
            keypair: keypair,
            likes: EventCounter(our_pubkey: pubkey),
            boosts: EventCounter(our_pubkey: pubkey),
            contacts: Contacts(our_pubkey: pubkey),
            mutelist_manager: MutelistManager(user_keypair: keypair),
            profiles: Profiles(ndb: ndb),
            dms: home.dms,
            previews: PreviewCache(),
            zaps: Zaps(our_pubkey: pubkey),
            lnurls: LNUrls(),
            settings: settings,
            relay_filters: relay_filters,
            relay_model_cache: model_cache,
            drafts: Drafts(),
            events: EventCache(ndb: ndb),
            bookmarks: BookmarksManager(pubkey: pubkey),
            postbox: PostBox(pool: pool),
            bootstrap_relays: bootstrap_relays,
            replies: ReplyCounter(our_pubkey: pubkey),
            wallet: WalletModel(settings: settings),
            nav: navigationCoordinator,
            music: MusicController(onChange: { _ in }),
            video: VideoController(),
            ndb: ndb,
            quote_reposts: .init(our_pubkey: pubkey),
            emoji_provider: DefaultEmojiProvider(showAllVariations: true)
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

    func close() {
        print("txn: damus close")
        wallet.disconnect()
        pool.close()
        ndb.close()
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
            mutelist_manager: MutelistManager(user_keypair: kp),
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
            wallet: WalletModel(settings: UserSettingsStore()),
            nav: NavigationCoordinator(),
            music: nil,
            video: VideoController(),
            ndb: .empty,
            quote_reposts: .init(our_pubkey: empty_pub),
            emoji_provider: DefaultEmojiProvider(showAllVariations: true)
        )
    }
}
