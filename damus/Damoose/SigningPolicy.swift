//
//  SigningPolicy.swift
//  damus
//
//  Core types for the Damoose signing policy framework.
//

import Foundation

// MARK: - Unsigned Event

/// An event that has not yet been signed.
///
/// Contains all the fields needed to create a signed NostrEvent.
/// The pubkey, id, and sig are added during the signing process.
struct UnsignedEvent: Codable, Equatable {
    /// The event kind (e.g., 1 for text note, 3 for contacts).
    let kind: UInt32

    /// The event content.
    let content: String

    /// The event tags (e.g., p-tags for mentions, e-tags for references).
    let tags: [[String]]

    /// The creation timestamp. If nil, will be set to current time when signing.
    let createdAt: UInt32?

    /// Creates an unsigned event from its components.
    init(kind: UInt32, content: String, tags: [[String]], createdAt: UInt32? = nil) {
        self.kind = kind
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
    }

    /// Returns a human-readable summary of the event for approval UI.
    var summary: String {
        switch kind {
        case 0:
            return "Update profile metadata"
        case 1:
            let preview = content.prefix(100)
            return "Post: \"\(preview)\(content.count > 100 ? "..." : "")\""
        case 3:
            let contactCount = tags.filter { $0.first == "p" }.count
            return "Update contact list (\(contactCount) follows)"
        case 4:
            return "Send encrypted direct message"
        case 5:
            return "Delete event(s)"
        case 6:
            return "Repost/boost"
        case 7:
            return "React to post"
        default:
            return "Event kind \(kind)"
        }
    }
}

// MARK: - Signing Client

/// Identifies the source of a signing request.
///
/// Each client (app, extension, website) has a unique identifier and optional
/// metadata for display in approval prompts.
struct SigningClient: Codable, Hashable, Equatable {
    /// Unique identifier for this client.
    ///
    /// For Safari extension: the website origin (e.g., "https://highlighter.com")
    /// For URL scheme: the app's bundle ID (e.g., "com.primal.ios")
    /// For NIP-46: the client's pubkey
    let id: String

    /// Human-readable name for display in approval UI.
    let name: String?

    /// URL to the client's icon for display in approval UI.
    let iconURL: URL?

    /// When this client first connected.
    let firstSeen: Date

    /// Creates a signing client identifier.
    init(id: String, name: String? = nil, iconURL: URL? = nil, firstSeen: Date = Date()) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
        self.firstSeen = firstSeen
    }

    /// Creates a client for internal Damus app usage.
    static let damusInternal = SigningClient(
        id: "io.damus.internal",
        name: "Damus",
        iconURL: nil,
        firstSeen: Date.distantPast
    )
}

// MARK: - Policy Decision

/// The result of evaluating a signing request against policies.
enum PolicyDecision: Equatable {
    /// The request is approved and can proceed to signing.
    case approve

    /// The request is denied with a reason.
    case deny(reason: String)

    /// The request requires user approval before proceeding.
    case requireApproval(context: ApprovalContext)

    static func == (lhs: PolicyDecision, rhs: PolicyDecision) -> Bool {
        switch (lhs, rhs) {
        case (.approve, .approve):
            return true
        case (.deny(let r1), .deny(let r2)):
            return r1 == r2
        case (.requireApproval(let c1), .requireApproval(let c2)):
            return c1.summary == c2.summary
        default:
            return false
        }
    }
}

// MARK: - Approval Context

/// Context provided to the user approval UI.
///
/// Contains all information needed to display a meaningful approval prompt.
struct ApprovalContext {
    /// The client requesting the signature.
    let client: SigningClient

    /// The event to be signed.
    let event: UnsignedEvent

    /// Any risks detected in this signing request.
    let risks: [SigningRisk]

    /// Human-readable summary of what this signing will do.
    let summary: String

    /// Creates an approval context.
    init(client: SigningClient, event: UnsignedEvent, risks: [SigningRisk] = [], summary: String? = nil) {
        self.client = client
        self.event = event
        self.risks = risks
        self.summary = summary ?? event.summary
    }
}

// MARK: - Signing Risk

/// Potential risks detected in a signing request.
///
/// These are surfaced to the user in the approval UI to help them
/// make informed decisions about potentially dangerous operations.
enum SigningRisk: Equatable {
    /// Contact list would be reduced significantly.
    case contactListTruncation(removed: Int, remaining: Int)

    /// Contact list would become empty.
    case contactListEmpty

    /// This is a deletion event (kind 5).
    case deletionEvent

    /// Content is encrypted (user can't verify what they're signing).
    case encryptedContent

    /// High frequency of requests from this client.
    case highFrequency(count: Int, window: TimeInterval)

    /// Unknown or new client.
    case unknownClient

    /// Human-readable description of this risk.
    var description: String {
        switch self {
        case .contactListTruncation(let removed, let remaining):
            return "This will remove \(removed) follows (keeping \(remaining))"
        case .contactListEmpty:
            return "This will remove ALL your follows"
        case .deletionEvent:
            return "This will permanently delete content"
        case .encryptedContent:
            return "Content is encrypted - cannot verify what you're signing"
        case .highFrequency(let count, let window):
            let minutes = Int(window / 60)
            return "This client has made \(count) requests in \(minutes) minutes"
        case .unknownClient:
            return "This is a new/unknown client"
        }
    }

    /// Severity level for UI display (higher = more dangerous).
    var severity: Int {
        switch self {
        case .contactListEmpty: return 5
        case .contactListTruncation: return 4
        case .deletionEvent: return 3
        case .highFrequency: return 2
        case .encryptedContent: return 2
        case .unknownClient: return 1
        }
    }
}

// MARK: - Kind Policy Protocol

/// A policy that evaluates signing requests for a specific event kind.
///
/// Implement this protocol to add custom validation logic for specific
/// event types (e.g., contact list protection, deletion safeguards).
protocol KindPolicy {
    /// The event kind this policy applies to.
    var kind: UInt32 { get }

    /// Evaluates a signing request.
    ///
    /// - Parameters:
    ///   - event: The unsigned event to evaluate.
    ///   - client: The client requesting the signature.
    /// - Returns: A policy decision (approve, deny, or require approval).
    func evaluate(event: UnsignedEvent, client: SigningClient) -> PolicyDecision
}
