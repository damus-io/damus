//
//  NWCManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-05.
//

extension NostrNetworkManager {
    /// Manages the user's connected NWC wallet
    class NWCManager {
        private var delegate: Delegate
        
        init(delegate: Delegate) {
            self.delegate = delegate
        }
        
        
        
        protocol Delegate {
            func nwcWalletChanged()
        }
    }
}
