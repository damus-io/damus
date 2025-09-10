//
//  UserRelayListManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-27.
//

import Foundation
import Combine

extension NostrNetworkManager {
    /// Manages the user's relay list
    ///
    /// - It can compute the user's current relay list
    /// - It can compute the best relay list to connect to
    /// - It can edit the user's relay list
    class UserRelayListManager {
        private var delegate: Delegate
        private let pool: RelayPool
        private let reader: SubscriptionManager
        
        private var relayListObserverTask: Task<Void, Never>? = nil
        private var walletUpdatesObserverTask: AnyCancellable? = nil
        
        init(delegate: Delegate, pool: RelayPool, reader: SubscriptionManager) {
            self.delegate = delegate
            self.pool = pool
            self.reader = reader
        }
        
        // MARK: - Computing the relays to connect to
        
        private func relaysToConnectTo() -> [RelayPool.RelayDescriptor] {
            return self.computeRelaysToConnectTo(with: self.getBestEffortRelayList())
        }
        
        private func computeRelaysToConnectTo(with relayList: NIP65.RelayList) -> [RelayPool.RelayDescriptor] {
            let regularRelayDescriptorList = relayList.toRelayDescriptors()
            if let nwcWallet = delegate.nwcWallet {
                return regularRelayDescriptorList + [.nwc(url: nwcWallet.relay)]
            }
            return regularRelayDescriptorList
        }
        
        // MARK: - Getting the user's relay list
        
        /// Gets the "best effort" relay list.
        ///
        /// It attempts to get a relay list from the user. If one is not available, it uses the default bootstrap list.
        ///
        /// This is always guaranteed to return a relay list.
        func getBestEffortRelayList() -> NIP65.RelayList {
            guard let userCurrentRelayList = self.getUserCurrentRelayList() else {
                return NIP65.RelayList(relays: delegate.bootstrapRelays)
            }
            return userCurrentRelayList
        }
        
        /// Gets the user's current relay list.
        ///
        /// It attempts to get a NIP-65 relay list from the local database, or falls back to a legacy list.
        func getUserCurrentRelayList() -> NIP65.RelayList? {
            if let latestRelayListEvent = try? self.getLatestNIP65RelayList() { return latestRelayListEvent }
            if let latestRelayListEvent = try? self.getLatestKind3RelayList() { return latestRelayListEvent }
            if let latestRelayListEvent = try? self.getLatestUserDefaultsRelayList() { return latestRelayListEvent }
            return nil
        }
        
        /// Gets the latest NIP-65 relay list from NostrDB.
        ///
        /// This is `private` because it is part of internal logic. Callers should use the higher level functions.
        ///
        /// - Returns: The latest NIP-65 relay list object
        private func getLatestNIP65RelayList() throws(LoadingError) -> NIP65.RelayList? {
            guard let latestRelayListEvent = self.getLatestNIP65RelayListEvent() else { return nil }
            guard let list = try? NIP65.RelayList(event: latestRelayListEvent) else { throw .relayListParseError }
            return list
        }
        
        /// Gets the latest NIP-65 relay list event from NostrDB.
        /// 
        /// This is `private` because it is part of internal logic. Callers should use the higher level functions.
        ///
        /// It is recommended to use this function only if the NostrEvent metadata is needed. For cases where only the relay list info is needed, use `getLatestNIP65RelayList` instead.
        ///
        /// - Returns: The latest NIP-65 relay list NdbNote
        private func getLatestNIP65RelayListEvent() -> NdbNote? {
            guard let latestRelayListEventId = delegate.latestRelayListEventIdHex else { return nil }
            guard let latestRelayListEventId = NoteId(hex: latestRelayListEventId) else { return nil }
            return delegate.ndb.lookup_note(latestRelayListEventId)?.unsafeUnownedValue?.to_owned()
        }
        
        /// Gets the latest `kind:3` relay list from NostrDB.
        ///
        /// This is `private` because it is part of internal logic. Callers should use the higher level functions.
        private func getLatestKind3RelayList() throws(LoadingError) -> NIP65.RelayList? {
            guard let latestContactListEvent = delegate.latestContactListEvent else { return nil }
            guard let legacyContactList = try? NIP65.RelayList.fromLegacyContactList(latestContactListEvent) else { throw .relayListParseError }
            return legacyContactList
        }
        
        /// Gets the latest relay list from `UserDefaults`
        ///
        /// This is `private` because it is part of internal logic. Callers should use the higher level functions.
        private func getLatestUserDefaultsRelayList() throws(LoadingError) -> NIP65.RelayList? {
            let key = bootstrap_relays_setting_key(pubkey: delegate.keypair.pubkey)
            guard let relays = UserDefaults.standard.stringArray(forKey: key) else { return nil }
            let relayUrls = relays.compactMap({ RelayURL($0) })
            if relayUrls.count == 0 { return nil }
            return NIP65.RelayList(relays: relayUrls)
        }
        
        // MARK: - Getting metadata from the user's relay list
        
        /// Gets the creation date of the user's current relay list, with preference to NIP-65 relay lists
        /// - Returns: The current relay list's creation date
        private func getUserCurrentRelayListCreationDate() -> UInt32? {
            if let latestNIP65RelayListEvent = self.getLatestNIP65RelayListEvent() { return latestNIP65RelayListEvent.created_at }
            if let latestKind3RelayListEvent = delegate.latestContactListEvent { return latestKind3RelayListEvent.created_at }
            return nil
        }
        
        // MARK: - Listening to and handling relay updates from the network
        
        func connect() {
            self.load()
            
            self.relayListObserverTask?.cancel()
            self.relayListObserverTask = Task { await self.listenAndHandleRelayUpdates() }
            self.walletUpdatesObserverTask?.cancel()
            self.walletUpdatesObserverTask = handle_notify(.attached_wallet).sink { _ in self.load() }
        }
        
        func listenAndHandleRelayUpdates() async {
            let filter = NostrFilter(kinds: [.relay_list], authors: [delegate.keypair.pubkey])
            for await item in self.reader.subscribe(filters: [filter]) {
                switch item {
                case .event(let lender):                                                                // Signature validity already ensured at this point
                    let currentRelayListCreationDate = self.getUserCurrentRelayListCreationDate()
                    try? lender.borrow({ note in
                        guard note.pubkey == self.delegate.keypair.pubkey else { return }               // Ensure this new list was ours
                        guard note.createdAt > (currentRelayListCreationDate ?? 0) else { return }      // Ensure this is a newer list
                        guard let relayList = try? NIP65.RelayList(event: note) else { return }         // Ensure it is a valid NIP-65 list
                        
                        try? self.set(userRelayList: relayList)                                         // Set the validated list
                    })
                case .eose: continue
                }
            }
        }
        
        // MARK: - Editing the user's relay list
    
        func upsert(relay: NIP65.RelayList.RelayItem, force: Bool = false, overwriteExisting: Bool = false) throws(UpdateError) {
            guard let currentUserRelayList = force ? self.getBestEffortRelayList() : self.getUserCurrentRelayList() else { throw .noInitialRelayList }
            guard !currentUserRelayList.relays.keys.contains(relay.url) || overwriteExisting else { throw .relayAlreadyExists }
            var newList = currentUserRelayList.relays
            newList[relay.url] = relay
            try self.set(userRelayList: NIP65.RelayList(relays: Array(newList.values)))
        }
    
        func insert(relay: NIP65.RelayList.RelayItem, force: Bool = false) throws(UpdateError) {
            guard let currentUserRelayList = force ? self.getBestEffortRelayList() : self.getUserCurrentRelayList() else { throw .noInitialRelayList }
            guard currentUserRelayList.relays[relay.url] == nil else { throw .relayAlreadyExists }
            try self.upsert(relay: relay, force: force)
        }
    
        func remove(relayURL: RelayURL, force: Bool = false) throws(UpdateError) {
            guard let currentUserRelayList = force ? self.getBestEffortRelayList() : self.getUserCurrentRelayList() else { throw .noInitialRelayList }
            guard currentUserRelayList.relays.keys.contains(relayURL) || force else { throw .noSuchRelay }
            var newList = currentUserRelayList.relays
            newList[relayURL] = nil
            try self.set(userRelayList: NIP65.RelayList(relays: Array(newList.values)))
        }
    
        func set(userRelayList: NIP65.RelayList) throws(UpdateError) {
            guard let fullKeypair = delegate.keypair.to_full() else { throw .notAuthorizedToChangeRelayList }
            guard let relayListEvent = userRelayList.toNostrEvent(keypair: fullKeypair) else { throw .cannotFormRelayListEvent }
    
            self.apply(newRelayList: self.computeRelaysToConnectTo(with: userRelayList))
    
            self.pool.send(.event(relayListEvent))   // This will send to NostrDB as well, which will locally save that NIP-65 event
            self.delegate.latestRelayListEventIdHex = relayListEvent.id.hex()   // Make sure we are able to recall this event from NostrDB
        }
        
        // MARK: - Syncing our saved user relay list with the active `RelayPool`
        
        /// Loads the current user relay list
        func load() {
            self.apply(newRelayList: self.relaysToConnectTo())
        }
        
        /// Loads a new relay list into the active relay pool, making sure it matches the specified relay list.
        ///
        /// - Parameters:
        ///   - state: The state of the app
        ///   - newRelayList: The new relay list to be applied
        ///
        ///
        /// ## Implementation notes
        ///
        /// - This is `private` because syncing the user's saved relay list with the relay pool is `NostrNetworkManager`'s responsibility,
        ///   so we do not want other classes to forcibly load this.
        private func apply(newRelayList: [RelayPool.RelayDescriptor]) {
            let currentRelayList = self.pool.relays.map({ $0.descriptor })

            var changed = false
            let new_relay_filters = load_relay_filters(delegate.keypair.pubkey) == nil
            
            for index in self.pool.relays.indices {
                guard let newDescriptor = newRelayList.first(where: { $0.url == self.pool.relays[index].descriptor.url }) else { continue }
                self.pool.relays[index].descriptor.info = newDescriptor.info
                // Relay read-write configuration change does not need reconnection to the relay, so we do not set the `changed` flag.
            }
            
            // Working with URL Sets for difference analysis
            let currentRelayURLs = Set(currentRelayList.map { $0.url })
            let newRelayURLs = Set(newRelayList.map { $0.url })
            
            // Analyzing which relays to add or remove
            let relaysToRemove = currentRelayURLs.subtracting(newRelayURLs)
            let relaysToAdd = newRelayURLs.subtracting(currentRelayURLs)
            
            // Remove relays not in the new list
            relaysToRemove.forEach { url in
                pool.remove_relay(url)
                changed = true
            }

            // Add new relays from the new list
            relaysToAdd.forEach { url in
                guard let descriptor = newRelayList.first(where: { $0.url == url }) else { return }
                add_new_relay(
                    model_cache: delegate.relayModelCache,
                    relay_filters: delegate.relayFilters,
                    pool: pool,
                    descriptor: descriptor,
                    new_relay_filters: new_relay_filters,
                    logging_enabled: delegate.developerMode
                )
                changed = true
            }

            if changed {
                pool.connect()
                notify(.relays_changed)
            }
        }
    }
}

// MARK: - Helper extensions

fileprivate extension NIP65.RelayList.RelayItem {
    func toRelayDescriptor() -> RelayPool.RelayDescriptor {
        return RelayPool.RelayDescriptor(url: self.url, info: self.rwConfiguration, variant: .regular)  // NIP-65 relays are regular by definition.
    }
}

fileprivate extension NIP65.RelayList {
    func toRelayDescriptors() -> [RelayPool.RelayDescriptor] {
        return self.relays.values.map({ $0.toRelayDescriptor() })
    }
}

// MARK: - Helper functions


/// Adds a new relay, taking care of other tangential concerns, such as updating the relay model cache, configuring logging, etc
///
/// ## Implementation notes
///
/// 1. This function used to be in `HomeModel.swift` and moved here when `UserRelayListManager` was first implemented
/// 2. This is `fileprivate` because only `UserRelayListManager` should be able to manage the user's relay list and apply them to the `RelayPool`
///
/// - Parameters:
///   - model_cache: The relay model cache, that keeps metadata cached
///   - relay_filters: Relay filters
///   - pool: The relay pool to add this in
///   - descriptor: The description of the relay being added
///   - new_relay_filters: Whether to insert new relay filters
///   - logging_enabled: Whether logging is enabled
fileprivate func add_new_relay(model_cache: RelayModelCache, relay_filters: RelayFilters, pool: RelayPool, descriptor: RelayPool.RelayDescriptor, new_relay_filters: Bool, logging_enabled: Bool) {
    try? pool.add_relay(descriptor)
    let url = descriptor.url

    let relay_id = url
    guard model_cache.model(withURL: url) == nil else {
        return
    }
    
    Task.detached(priority: .background) {
        guard let meta = try? await fetch_relay_metadata(relay_id: relay_id) else {
            return
        }
        
        await MainActor.run {
            let model = RelayModel(url, metadata: meta)
            model_cache.insert(model: model)
            
            if logging_enabled {
                pool.setLog(model.log, for: relay_id)
            }
            
            // if this is the first time adding filters, we should filter non-paid relays
            if new_relay_filters && !meta.is_paid {
                relay_filters.insert(timeline: .search, relay_id: relay_id)
            }
        }
    }
}
