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
