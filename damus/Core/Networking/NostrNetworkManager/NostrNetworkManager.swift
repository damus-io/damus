//
//  NostrNetworkManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-26.
//
import Foundation

/// Manages interactions with the Nostr Network.
///
/// This delineates a layer that is responsible for doing mid-level management of interactions with the Nostr network, controlling lower-level classes that perform more network/DB specific code, and providing an easier to use and more semantic interfaces for the rest of the app.
///
/// This is responsible for:
/// - Managing the user's relay list
/// - Establishing a `RelayPool` and maintaining it in sync with the user's relay list as it changes
/// - Abstracting away complexities of interacting with the nostr network, providing an easier-to-use interface to fetch and send content related to the Nostr network
///
/// This is **NOT** responsible for:
/// - Doing actual storage of relay list (delegated via the delegate
/// - Handling low-level relay logic (this will be delegated to lower level classes used in RelayPool/RelayConnection)
class NostrNetworkManager {
    /// The relay pool that we manage
    ///
    /// ## Implementation notes
    ///
    /// - This will be marked `private` in the future to prevent other code from accessing the relay pool directly. Code outside this layer should use a higher level interface
    private let pool: RelayPool // TODO: Make this private and make higher level interface for classes outside the NostrNetworkManager
    /// A delegate that allows us to interact with the rest of app without introducing hard or circular dependencies
    private var delegate: Delegate
    /// Manages the user's relay list, controls RelayPool's connected relays
    let userRelayList: UserRelayListManager
    /// Handles sending out notes to the network
    let postbox: PostBox
    /// Handles subscriptions and functions to read or consume data from the Nostr network
    let reader: SubscriptionManager
    let profilesManager: ProfilesManager
    
    init(delegate: Delegate, addNdbToRelayPool: Bool = true) {
        self.delegate = delegate
        let pool = RelayPool(ndb: addNdbToRelayPool ? delegate.ndb : nil, keypair: delegate.keypair)
        self.pool = pool
        let reader = SubscriptionManager(pool: pool, ndb: delegate.ndb, experimentalLocalRelayModelSupport: self.delegate.experimentalLocalRelayModelSupport)
        let userRelayList = UserRelayListManager(delegate: delegate, pool: pool, reader: reader)
        self.reader = reader
        self.userRelayList = userRelayList
        self.postbox = PostBox(pool: pool)
        self.profilesManager = ProfilesManager(subscriptionManager: reader, ndb: delegate.ndb)
    }
    
    // MARK: - Control and lifecycle functions
    
    /// Connects the app to the Nostr network
    func connect() async {
        await self.userRelayList.connect()    // Will load the user's list, apply it, and get RelayPool to connect to it.
        await self.profilesManager.load()
    }
    
    func disconnectRelays() async {
        await self.pool.disconnect()
    }
    
    func handleAppBackgroundRequest() async {
        await self.reader.cancelAllTasks()
        await self.pool.cleanQueuedRequestForSessionEnd()
    }
    
    func close() async {
        await withTaskGroup { group in
            // Spawn each cancellation task in parallel for faster execution speed
            group.addTask {
                await self.reader.cancelAllTasks()
            }
            group.addTask {
                await self.profilesManager.stop()
            }
            // But await on each one to prevent race conditions
            for await value in group { continue }
            await pool.close()
        }
    }
    
    func ping() async {
        await self.pool.ping()
    }

    @MainActor
    func relaysForEvent(event: NostrEvent) async -> [RelayURL] {
        // TODO(tyiu) Ideally this list would be sorted by the event author's outbox relay preferences
        // and reliability of relays to maximize chances of others finding this event.
        if let relays = await pool.seen[event.id] {
            return Array(relays)
        }

        return []
    }
    
    // TODO: ORGANIZE THESE
    
    // MARK: - Communication with the Nostr Network
    /// ## Implementation notes
    ///
    /// - This class hides the relay pool on purpose to avoid other code from dealing with complex relay + nostrDB logic.
    /// - Instead, we provide an easy to use interface so that normal code can just get the info they want.
    /// - This is also to help us migrate to the relay model.
    // TODO: Define a better interface. This is a temporary scaffold to replace direct relay pool access. After that is done, we can refactor this interface to be cleaner and reduce non-sense.
    
    func sendToNostrDB(event: NostrEvent) async {
        await self.pool.send_raw_to_local_ndb(.typical(.event(event)))
    }
    
    func send(event: NostrEvent, to targetRelays: [RelayURL]? = nil, skipEphemeralRelays: Bool = true) async {
        await self.pool.send(.event(event), to: targetRelays, skip_ephemeral: skipEphemeralRelays)
    }
    
    @MainActor
    func getRelay(_ id: RelayURL) -> RelayPool.Relay? {
        pool.get_relay(id)
    }
    
    @MainActor
    var connectedRelays: [RelayPool.Relay] {
        self.pool.relays
    }
    
    @MainActor
    var ourRelayDescriptors: [RelayPool.RelayDescriptor] {
        self.pool.our_descriptors
    }
    
    @MainActor
    func relayURLsThatSawNote(id: NoteId) async -> Set<RelayURL>? {
        return await self.pool.seen[id]
    }
    
    @MainActor
    func determineToRelays(filters: RelayFilters) -> [RelayURL] {
        return self.pool.our_descriptors
            .map { $0.url }
            .filter { !filters.is_filtered(timeline: .search, relay_id: $0) }
    }
    
    /// Ensures the relay pool is connected to a specific relay, adding it if necessary. Useful for feature-specific relays (e.g., Vine POC).
    func ensureRelayConnected(_ relayURL: RelayURL) async {
        if await pool.get_relay(relayURL) != nil {
            return
        }
        
        let descriptor = RelayPool.RelayDescriptor(url: relayURL, info: .readWrite)
        try? await pool.add_relay(descriptor)
        await pool.connect(to: [relayURL])
    }
    
    /// Disconnects and removes a relay from the pool if we previously added it.
    func disconnectRelay(_ relayURL: RelayURL) async {
        guard await pool.get_relay(relayURL) != nil else {
            return
        }
        
        await pool.remove_relay(relayURL)
    }
    
    // MARK: NWC
    // TODO: Move this to NWCManager
    
    @discardableResult
    func nwcPay(url: WalletConnectURL, post: PostBox, invoice: String, delay: TimeInterval? = 5.0, on_flush: OnFlush? = nil, zap_request: NostrEvent? = nil) async -> NostrEvent? {
        await WalletConnect.pay(url: url, pool: self.pool, post: post, invoice: invoice, zap_request: nil)
    }
    
    /// Send a donation zap to the Damus team
    func send_donation_zap(nwc: WalletConnectURL, percent: Int, base_msats: Int64) async {
        let percent_f = Double(percent) / 100.0
        let donations_msats = Int64(percent_f * Double(base_msats))
        
        let payreq = LNUrlPayRequest(allowsNostr: true, commentAllowed: nil, nostrPubkey: "", callback: "https://sendsats.lol/@damus")
        guard let invoice = await fetch_zap_invoice(payreq, zapreq: nil, msats: donations_msats, zap_type: .non_zap, comment: nil) else {
            // we failed... oh well. no donation for us.
            print("damus-donation failed to fetch invoice")
            return
        }
        
        print("damus-donation donating...")
        await WalletConnect.pay(url: nwc, pool: self.pool, post: self.postbox, invoice: invoice, zap_request: nil, delay: nil)
    }
}


// MARK: - Helper types

extension NostrNetworkManager {
    /// The delegate that provides information and structure for the `NostrNetworkManager` to function.
    ///
    /// ## Implementation notes
    ///
    /// This is needed to prevent a circular reference between `DamusState` and `NostrNetworkManager`, and reduce coupling.
    protocol Delegate: Sendable {
        /// NostrDB instance, used with `RelayPool` to send events for ingestion.
        var ndb: Ndb { get }
        
        /// The keypair to use for relay authentication and updating relay lists
        var keypair: Keypair { get }
        
        /// The latest relay list event id hex
        var latestRelayListEventIdHex: String? { get set }  // TODO: Update this once we have full NostrDB query support
        
        /// The latest contact list `NostrEvent`
        ///
        /// Note: Read-only access, because `NostrNetworkManager` does not manage contact lists.
        var latestContactListEvent: NostrEvent? { get }
        
        /// Default bootstrap relays to start with when a user relay list is not present
        var bootstrapRelays: [RelayURL] { get }
        
        /// Whether the app is in developer mode
        var developerMode: Bool { get }
        
        /// Whether the app has the experimental local relay model flag that streams data only from the local relay (ndb)
        var experimentalLocalRelayModelSupport: Bool { get }
        
        /// The cache of relay model information
        var relayModelCache: RelayModelCache { get }
        
        /// Relay filters
        var relayFilters: RelayFilters { get }
        
        /// The user's connected NWC wallet
        var nwcWallet: WalletConnectURL? { get }
    }
}
