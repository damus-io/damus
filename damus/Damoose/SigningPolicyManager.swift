//
//  SigningPolicyManager.swift
//  damus
//
//  Central manager for evaluating signing requests against policies.
//

import Foundation

/// Manages signing policy evaluation for Damoose.
///
/// This singleton evaluates signing requests from external clients (Safari extension,
/// URL scheme, NIP-46) and determines whether they should be approved, denied, or
/// require user approval.
///
/// ## Usage
/// ```swift
/// let decision = SigningPolicyManager.shared.evaluate(
///     event: unsignedEvent,
///     client: requestingClient
/// )
///
/// switch decision {
/// case .approve:
///     return sign(event)
/// case .deny(let reason):
///     return .error(reason)
/// case .requireApproval(let context):
///     let approved = await showApprovalUI(context)
///     // ...
/// }
/// ```
@MainActor
final class SigningPolicyManager: ObservableObject {

    // MARK: - Singleton

    /// Shared instance of the policy manager.
    static let shared = SigningPolicyManager()

    // MARK: - Published State

    /// All client permissions, keyed by client ID.
    @Published private(set) var clientPermissions: [String: ClientPermissions]

    // MARK: - Private State

    /// Kind-specific policy implementations.
    private var kindPolicies: [UInt32: KindPolicy] = [:]

    /// Default policy for kinds without specific policies.
    private var defaultPolicy: KindPolicy?

    // MARK: - Initialization

    private init() {
        self.clientPermissions = ClientPermissionsStore.loadAll()
        registerDefaultPolicies()
    }

    // MARK: - Policy Registration

    /// Registers a policy for a specific event kind.
    ///
    /// - Parameter policy: The policy to register.
    func registerPolicy(_ policy: KindPolicy) {
        kindPolicies[policy.kind] = policy
    }

    /// Sets the default policy for kinds without specific policies.
    ///
    /// - Parameter policy: The default policy to use.
    func setDefaultPolicy(_ policy: KindPolicy) {
        defaultPolicy = policy
    }

    /// Registers the built-in default policies.
    private func registerDefaultPolicies() {
        // Contact list protection is critical
        registerPolicy(ContactListPolicy())
    }

    // MARK: - Policy Evaluation

    /// Evaluates a signing request against all applicable policies.
    ///
    /// This is the main entry point for the policy system. It checks:
    /// 1. Whether the client is blocked
    /// 2. Whether the event kind is approved for this client
    /// 3. Kind-specific policy rules
    ///
    /// - Parameters:
    ///   - event: The unsigned event to evaluate.
    ///   - client: The client requesting the signature.
    /// - Returns: A policy decision (approve, deny, or require approval).
    func evaluate(event: UnsignedEvent, client: SigningClient) -> PolicyDecision {
        // Internal Damus requests are always approved
        guard client.id != SigningClient.damusInternal.id else {
            return .approve
        }

        // Get or create permissions for this client
        let permissions = getOrCreatePermissions(for: client)

        // Check if client is blocked
        guard !permissions.isBlocked else {
            return .deny(reason: "This app has been blocked")
        }

        // Check if kind is explicitly blocked
        guard !permissions.blockedKinds.contains(event.kind) else {
            return .deny(reason: "This event type has been blocked for this app")
        }

        // Run kind-specific policy if available
        if let kindPolicy = kindPolicies[event.kind] {
            let policyDecision = kindPolicy.evaluate(event: event, client: client)

            // If kind policy denies, respect that
            if case .deny = policyDecision {
                return policyDecision
            }

            // If kind policy requires approval, respect that
            if case .requireApproval = policyDecision {
                return policyDecision
            }
        }

        // Check if kind is approved for this client
        if permissions.isKindApproved(event.kind) {
            recordRequest(for: client)
            return .approve
        }

        // Unknown kind/client combination - require approval
        return .requireApproval(context: buildApprovalContext(
            event: event,
            client: client,
            risks: detectRisks(event: event, client: client, permissions: permissions)
        ))
    }

    // MARK: - Permission Management

    /// Gets existing permissions or creates default permissions for a client.
    ///
    /// - Parameter client: The client to get permissions for.
    /// - Returns: The client's permissions.
    func getOrCreatePermissions(for client: SigningClient) -> ClientPermissions {
        if let existing = clientPermissions[client.id] {
            return existing
        }

        let newPermissions = ClientPermissions(clientId: client.id)
        clientPermissions[client.id] = newPermissions
        ClientPermissionsStore.save(newPermissions)
        return newPermissions
    }

    /// Updates permissions for a client.
    ///
    /// - Parameter permissions: The updated permissions.
    func updatePermissions(_ permissions: ClientPermissions) {
        var updated = permissions
        updated.lastModified = Date()
        clientPermissions[permissions.clientId] = updated
        ClientPermissionsStore.save(updated)
    }

    /// Approves a specific event kind for a client.
    ///
    /// - Parameters:
    ///   - kind: The event kind to approve.
    ///   - client: The client to approve for.
    func approveKind(_ kind: UInt32, for client: SigningClient) {
        var permissions = getOrCreatePermissions(for: client)
        permissions.approvedKinds.insert(kind)
        permissions.blockedKinds.remove(kind)
        updatePermissions(permissions)
    }

    /// Blocks a specific event kind for a client.
    ///
    /// - Parameters:
    ///   - kind: The event kind to block.
    ///   - client: The client to block for.
    func blockKind(_ kind: UInt32, for client: SigningClient) {
        var permissions = getOrCreatePermissions(for: client)
        permissions.blockedKinds.insert(kind)
        permissions.approvedKinds.remove(kind)
        updatePermissions(permissions)
    }

    /// Blocks a client entirely.
    ///
    /// - Parameter client: The client to block.
    func blockClient(_ client: SigningClient) {
        var permissions = getOrCreatePermissions(for: client)
        permissions.isBlocked = true
        updatePermissions(permissions)
    }

    /// Unblocks a client.
    ///
    /// - Parameter client: The client to unblock.
    func unblockClient(_ client: SigningClient) {
        var permissions = getOrCreatePermissions(for: client)
        permissions.isBlocked = false
        updatePermissions(permissions)
    }

    /// Sets the trust level for a client.
    ///
    /// - Parameters:
    ///   - level: The trust level to set.
    ///   - client: The client to update.
    func setTrustLevel(_ level: TrustLevel, for client: SigningClient) {
        var permissions = getOrCreatePermissions(for: client)
        permissions.trustLevel = level
        updatePermissions(permissions)
    }

    // MARK: - Private Helpers

    /// Records that a client made a signing request.
    private func recordRequest(for client: SigningClient) {
        guard var permissions = clientPermissions[client.id] else {
            return
        }
        permissions.recordRequest()
        clientPermissions[client.id] = permissions
        ClientPermissionsStore.save(permissions)
    }

    /// Builds an approval context for the UI.
    private func buildApprovalContext(
        event: UnsignedEvent,
        client: SigningClient,
        risks: [SigningRisk]
    ) -> ApprovalContext {
        ApprovalContext(
            client: client,
            event: event,
            risks: risks.sorted { $0.severity > $1.severity }
        )
    }

    /// Detects risks in a signing request.
    private func detectRisks(
        event: UnsignedEvent,
        client: SigningClient,
        permissions: ClientPermissions
    ) -> [SigningRisk] {
        var risks: [SigningRisk] = []

        // Check for unknown client
        if permissions.requestCount == 0 {
            risks.append(.unknownClient)
        }

        // Check for deletion event
        if event.kind == 5 {
            risks.append(.deletionEvent)
        }

        // Check for encrypted content (kind 4 DMs)
        if event.kind == 4 {
            risks.append(.encryptedContent)
        }

        // Note: Contact list risks are detected by ContactListPolicy

        return risks
    }
}
