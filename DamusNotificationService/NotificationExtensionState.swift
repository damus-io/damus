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
    
    init?() {
        guard let ndb = try? Ndb(owns_db_file: false) else { return nil }
        self.ndb = ndb
        self.settings = UserSettingsStore()
        
        guard let keypair = get_saved_keypair() else { return nil }
        self.contacts = Contacts(our_pubkey: keypair.pubkey)
        self.muted_threads = MutedThreadsManager(keypair: keypair)
        self.keypair = keypair
        self.profiles = Profiles(ndb: ndb)
    }
}
