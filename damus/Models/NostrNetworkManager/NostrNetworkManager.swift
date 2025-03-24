//
//  NostrNetworkManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-26.
//
import Foundation

/// Manages interactions with the Nostr Network.
///  
/// This is responsible for:
/// - Managing the user's relay list
/// - Establishing a `RelayPool` and maintaining it in sync with the user's relay list as it changes
/// - Abstracting away complexities of interacting with the nostr network, providing an easier-to-use interface to fetch and send content related to the Nostr network
///
/// This is **NOT** responsible for:
/// - Doing actual storage of relay list
/// - Handling low-level relay logic
class NostrNetworkManager {
    /// The relay pool that we manage
    ///
    /// ## Implementation notes
    ///
    /// - This will be marked `private` in the future to prevent other code from accessing the relay pool directly. Other code should go through this class' interface
    let pool: RelayPool // TODO: Make this private and make higher level interface for classes outside the NostrNetworkManager
    private var delegate: Delegate
    let userRelayList: UserRelayListManager
    let postbox: PostBox
    
    init(delegate: Delegate) {
        self.delegate = delegate
        let pool = RelayPool(ndb: delegate.ndb, keypair: delegate.keypair)
        self.pool = pool
        let userRelayList = UserRelayListManager(delegate: delegate, pool: pool)
        self.userRelayList = userRelayList
        self.postbox = PostBox(pool: pool)
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
