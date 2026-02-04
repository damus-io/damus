//
//  DamusState.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation
import LinkPresentation
import EmojiPicker

class DamusState: HeadlessDamusState, ObservableObject {
    let keypair: Keypair
    let likes: EventCounter
    let boosts: EventCounter
    let quote_reposts: EventCounter
    let contacts: Contacts
    let contactCards: ContactCard
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
    let replies: ReplyCounter
    let wallet: WalletModel
    let nav: NavigationCoordinator
    let music: MusicController?
    let video: DamusVideoCoordinator
    let ndb: Ndb
    var purple: DamusPurple
    var push_notification_client: PushNotificationClient
    let emoji_provider: EmojiProvider
    let favicon_cache: FaviconCache
    private(set) var nostrNetwork: NostrNetworkManager
    var snapshotManager: DatabaseSnapshotManager

    init(keypair: Keypair, likes: EventCounter, boosts: EventCounter, contacts: Contacts, contactCards: ContactCard, mutelist_manager: MutelistManager, profiles: Profiles, dms: DirectMessagesModel, previews: PreviewCache, zaps: Zaps, lnurls: LNUrls, settings: UserSettingsStore, relay_filters: RelayFilters, relay_model_cache: RelayModelCache, drafts: Drafts, events: EventCache, bookmarks: BookmarksManager, replies: ReplyCounter, wallet: WalletModel, nav: NavigationCoordinator, music: MusicController?, video: DamusVideoCoordinator, ndb: Ndb, purple: DamusPurple? = nil, quote_reposts: EventCounter, emoji_provider: EmojiProvider, favicon_cache: FaviconCache, addNdbToRelayPool: Bool = true) {
        self.keypair = keypair
        self.likes = likes
        self.boosts = boosts
        self.contacts = contacts
        self.contactCards = contactCards
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
        self.favicon_cache = FaviconCache()

        let networkManagerDelegate = NostrNetworkManagerDelegate(settings: settings, contacts: contacts, ndb: ndb, keypair: keypair, relayModelCache: relay_model_cache, relayFilters: relay_filters)
        let nostrNetwork = NostrNetworkManager(delegate: networkManagerDelegate, addNdbToRelayPool: addNdbToRelayPool)
        self.nostrNetwork = nostrNetwork
        self.wallet.nostrNetwork = nostrNetwork
        self.snapshotManager = .init(ndb: ndb)
    }
    
    @MainActor
    convenience init?(keypair: Keypair, owns_db_file: Bool) {
        // nostrdb
        var mndb = Ndb(owns_db_file: owns_db_file)
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

        // Add user's private key to nostrdb for gift wrap decryption (NIP-17)
        if let privkey = keypair.privkey {
            print("[DM-DEBUG] Adding key to nostrdb...")
            let keyAdded = ndb.addKey(privkey)
            print("[DM-DEBUG] addKey returned: \(keyAdded)")
            if keyAdded {
                // Reprocess any previously received gift wraps with the new key
                do {
                    let result = try ndb.processGiftWraps()
                    print("[DM-DEBUG] processGiftWraps returned: \(result)")
                } catch {
                    print("[DM-DEBUG] processGiftWraps threw error: \(error)")
                }
            } else {
                print("[DM-DEBUG] addKey failed or key already exists")
                // Try processing anyway in case key was already added
                do {
                    let result = try ndb.processGiftWraps()
                    print("[DM-DEBUG] processGiftWraps (retry) returned: \(result)")
                } catch {
                    print("[DM-DEBUG] processGiftWraps (retry) threw: \(error)")
                }
            }
        } else {
            print("[DM-DEBUG] No private key available for NIP-17")
        }

        let pubkey = keypair.pubkey

        let model_cache = RelayModelCache()
        let relay_filters = RelayFilters(our_pubkey: pubkey)
        let bootstrap_relays = load_bootstrap_relays(pubkey: pubkey)
        
        let settings = UserSettingsStore.globally_load_for(pubkey: pubkey)

        self.init(
            keypair: keypair,
            likes: EventCounter(our_pubkey: pubkey),
            boosts: EventCounter(our_pubkey: pubkey),
            contacts: Contacts(our_pubkey: pubkey),
            contactCards: ContactCardManager(),
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
            replies: ReplyCounter(our_pubkey: pubkey),
            wallet: WalletModel(settings: settings), // nostrNetwork is connected after initialization
            nav: navigationCoordinator,
            music: MusicController(onChange: { _ in }),
            video: DamusVideoCoordinator(),
            ndb: ndb,
            quote_reposts: .init(our_pubkey: pubkey),
            emoji_provider: DefaultEmojiProvider(showAllVariations: true),
            favicon_cache: FaviconCache()
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
        Task {
            try await self.push_notification_client.revoke_token()
        }
        wallet.disconnect()
        Task {
            await nostrNetwork.close()  // Close ndb streaming tasks before closing ndb to avoid memory errors
            ndb.close()
        }
    }

    /// Initializes NIP-17 gift wrap decryption by registering the user's private key
    /// and reprocessing stored gift wraps. Runs on a background task to avoid blocking main thread.
    func initializeNip17KeysIfNeeded() {
        guard let privkey = keypair.privkey else {
            print("[DM-DEBUG] No private key available for NIP-17")
            return
        }

        Task.detached(priority: .utility) { [ndb, keypair] in
            print("[DM-DEBUG] Our pubkey: \(keypair.pubkey.hex())")
            print("[DM-DEBUG] Adding key to nostrdb...")
            let keyAdded = ndb.addKey(privkey)
            print("[DM-DEBUG] addKey returned: \(keyAdded)")
            do {
                let result = try ndb.processGiftWraps()
                print("[DM-DEBUG] processGiftWraps returned: \(result)")

                // Wait a moment for async processing to complete
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

                // Debug: Query nostrdb for kind:14 and kind:1059 counts
                let dm_chat_filter = NostrFilter(kinds: [.dm_chat])
                let giftwrap_filter = NostrFilter(kinds: [.gift_wrap])

                let dm_chat_keys = try ndb.query(filters: [NdbFilter(from: dm_chat_filter)], maxResults: 1000)
                let giftwrap_keys = try ndb.query(filters: [NdbFilter(from: giftwrap_filter)], maxResults: 1000)

                print("[DM-DEBUG] nostrdb contains: \(dm_chat_keys.count) kind:14 rumors, \(giftwrap_keys.count) kind:1059 gift_wraps")
            } catch {
                print("[DM-DEBUG] processGiftWraps threw error: \(error)")
            }
        }
    }

    @MainActor
    static var empty: DamusState {
        let empty_pub: Pubkey = .empty
        let empty_sec: Privkey = .empty
        let kp = Keypair(pubkey: empty_pub, privkey: nil)
        
        return DamusState.init(
            keypair: Keypair(pubkey: empty_pub, privkey: empty_sec),
            likes: EventCounter(our_pubkey: empty_pub),
            boosts: EventCounter(our_pubkey: empty_pub),
            contacts: Contacts(our_pubkey: empty_pub),
            contactCards: ContactCardManagerMock(),
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
            replies: ReplyCounter(our_pubkey: empty_pub),
            wallet: WalletModel(settings: UserSettingsStore()),
            nav: NavigationCoordinator(),
            music: nil,
            video: DamusVideoCoordinator(),
            ndb: .empty,
            quote_reposts: .init(our_pubkey: empty_pub),
            emoji_provider: DefaultEmojiProvider(showAllVariations: true),
            favicon_cache: FaviconCache()
        )
    }
}

fileprivate extension DamusState {
    struct NostrNetworkManagerDelegate: NostrNetworkManager.Delegate {
        let settings: UserSettingsStore
        let contacts: Contacts
        
        var ndb: Ndb
        var keypair: Keypair
        
        var latestRelayListEventIdHex: String? {
            get { self.settings.latestRelayListEventIdHex }
            set { self.settings.latestRelayListEventIdHex = newValue }
        }
        
        @MainActor
        var latestContactListEvent: NostrEvent? { self.contacts.event }
        var bootstrapRelays: [RelayURL] { get_default_bootstrap_relays() }
        var developerMode: Bool { self.settings.developer_mode }
        var experimentalLocalRelayModelSupport: Bool { self.settings.enable_experimental_local_relay_model }
        var relayModelCache: RelayModelCache
        var relayFilters: RelayFilters
        
        var nwcWallet: WalletConnectURL? {
            guard let nwcString = self.settings.nostr_wallet_connect else { return nil }
            return WalletConnectURL(str: nwcString)
        }
    }
}
