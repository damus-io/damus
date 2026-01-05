//
//  ClientPermissions.swift
//  damus
//
//  Per-client permission storage for Damoose signing policy.
//

import Foundation

// MARK: - Trust Level

/// Trust level assigned to a signing client.
///
/// Determines the default behavior for signing requests from this client.
enum TrustLevel: String, Codable, CaseIterable {
    /// Always require user approval for every request.
    case untrusted

    /// Auto-approve safe event kinds only (reactions, basic posts).
    case limited

    /// Auto-approve most operations except dangerous ones.
    case trusted

    /// Auto-approve everything. Reserved for internal Damus use.
    case full

    /// Human-readable description for settings UI.
    var description: String {
        switch self {
        case .untrusted:
            return "Always ask"
        case .limited:
            return "Auto-approve safe actions"
        case .trusted:
            return "Auto-approve most actions"
        case .full:
            return "Auto-approve all"
        }
    }

    /// Event kinds that are auto-approved at this trust level.
    var autoApprovedKinds: Set<UInt32> {
        switch self {
        case .untrusted:
            return []
        case .limited:
            // Reactions, reposts - low risk
            return [6, 7]
        case .trusted:
            // Posts, reactions, reposts, DMs, zap requests
            return [1, 4, 6, 7, 9734]
        case .full:
            // Everything
            return []  // Special case: all kinds approved
        }
    }
}

// MARK: - Client Permissions

/// Permissions granted to a specific signing client.
///
/// Stored in UserDefaults, keyed by client ID.
struct ClientPermissions: Codable, Equatable {
    /// The client these permissions apply to.
    let clientId: String

    /// Event kinds explicitly approved for this client.
    var approvedKinds: Set<UInt32>

    /// Event kinds explicitly blocked for this client.
    var blockedKinds: Set<UInt32>

    /// The trust level for this client.
    var trustLevel: TrustLevel

    /// Whether this client is completely blocked.
    var isBlocked: Bool

    /// When these permissions were last modified.
    var lastModified: Date

    /// When this client last made a signing request.
    var lastUsed: Date?

    /// Total number of signing requests from this client.
    var requestCount: Int

    /// Creates default permissions for a new client.
    init(clientId: String) {
        self.clientId = clientId
        self.approvedKinds = []
        self.blockedKinds = []
        self.trustLevel = .untrusted
        self.isBlocked = false
        self.lastModified = Date()
        self.lastUsed = nil
        self.requestCount = 0
    }

    /// Checks if a specific event kind is approved for this client.
    ///
    /// - Parameter kind: The event kind to check.
    /// - Returns: true if the kind is approved (explicitly or via trust level).
    func isKindApproved(_ kind: UInt32) -> Bool {
        // Blocked kinds are never approved
        guard !blockedKinds.contains(kind) else {
            return false
        }

        // Check explicit approval
        if approvedKinds.contains(kind) {
            return true
        }

        // Check trust level auto-approval
        if trustLevel == .full {
            return true
        }

        return trustLevel.autoApprovedKinds.contains(kind)
    }

    /// Records that this client made a signing request.
    mutating func recordRequest() {
        lastUsed = Date()
        requestCount += 1
    }
}

// MARK: - Permissions Store

/// Manages persistent storage of client permissions.
///
/// Permissions are stored in UserDefaults as JSON, keyed by a common prefix.
enum ClientPermissionsStore {
    private static let storageKey = "damoose_client_permissions"

    /// Loads all stored client permissions.
    ///
    /// - Returns: Dictionary of client ID to permissions.
    static func loadAll() -> [String: ClientPermissions] {
        guard let data = DamusUserDefaults.standard.object(forKey: storageKey) as? Data else {
            return [:]
        }
        guard let permissions = try? JSONDecoder().decode([String: ClientPermissions].self, from: data) else {
            return [:]
        }
        return permissions
    }

    /// Saves all client permissions.
    ///
    /// - Parameter permissions: Dictionary of client ID to permissions.
    static func saveAll(_ permissions: [String: ClientPermissions]) {
        guard let data = try? JSONEncoder().encode(permissions) else {
            return
        }
        DamusUserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Loads permissions for a specific client.
    ///
    /// - Parameter clientId: The client ID to look up.
    /// - Returns: The client's permissions, or nil if not found.
    static func load(clientId: String) -> ClientPermissions? {
        let all = loadAll()
        return all[clientId]
    }

    /// Saves permissions for a specific client.
    ///
    /// - Parameter permissions: The permissions to save.
    static func save(_ permissions: ClientPermissions) {
        var all = loadAll()
        all[permissions.clientId] = permissions
        saveAll(all)
    }

    /// Deletes permissions for a specific client.
    ///
    /// - Parameter clientId: The client ID to delete.
    static func delete(clientId: String) {
        var all = loadAll()
        all.removeValue(forKey: clientId)
        saveAll(all)
    }

    /// Resets all client permissions.
    static func reset() {
        DamusUserDefaults.standard.removeObject(forKey: storageKey)
    }
}
