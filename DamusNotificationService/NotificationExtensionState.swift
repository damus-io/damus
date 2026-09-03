//
//  NotificationExtensionState.swift
//  DamusNotificationService
//
//  Created by Daniel D’Aquino on 2023-11-27.
//

import Foundation

@MainActor
struct NotificationExtensionState: HeadlessDamusState {
    let ndb: Ndb
    let settings: UserSettingsStore
    let contacts: Contacts
    let mutelist_manager: MutelistManager
    let keypair: Keypair
    let profiles: Profiles
    let zaps: Zaps
    let lnurls: LNUrls
    
    init?() {
        guard let keypair = get_saved_keypair() else { return nil }

        // dumb stuff needed for property wrappers.
        //
        // Done before opening nostrdb so that the pubkey-scoped settings keys resolve even on the
        // path where the db fails to open and `didReceive` falls back to the plain formatter — which
        // reads `UserSettingsStore.legacy_nip04_dms_enabled` to decide whether a kind-4 DM is
        // something this account still wants notifications for.
        UserSettingsStore.pubkey = keypair.pubkey

        guard let ndb = Ndb(owns_db_file: false) else { return nil }
        self.ndb = ndb

        // nostrdb unwraps NIP-59 giftwraps on its ingester threads, and the key it needs to do that
        // lives in those threads' memory — `ndb_add_key` never writes anything to lmdb. So the
        // registration the app made says nothing at all about this process: without this line the
        // extension can hand a kind-1059 push to nostrdb and nothing will ever come out of it.
        //
        // Nothing to do for a pubkey-only (read-only) login. There is no secret key, so there is
        // nothing that could open a giftwrap, and a NIP-17 push has no readable content for us.
        //
        // Deliberately *not* followed by `backfillGiftwrapsInBackground()`: that walks the whole
        // kind-1059 index, and this process exists for a few seconds to describe one message.
        if let privkey = keypair.privkey {
            ndb.add_key(privkey)
        }

        self.settings = UserSettingsStore()
        
        self.contacts = Contacts(our_pubkey: keypair.pubkey)
        self.mutelist_manager = MutelistManager(user_keypair: keypair)
        self.keypair = keypair
        self.profiles = Profiles(ndb: ndb)
        self.zaps = Zaps(our_pubkey: keypair.pubkey)
        self.lnurls = LNUrls()
    }
    
    @discardableResult
    func add_zap(zap: Zapping) -> Bool {
        // store generic zap mapping
        self.zaps.add_zap(zap: zap)
        
        return true
    }
}
