//
//  BlossomServerListManager.swift
//  damus
//
//  Created by Claude on 2025-01-15.
//
//  Manages user's Blossom server list (kind 10063).
//
//  Follows the pattern of UserRelayListManager for handling
//  replaceable events - fetches from relays, stores locally,
//  and publishes updates.
//

import Foundation

// MARK: - Blossom Server List Manager

/// Manages fetching, storing, and publishing a user's Blossom server list.
///
/// This class handles:
/// - Loading the latest server list from NostrDB
/// - Publishing new server lists to relays
/// - Adding/removing individual servers
///
/// Usage:
/// ```swift
/// let manager = BlossomServerListManager(delegate: delegate, pool: pool)
/// if let list = manager.getLatestServerList() {
///     print("Primary server: \(list.primaryServer?.absoluteString ?? "none")")
/// }
/// ```
class BlossomServerListManager {

    // MARK: - Delegate Protocol

    /// Protocol for accessing app state needed by the manager.
    ///
    /// This follows the UserRelayListManager.Delegate pattern to avoid
    /// circular dependencies with DamusState.
    protocol Delegate: AnyObject {
        var keypair: Keypair { get }
        var ndb: Ndb { get }
        var settings: UserSettingsStore { get }
    }

    // MARK: - Properties

    private weak var delegate: Delegate?
    private let pool: RelayPool

    // MARK: - Initialization

    init(delegate: Delegate, pool: RelayPool) {
        self.delegate = delegate
        self.pool = pool
    }

    // MARK: - Reading Server List

    /// Gets the latest server list from local storage.
    ///
    /// First checks for a manually configured server URL in settings,
    /// then falls back to the kind 10063 event stored in NostrDB.
    ///
    /// - Returns: The server list, or nil if none configured
    func getLatestServerList() -> BlossomServerList? {
        guard let delegate = delegate else { return nil }

        // First, check for manually configured server (primary method for v1)
        if let manualURL = delegate.settings.manualBlossomServerUrl,
           !manualURL.isEmpty,
           let serverURL = BlossomServerURL(manualURL) {
            return BlossomServerList(servers: [serverURL])
        }

        // Fall back to kind 10063 event from NostrDB
        guard let eventIdHex = delegate.settings.latestBlossomServerListEventIdHex,
              let eventId = NoteId(hex: eventIdHex) else {
            return nil
        }

        // Look up the event in NostrDB
        guard let note = delegate.ndb.lookup_note_and_copy(eventId) else {
            return nil
        }

        return try? BlossomServerList(note: note)
    }

    /// Gets the preferred upload server.
    ///
    /// Returns the first server from the list, or nil if no servers configured.
    func getPreferredServer() -> BlossomServerURL? {
        return getLatestServerList()?.primaryServer
    }

    // MARK: - Writing Server List

    /// Sets the server list and publishes to relays.
    ///
    /// Creates a new kind 10063 event and sends it to all connected relays.
    /// Also stores the event ID for future local lookups.
    ///
    /// - Parameter serverList: The new server list to publish
    /// - Throws: If publishing fails
    @MainActor
    func setServerList(_ serverList: BlossomServerList) async throws {
        guard let delegate = delegate else {
            throw BlossomServerListManagerError.notInitialized
        }

        // Need full keypair to sign
        guard let fullKeypair = delegate.keypair.to_full() else {
            throw BlossomServerListManagerError.noPrivateKey
        }

        // Create the kind 10063 event
        guard let event = serverList.toNostrEvent(keypair: fullKeypair) else {
            throw BlossomServerListManagerError.eventCreationFailed
        }

        // Send to all relays
        await pool.send(.event(event))

        // Store the event ID for local lookup
        // Note: The actual event will be stored in NostrDB when we receive it back
        delegate.settings.latestBlossomServerListEventIdHex = event.id.hex()
    }

    /// Sets a single manual server URL.
    ///
    /// This is the primary method for v1 - stores the URL in settings
    /// without publishing a kind 10063 event.
    ///
    /// - Parameter url: The server URL to set, or nil to clear
    @MainActor
    func setManualServer(_ url: BlossomServerURL?) {
        guard let delegate = delegate else { return }
        delegate.settings.manualBlossomServerUrl = url?.absoluteString
    }

    /// Clears the manual server URL.
    @MainActor
    func clearManualServer() {
        setManualServer(nil)
    }

    // MARK: - Convenience Methods

    /// Adds a server to the list and publishes.
    ///
    /// - Parameter server: The server to add
    /// - Throws: If publishing fails
    @MainActor
    func addServer(_ server: BlossomServerURL) async throws {
        let currentList = getLatestServerList() ?? BlossomServerList()
        let newList = currentList.adding(server)
        try await setServerList(newList)
    }

    /// Removes a server from the list and publishes.
    ///
    /// - Parameter server: The server to remove
    /// - Throws: If publishing fails
    @MainActor
    func removeServer(_ server: BlossomServerURL) async throws {
        guard let currentList = getLatestServerList() else { return }
        let newList = currentList.removing(server)
        try await setServerList(newList)
    }

    /// Checks if a server is in the current list.
    func containsServer(_ server: BlossomServerURL) -> Bool {
        return getLatestServerList()?.servers.contains(server) ?? false
    }
}

// MARK: - Errors

/// Errors from BlossomServerListManager operations.
enum BlossomServerListManagerError: Error, LocalizedError {
    /// Manager delegate is nil (not properly initialized)
    case notInitialized

    /// User doesn't have a private key (read-only mode)
    case noPrivateKey

    /// Failed to create the nostr event
    case eventCreationFailed

    /// Failed to publish to relays
    case publishFailed

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Server list manager not initialized"
        case .noPrivateKey:
            return "Cannot publish without private key"
        case .eventCreationFailed:
            return "Failed to create server list event"
        case .publishFailed:
            return "Failed to publish server list"
        }
    }
}
