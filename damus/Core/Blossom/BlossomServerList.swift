//
//  BlossomServerList.swift
//  damus
//
//  Created by Claude on 2025-01-15.
//
//  Models kind 10063 user server list events (BUD-03).
//
//  Users publish kind 10063 replaceable events to advertise their
//  preferred Blossom servers. The event contains ["server", url] tags
//  ordered by preference (most reliable/trusted first).
//
//  Example event:
//  {
//    "kind": 10063,
//    "content": "",
//    "tags": [
//      ["server", "https://cdn.self.hosted"],
//      ["server", "https://cdn.satellite.earth"]
//    ]
//  }
//

import Foundation

// MARK: - Blossom Server List

/// Represents a user's list of preferred Blossom servers (kind 10063).
///
/// This is a replaceable event - publishing a new one replaces the old one.
/// Servers are ordered by preference, with most trusted/reliable first.
struct BlossomServerList: Sendable {
    /// Ordered list of server URLs (first = most preferred)
    let servers: [BlossomServerURL]

    /// The event ID of the source event (if parsed from an event)
    let eventId: NoteId?

    /// Timestamp of when this list was created/updated
    let createdAt: UInt32?

    // MARK: - Initialization

    /// Creates an empty server list.
    init() {
        self.servers = []
        self.eventId = nil
        self.createdAt = nil
    }

    /// Creates a server list with the given servers.
    init(servers: [BlossomServerURL]) {
        self.servers = servers
        self.eventId = nil
        self.createdAt = nil
    }

    /// Parses a server list from a kind 10063 nostr event.
    ///
    /// - Parameter event: The nostr event to parse
    /// - Throws: `BlossomServerListError` if the event is invalid
    ///
    /// Per BUD-03, the event must:
    /// - Be kind 10063
    /// - Have at least one ["server", url] tag
    /// - Server URLs must be valid (http/https with host)
    init(event: NostrEvent) throws {
        // Validate event kind
        guard event.kind == NostrKind.blossom_server_list.rawValue else {
            throw BlossomServerListError.invalidKind(expected: 10063, got: event.kind)
        }

        // Parse server tags
        var parsedServers: [BlossomServerURL] = []

        for tag in event.tags {
            // Skip non-server tags
            guard tag.count >= 2, tag[0].string() == "server" else {
                continue
            }

            let urlString = tag[1].string()

            // Validate and parse server URL
            guard let serverURL = BlossomServerURL(urlString) else {
                // Skip invalid URLs rather than failing entirely
                // This allows graceful handling of malformed events
                continue
            }

            parsedServers.append(serverURL)
        }

        self.servers = parsedServers
        self.eventId = event.id
        self.createdAt = event.created_at
    }

    /// Parses a server list from an NdbNote.
    init(note: NdbNote) throws {
        // Validate event kind
        guard note.kind == NostrKind.blossom_server_list.rawValue else {
            throw BlossomServerListError.invalidKind(expected: 10063, got: note.kind)
        }

        // Parse server tags
        var parsedServers: [BlossomServerURL] = []

        for tag in note.tags {
            // Skip non-server tags
            guard tag.count >= 2, tag[0].string() == "server" else {
                continue
            }

            let urlString = tag[1].string()

            // Validate and parse server URL
            guard let serverURL = BlossomServerURL(urlString) else {
                continue
            }

            parsedServers.append(serverURL)
        }

        self.servers = parsedServers
        self.eventId = note.id
        self.createdAt = note.created_at
    }

    // MARK: - Conversion to Event

    /// Creates a kind 10063 nostr event from this server list.
    ///
    /// - Parameter keypair: The user's full keypair for signing
    /// - Parameter timestamp: Optional timestamp (defaults to now)
    /// - Returns: A signed NostrEvent, or nil if signing fails
    func toNostrEvent(keypair: FullKeypair, timestamp: UInt32? = nil) -> NostrEvent? {
        // Build server tags
        let tags: [[String]] = servers.map { server in
            ["server", server.absoluteString]
        }

        // Create and sign the event using NdbNote (following NIP65 pattern)
        // Kind 10063 is a replaceable event (10000-19999 range)
        return NdbNote(
            content: "",
            keypair: keypair.to_keypair(),
            kind: NostrKind.blossom_server_list.rawValue,
            tags: tags,
            createdAt: timestamp ?? UInt32(Date.now.timeIntervalSince1970)
        )
    }

    // MARK: - Mutations

    /// Returns a new list with the server added at the end.
    func adding(_ server: BlossomServerURL) -> BlossomServerList {
        // Don't add duplicates
        guard !servers.contains(server) else {
            return self
        }
        return BlossomServerList(servers: servers + [server])
    }

    /// Returns a new list with the server removed.
    func removing(_ server: BlossomServerURL) -> BlossomServerList {
        return BlossomServerList(servers: servers.filter { $0 != server })
    }

    /// Returns a new list with servers reordered.
    func reordered(_ newOrder: [BlossomServerURL]) -> BlossomServerList {
        return BlossomServerList(servers: newOrder)
    }

    // MARK: - Accessors

    /// The first (most preferred) server, if any.
    var primaryServer: BlossomServerURL? {
        servers.first
    }

    /// Whether the list is empty.
    var isEmpty: Bool {
        servers.isEmpty
    }

    /// Number of servers in the list.
    var count: Int {
        servers.count
    }
}

// MARK: - Errors

/// Errors that can occur when parsing a Blossom server list event.
enum BlossomServerListError: Error, LocalizedError {
    /// Event kind doesn't match expected 10063
    case invalidKind(expected: UInt32, got: UInt32)

    /// No valid server tags found in event
    case noServers

    var errorDescription: String? {
        switch self {
        case .invalidKind(let expected, let got):
            return "Invalid event kind: expected \(expected), got \(got)"
        case .noServers:
            return "No valid server URLs found in event"
        }
    }
}
