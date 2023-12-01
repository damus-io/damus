//
//  NotificationExtensionState.swift
//  DamusNotificationService
//
//  Created by Daniel D’Aquino on 2023-11-27.
//

import Foundation

struct NotificationExtensionState: HeadlessDamusState {
    let ndb: Ndb
    let settings: UserSettingsStore
    let contacts: Contacts
    let muted_threads: MutedThreadsManager
    let keypair: Keypair
    let profiles: Profiles
    let zaps: Zaps
    let lnurls: LNUrls
    
    init?() {
        guard let ndb = try? Ndb(owns_db_file: false) else { return nil }
        self.ndb = ndb
        self.settings = UserSettingsStore()
        
        guard let keypair = get_saved_keypair() else { return nil }
        self.contacts = Contacts(our_pubkey: keypair.pubkey)
        self.muted_threads = MutedThreadsManager(keypair: keypair)
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
