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

        /// In-memory cache of the most recently set relay list.
        /// Bridges the gap between sending an event to nostrdb (async write) and it being queryable.
        @MainActor
        private var lastSetRelayList: NIP65.RelayList?

        /// In-memory cache of the DM inbox relay list we most recently published.
        /// Same purpose as `lastSetRelayList`: nostrdb's write is async, so without this a read taken
        /// right after publishing would still say we have no list and publish a second one.
        @MainActor
        private var lastSetDMInboxRelayList: NIP17.DMRelayList?

        private var dmInboxRelayListPublishTask: Task<Void, Never>? = nil
        
        init(delegate: Delegate, pool: RelayPool, reader: SubscriptionManager) {
            self.delegate = delegate
            self.pool = pool
            self.reader = reader
        }
        
        // MARK: - Computing the relays to connect to
        
        @MainActor
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
        @MainActor
        func getBestEffortRelayList() -> NIP65.RelayList {
            guard let userCurrentRelayList = self.getUserCurrentRelayList() else {
                return NIP65.RelayList(relays: delegate.bootstrapRelays)
            }
            return userCurrentRelayList
        }
        
        /// Gets the user's current relay list.
        ///
        /// It attempts to get the in-memory cache first (to bridge the nostrdb async write gap),
        /// then a NIP-65 relay list from the local database, or falls back to a legacy list.
        @MainActor
        func getUserCurrentRelayList() -> NIP65.RelayList? {
            if let lastSetRelayList { return lastSetRelayList }
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
        
        /// Gets the latest NIP-65 relay list event from NostrDB via query.
        ///
        /// This is `private` because it is part of internal logic. Callers should use the higher level functions.
        ///
        /// It is recommended to use this function only if the NostrEvent metadata is needed. For cases where only the relay list info is needed, use `getLatestNIP65RelayList` instead.
        ///
        /// - Returns: The latest NIP-65 relay list NdbNote
        private func getLatestNIP65RelayListEvent() -> NdbNote? {
            let filter = NostrFilter(kinds: [.relay_list], limit: 1, authors: [delegate.keypair.pubkey])
            guard let ndbFilter = try? NdbFilter(from: filter) else { return nil }
            guard let noteKey = try? delegate.ndb.query(filters: [ndbFilter], maxResults: 1).first else { return nil }
            return try? delegate.ndb.lookup_note_by_key_and_copy(noteKey)
        }
        
        /// Gets the latest `kind:3` relay list from NostrDB.
        ///
        /// This is `private` because it is part of internal logic. Callers should use the higher level functions.
        @MainActor
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
        @MainActor
        private func getUserCurrentRelayListCreationDate() -> UInt32? {
            if let latestNIP65RelayListEvent = self.getLatestNIP65RelayListEvent() { return latestNIP65RelayListEvent.created_at }
            if let latestKind3RelayListEvent = delegate.latestContactListEvent { return latestKind3RelayListEvent.created_at }
            return nil
        }
        
        // MARK: - Listening to and handling relay updates from the network
        
        func connect() async {
            await self.load()
            
            self.relayListObserverTask?.cancel()
            self.relayListObserverTask = Task { await self.listenAndHandleRelayUpdates() }
            self.walletUpdatesObserverTask?.cancel()
            self.walletUpdatesObserverTask = handle_notify(.attached_wallet).sink { _ in Task { await self.load() } }

            // Detached, because this waits on the network to tell us whether we already have a DM
            // inbox list before it publishes one, and nothing else about connecting should block on
            // that answer.
            self.dmInboxRelayListPublishTask?.cancel()
            self.dmInboxRelayListPublishTask = Task { await self.publishOurDMInboxRelayListIfMissing() }
        }
        
        func listenAndHandleRelayUpdates() async {
            let filter = NostrFilter(kinds: [.relay_list], authors: [delegate.keypair.pubkey])
            for await noteLender in self.reader.streamIndefinitely(filters: [filter]) {
                let currentRelayListCreationDate = await self.getUserCurrentRelayListCreationDate()
                guard let note = noteLender.justGetACopy() else { continue }
                guard note.pubkey == self.delegate.keypair.pubkey else { continue }               // Ensure this new list was ours
                guard note.created_at > (currentRelayListCreationDate ?? 0) else { continue }     // Ensure this is a newer list
                guard let relayList = try? NIP65.RelayList(event: note) else { continue }         // Ensure it is a valid NIP-65 list
                
                try? await self.set(userRelayList: relayList)                                     // Set the validated list
            }
        }
        
        // MARK: - Editing the user's relay list
    
        func upsert(relay: NIP65.RelayList.RelayItem, force: Bool = false, overwriteExisting: Bool = false) async throws(UpdateError) {
            guard let currentUserRelayList = await force ? self.getBestEffortRelayList() : self.getUserCurrentRelayList() else { throw .noInitialRelayList }
            guard !currentUserRelayList.relays.keys.contains(relay.url) || overwriteExisting else { throw .relayAlreadyExists }
            var newList = currentUserRelayList.relays
            newList[relay.url] = relay
            try await self.set(userRelayList: NIP65.RelayList(relays: Array(newList.values)))
        }
    
        func insert(relay: NIP65.RelayList.RelayItem, force: Bool = false) async throws(UpdateError) {
            guard let currentUserRelayList = await force ? self.getBestEffortRelayList() : self.getUserCurrentRelayList() else { throw .noInitialRelayList }
            guard currentUserRelayList.relays[relay.url] == nil else { throw .relayAlreadyExists }
            try await self.upsert(relay: relay, force: force)
        }
    
        func remove(relayURL: RelayURL, force: Bool = false) async throws(UpdateError) {
            guard let currentUserRelayList = await force ? self.getBestEffortRelayList() : self.getUserCurrentRelayList() else { throw .noInitialRelayList }
            guard currentUserRelayList.relays.keys.contains(relayURL) || force else { throw .noSuchRelay }
            var newList = currentUserRelayList.relays
            newList[relayURL] = nil
            try await self.set(userRelayList: NIP65.RelayList(relays: Array(newList.values)))
        }
    
        func set(userRelayList: NIP65.RelayList) async throws(UpdateError) {
            guard let fullKeypair = delegate.keypair.to_full() else { throw .notAuthorizedToChangeRelayList }
            guard let relayListEvent = userRelayList.toNostrEvent(keypair: fullKeypair) else { throw .cannotFormRelayListEvent }

            await MainActor.run { self.lastSetRelayList = userRelayList }

            await self.apply(newRelayList: self.computeRelaysToConnectTo(with: userRelayList))

            await self.pool.send(.event(relayListEvent))   // This will send to NostrDB as well, which will locally save that NIP-65 event
        }
        
        // MARK: - DM inbox relay lists (NIP-17, kind 10050)
        //
        // A NIP-17 giftwrap has to reach the relays its recipient actually reads DMs from, which is
        // what kind 10050 declares. This is a separate list from the NIP-65 one above and is handled
        // separately on purpose: NIP-65 says where someone's public notes flow, kind 10050 says the
        // one place a private message can be delivered to them at all. Publishing a wrap to our own
        // write relays instead is valid but, for anyone whose inbox relays we are not on, invisible.

        /// Gets the latest kind-10050 DM inbox relay list event for a user, from the local database only.
        ///
        /// This is `private` because it is part of internal logic. Callers should use the higher level functions.
        private func getLatestDMInboxRelayListEvent(for pubkey: Pubkey) -> NdbNote? {
            let filter = NostrFilter(kinds: [.dm_relay_list], limit: 1, authors: [pubkey])
            guard let ndbFilter = try? NdbFilter(from: filter) else { return nil }
            guard let noteKey = try? delegate.ndb.query(filters: [ndbFilter], maxResults: 1).first else { return nil }
            return try? delegate.ndb.lookup_note_by_key_and_copy(noteKey)
        }

        /// Gets a user's DM inbox relay list from the local database.
        ///
        /// - Returns: the user's list, or `nil` if we have not seen a kind-10050 event from them. An
        ///   empty list is *not* the same as `nil`: it means they published one saying they have no
        ///   inbox, which is a statement, whereas `nil` only means we have not looked hard enough yet.
        @MainActor
        func getDMInboxRelayList(for pubkey: Pubkey) -> NIP17.DMRelayList? {
            if pubkey == delegate.keypair.pubkey, let lastSetDMInboxRelayList { return lastSetDMInboxRelayList }
            guard let event = self.getLatestDMInboxRelayListEvent(for: pubkey) else { return nil }
            return try? NIP17.DMRelayList(event: event)
        }

        /// Gets a user's DM inbox relays, going to the network if the local database has nothing for them.
        ///
        /// The network step is bounded and best effort. Coming back with `nil` is a normal outcome —
        /// most people have no kind-10050 yet — and callers are expected to fall back to our own write
        /// relays rather than refuse to send.
        ///
        /// - Parameters:
        ///   - pubkey: whose inbox to look up
        ///   - timeout: how long to give the network before giving up
        /// - Returns: their inbox relays, or `nil` if they have no published list
        func fetchDMInboxRelays(for pubkey: Pubkey, timeout: Duration = .seconds(5)) async -> [RelayURL]? {
            if let local = await self.getDMInboxRelayList(for: pubkey) { return local.relays }

            let filter = NostrFilter(kinds: [.dm_relay_list], limit: 1, authors: [pubkey])
            let events = await self.reader.query(filters: [filter], timeout: timeout)
            // A kind-10050 is replaceable, so several relays may hand us different revisions of it.
            // Take the newest rather than whichever answered first.
            guard let newest = events.max(by: { $0.created_at < $1.created_at }) else { return nil }
            guard let list = try? NIP17.DMRelayList(event: newest) else { return nil }
            return list.relays
        }

        /// The DM inbox relay list we have actually published for ourselves, if any.
        ///
        /// Deliberately *not* best-effort, and deliberately not the default we would publish. A relay
        /// set we merely guessed at is not something to narrow a subscription to: guessing wrong there
        /// does not degrade delivery, it silently stops us pulling our own DMs. Callers treat `nil` as
        /// "no opinion" and keep using every relay they have.
        @MainActor
        func ourPublishedDMInboxRelays() -> [RelayURL]? {
            guard let ours = self.getDMInboxRelayList(for: delegate.keypair.pubkey), !ours.relays.isEmpty else { return nil }
            return ours.relays
        }

        /// The inbox relays we would publish for ourselves if we have not published a list yet.
        ///
        /// Our read/write relays, because a DM inbox has to work in both directions from where we
        /// stand: other people write giftwraps into it, we read them back out, and our own copy of
        /// every message we send is published there too. A relay we marked read-only would silently
        /// swallow that last part, so prefer relays that are both, and only widen the net if there
        /// are none.
        ///
        /// Returns `nil` when the user has no relay list of their own yet. `getBestEffortRelayList()`
        /// would happily hand back the bootstrap list here, and publishing *that* as our DM inbox
        /// would be durable and wrong: every sender would then be told to deliver our private messages
        /// to a set of default relays the user may never read, and we would key our own giftwrap
        /// subscription off the same mistake. A missing list is a reason to wait, not to guess.
        @MainActor
        private func defaultDMInboxRelays() -> [RelayURL]? {
            guard let relayList = self.getUserCurrentRelayList() else { return nil }
            let readWrite = relayList.relays.values.filter({ $0.rwConfiguration.canRead && $0.rwConfiguration.canWrite })
            if !readWrite.isEmpty { return readWrite.map({ $0.url }) }
            let readable = relayList.relays.values.filter({ $0.rwConfiguration.canRead }).map({ $0.url })
            return readable.isEmpty ? nil : readable
        }

        /// Our own DM inbox relays for *sending* our own copy of a message: what we published, else
        /// the default we would publish, else `nil` to mean "use our write relays".
        @MainActor
        func ourBestEffortDMInboxRelays() -> [RelayURL]? {
            return self.ourPublishedDMInboxRelays() ?? self.defaultDMInboxRelays()
        }

        /// Publishes a kind-10050 DM inbox relay list for us, but only if we do not already have one.
        ///
        /// Deliberately never overwrites. A user may have set a deliberately small, private inbox from
        /// another client, and replacing that with "all our write relays" would quietly widen who can
        /// see that they received a message — the one thing the list exists to control. So we only
        /// ever fill in the gap, and we ask the network before deciding the gap is real, because at
        /// startup the local database has not necessarily caught up with our own published events yet.
        func publishOurDMInboxRelayListIfMissing() async {
            guard let fullKeypair = delegate.keypair.to_full() else { return }   // Pubkey-only logins cannot publish
            if let existing = await self.fetchDMInboxRelays(for: fullKeypair.pubkey, timeout: .seconds(10)), !existing.isEmpty {
                return
            }

            // Nothing worth advertising yet — most likely the user's own relay list has not loaded, and
            // the bootstrap defaults are not an inbox anyone chose. Try again on the next connect.
            guard let relays = await self.defaultDMInboxRelays(), !relays.isEmpty else { return }

            let list = NIP17.DMRelayList(relays: relays)
            guard let event = list.toNostrEvent(keypair: fullKeypair) else {
                Log.error("Failed to build our NIP-17 DM inbox relay list event", for: .networking)
                return
            }

            await MainActor.run { self.lastSetDMInboxRelayList = list }
            await self.pool.send(.event(event))  // Also writes a local copy into nostrdb
        }

        /// Makes sure we are connected to our own DM inbox relays, and reports the relays a giftwrap
        /// subscription should run on.
        ///
        /// The job here is to *add* our inbox relays to what we already listen to, never to subtract.
        /// Our own DMs are the one thing we cannot re-fetch from somewhere else later, so the target
        /// is the union of our inbox relays and every relay we normally use — and it is empty, meaning
        /// "no opinion, use them all", whenever we have not published a list of our own.
        ///
        /// Narrowing to just the inbox list would be the tidier reading of NIP-17, but it makes the
        /// subscription hostage to two things that are wrong often enough to matter: a relay set
        /// computed once, from whichever connections happened to be up at that moment, and a published
        /// list that may be stale or may have been written by a client with a different idea of our
        /// relays. Neither is worth losing a conversation over.
        ///
        /// Connections made here are ephemeral and leased, so they do not show up in the user's relay
        /// settings as relays they never added. The caller owns the lease and must hand the returned
        /// `leased` list back to ``releaseDMInboxRelays(_:)`` when it stops listening.
        ///
        /// - Returns: `leased`, every relay we took a lease on, and `target`, the relays to subscribe
        ///   on — empty meaning "every relay".
        func leaseOurDMInboxRelays() async -> (leased: [RelayURL], target: [RelayURL]) {
            guard let inboxRelays = await self.ourPublishedDMInboxRelays(), !inboxRelays.isEmpty else {
                return (leased: [], target: [])
            }
            await self.pool.acquireEphemeralRelays(inboxRelays)
            let connected = await self.pool.ensureConnected(to: inboxRelays)
            let ourUsualRelays = await self.pool.our_descriptors.map({ $0.url })

            var seen: Set<RelayURL> = []
            let target = (connected + ourUsualRelays).filter({ seen.insert($0).inserted })
            return (leased: inboxRelays, target: target)
        }

        /// Releases the leases taken by ``leaseOurDMInboxRelays()``.
        func releaseDMInboxRelays(_ relays: [RelayURL]) async {
            guard !relays.isEmpty else { return }
            await self.pool.releaseEphemeralRelays(relays)
        }

        // MARK: - Syncing our saved user relay list with the active `RelayPool`
        
        /// Loads the current user relay list
        func load() async {
            await MainActor.run { self.lastSetRelayList = nil }  // Clear cache; ndb has had time to commit by now
            await self.apply(newRelayList: self.relaysToConnectTo())
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
        @MainActor
        private func apply(newRelayList: [RelayPool.RelayDescriptor]) async {
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
            
            await withTaskGroup { taskGroup in
                // Remove relays not in the new list
                relaysToRemove.forEach { url in
                    taskGroup.addTask(operation: { await self.pool.remove_relay(url) })
                    changed = true
                }

                // Add new relays from the new list
                relaysToAdd.forEach { url in
                    guard let descriptor = newRelayList.first(where: { $0.url == url }) else { return }
                    taskGroup.addTask(operation: {
                        await add_new_relay(
                            model_cache: self.delegate.relayModelCache,
                            relay_filters: self.delegate.relayFilters,
                            pool: self.pool,
                            descriptor: descriptor,
                            new_relay_filters: new_relay_filters,
                            logging_enabled: self.delegate.developerMode
                        )
                    })
                    changed = true
                }
                
                for await value in taskGroup { continue }
            }
            
            // Always tell RelayPool to connect whether or not we are already connected.
            // This is because:
            // 1. Internally it won't redo the connection because of internal checks
            // 2. Even if the relay list has not changed, relays may have been disconnected from app lifecycle or other events
            await pool.connect()

            if changed {
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
fileprivate func add_new_relay(model_cache: RelayModelCache, relay_filters: RelayFilters, pool: RelayPool, descriptor: RelayPool.RelayDescriptor, new_relay_filters: Bool, logging_enabled: Bool) async {
    try? await pool.add_relay(descriptor)
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
                Task { await pool.setLog(model.log, for: relay_id) }
            }
            
            // if this is the first time adding filters, we should filter non-paid relays
            if new_relay_filters && !meta.is_paid {
                relay_filters.insert(timeline: .search, relay_id: relay_id)
            }
        }
    }
}
