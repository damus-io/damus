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
    let pool: RelayPool // TODO: Make this private and make higher level interface for classes outside the NostrNetworkManager
    /// A delegate that allows us to interact with the rest of app without introducing hard or circular dependencies
    private var delegate: Delegate
    /// Manages the user's relay list, controls RelayPool's connected relays
    let userRelayList: UserRelayListManager
    /// Handles sending out notes to the network
    let postbox: PostBox
    /// Handles subscriptions and functions to read or consume data from the Nostr network
    let reader: SubscriptionManager
    
    init(delegate: Delegate) {
        self.delegate = delegate
        let pool = RelayPool(ndb: delegate.ndb, keypair: delegate.keypair)
        self.pool = pool
        let reader = SubscriptionManager(pool: pool, ndb: delegate.ndb)
        let userRelayList = UserRelayListManager(delegate: delegate, pool: pool, reader: reader)
        self.reader = reader
        self.userRelayList = userRelayList
        self.postbox = PostBox(pool: pool)
    }
    
    // MARK: - Control functions
    
    /// Connects the app to the Nostr network
    func connect() {
        self.userRelayList.connect()
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
        
        /// The cache of relay model information
        var relayModelCache: RelayModelCache { get }
        
        /// Relay filters
        var relayFilters: RelayFilters { get }
        
        /// The user's connected NWC wallet
        var nwcWallet: WalletConnectURL? { get }
    }
}
