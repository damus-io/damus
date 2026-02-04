//
//  HeadlessDamusState.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-27.
//

import Foundation

/// HeadlessDamusState
///
/// A protocl for a lighter headless alternative to DamusState that does not have dependencies on View objects or UI logic.
/// This is useful in limited environments (e.g. Notification Service Extension) where we do not want View/UI dependencies
protocol HeadlessDamusState {
    var ndb: Ndb { get }
    var settings: UserSettingsStore { get }
    var contacts: Contacts { get }
    var mutelist_manager: MutelistManager { get }
    var keypair: Keypair { get }
    var profiles: Profiles { get }
    var zaps: Zaps { get }
    var polls: PollResultsStore { get }
    var lnurls: LNUrls { get }
    
    @discardableResult
    func add_zap(zap: Zapping) -> Bool
}
