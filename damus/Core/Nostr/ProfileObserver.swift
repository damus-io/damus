//
//  ProfileObserver.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-09-19.
//
import Combine
import Foundation

@MainActor
class ProfileObserver: ObservableObject {
    private let pubkey: Pubkey
    private var observerTask: Task<Void, any Error>? = nil
    private let damusState: DamusState
    
    init(pubkey: Pubkey, damusState: DamusState) {
        self.pubkey = pubkey
        self.damusState = damusState
        self.watchProfileChanges()
    }
    
    private func watchProfileChanges() {
        observerTask?.cancel()
        observerTask = Task {
            for await _ in await damusState.nostrNetwork.profilesManager.streamProfile(pubkey: self.pubkey) {
                try Task.checkCancellation()
                DispatchQueue.main.async { self.objectWillChange.send() }
            }
        }
    }
    
    deinit {
        observerTask?.cancel()
    }
}
