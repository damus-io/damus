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
    let relay_metadata: RelayMetadatas
    let drafts: Drafts
    let events: EventCache
    let bookmarks: BookmarksManager
    let postbox: PostBox
    let bootstrap_relays: [String]
    let replies: ReplyCounter
    let muted_threads: MutedThreadsManager
    let wallet: WalletModel
    
    @discardableResult
    func add_zap(zap: Zapping) -> Bool {
        // store generic zap mapping
        self.zaps.add_zap(zap: zap)
        // associate with events as well
        return self.events.store_zap(zap: zap)
    }
    
    var pubkey: String {
        return keypair.pubkey
    }
    
    var is_privkey_user: Bool {
        keypair.privkey != nil
    }
    
    static var empty: DamusState {
        return DamusState.init(pool: RelayPool(), keypair: Keypair(pubkey: "", privkey: ""), likes: EventCounter(our_pubkey: ""), boosts: EventCounter(our_pubkey: ""), contacts: Contacts(our_pubkey: ""), profiles: Profiles(), dms: DirectMessagesModel(our_pubkey: ""), previews: PreviewCache(), zaps: Zaps(our_pubkey: ""), lnurls: LNUrls(), settings: UserSettingsStore(), relay_filters: RelayFilters(our_pubkey: ""), relay_metadata: RelayMetadatas(), drafts: Drafts(), events: EventCache(), bookmarks: BookmarksManager(pubkey: ""), postbox: PostBox(pool: RelayPool()), bootstrap_relays: [], replies: ReplyCounter(our_pubkey: ""), muted_threads: MutedThreadsManager(keypair: Keypair(pubkey: "", privkey: nil)), wallet: WalletModel(settings: UserSettingsStore())) }
}
