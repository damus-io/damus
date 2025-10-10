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
    let mutelist_manager: MutelistManager
    let keypair: Keypair
    let profiles: Profiles
    let zaps: Zaps
    let polls: PollResultsStore
    let lnurls: LNUrls
    
    init?() {
        guard let ndb = Ndb(owns_db_file: false) else { return nil }
        self.ndb = ndb
        
        guard let keypair = get_saved_keypair() else { return nil }
        
        // dumb stuff needed for property wrappers
        UserSettingsStore.pubkey = keypair.pubkey
        self.settings = UserSettingsStore()
        
        self.contacts = Contacts(our_pubkey: keypair.pubkey)
        self.mutelist_manager = MutelistManager(user_keypair: keypair)
        self.keypair = keypair
        self.profiles = Profiles(ndb: ndb)
        self.zaps = Zaps(our_pubkey: keypair.pubkey)
        self.polls = PollResultsStore()
        self.lnurls = LNUrls()
    }
    
    @discardableResult
    func add_zap(zap: Zapping) -> Bool {
        // store generic zap mapping
        self.zaps.add_zap(zap: zap)
        
        return true
    }
}
