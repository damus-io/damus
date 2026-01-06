//
//  NostrSignerHandler.swift
//  damus
//
//  NIP-55 iOS Extension: Coordinates the signing flow for external app requests.
//

import Foundation
import SwiftUI

/// Result of processing a signing request.
enum SignerHandlerResult {
    /// Request was processed, open this callback URL.
    case callback(URL)

    /// Request requires user approval, show the approval UI.
    case requiresApproval(ApprovalContext, NostrSignerRequest)

    /// Request was from extension and result stored in bridge storage.
    /// No callback URL to open - extension will poll for result.
    case extensionComplete

    /// Request failed with no callback (malformed request).
    case failed
}

/// Handles NIP-55 signing requests from external apps.
///
/// This class coordinates the full signing flow:
/// 1. Receives parsed request from URL handler
/// 2. Evaluates request against SigningPolicyManager
/// 3. Either auto-approves, shows approval UI, or rejects
/// 4. Returns callback URL with result
///
/// ## Usage
/// ```swift
/// let result = await NostrSignerHandler.shared.handle(request: request)
/// switch result {
/// case .callback(let url):
///     UIApplication.shared.open(url)
/// case .requiresApproval(let context, let request):
///     // Show approval sheet
/// case .failed:
///     // Log error, no callback possible
/// }
/// ```
@MainActor
final class NostrSignerHandler: ObservableObject {

    // MARK: - Singleton

    /// Shared instance of the signer handler.
    static let shared = NostrSignerHandler()

    // MARK: - Published State

    /// The pending request awaiting user approval.
    @Published var pendingRequest: NostrSignerRequest?

    /// The approval context for the pending request.
    @Published var pendingContext: ApprovalContext?

    // MARK: - Private State

    /// Continuation for async approval flow.
    private var approvalContinuation: CheckedContinuation<Bool, Never>?

    // MARK: - Initialization

    private init() {}

    // MARK: - Request Handling

    /// Handles an incoming signing request.
    ///
    /// - Parameter request: The parsed signing request.
    /// - Returns: The result of processing the request.
    func handle(request: NostrSignerRequest) async -> SignerHandlerResult {
        // Get keypair from shared storage
        guard let keypair = SharedKeychainStorage.getKeypair() else {
            guard let url = NostrSignerResponse.notLoggedIn(request: request) else {
                return .failed
            }
            return .callback(url)
        }

        // Handle based on method type
        switch request.method {
        case .getPublicKey:
            return handleGetPublicKey(request: request, keypair: keypair)

        case .signEvent:
            return await handleSignEvent(request: request, keypair: keypair)

        case .nip04Encrypt, .nip04Decrypt, .nip44Encrypt, .nip44Decrypt, .decryptZapEvent:
            // TODO: Implement encryption/decryption methods
            guard let url = NostrSignerResponse.unsupportedMethod(request: request) else {
                return .failed
            }
            return .callback(url)
        }
    }

    // MARK: - Method Handlers

    /// Handles get_public_key requests.
    private func handleGetPublicKey(
        request: NostrSignerRequest,
        keypair: Keypair
    ) -> SignerHandlerResult {
        // Public key requests don't need approval
        guard let url = NostrSignerResponse.publicKeySuccess(
            request: request,
            pubkey: keypair.pubkey
        ) else {
            return .failed
        }
        return .callback(url)
    }

    /// Handles sign_event requests.
    private func handleSignEvent(
        request: NostrSignerRequest,
        keypair: Keypair
    ) async -> SignerHandlerResult {
        // Parse the unsigned event from request content
        guard let unsignedEvent = request.parseAsUnsignedEvent() else {
            guard let url = NostrSignerResponse.invalidContent(request: request) else {
                return .failed
            }
            return .callback(url)
        }

        // Build client identifier
        let client = SigningClient(
            id: request.clientId,
            name: request.callbackUrl.host,
            iconURL: nil
        )

        // Evaluate against policy manager
        let decision = SigningPolicyManager.shared.evaluate(
            event: unsignedEvent,
            client: client
        )

        switch decision {
        case .approve:
            return signAndRespond(request: request, unsignedEvent: unsignedEvent, keypair: keypair)

        case .deny(let reason):
            guard let url = NostrSignerResponse.error(
                request: request,
                message: reason,
                rejected: true
            ) else {
                return .failed
            }
            return .callback(url)

        case .requireApproval(let context):
            return .requiresApproval(context, request)
        }
    }

    // MARK: - Signing

    /// Signs an event and builds the response.
    private func signAndRespond(
        request: NostrSignerRequest,
        unsignedEvent: UnsignedEvent,
        keypair: Keypair
    ) -> SignerHandlerResult {
        // Need private key to sign
        guard let privkey = keypair.privkey else {
            return handleError(
                request: request,
                message: "No private key available (read-only mode)",
                rejected: false
            )
        }

        // Create and sign the event
        let createdAt = unsignedEvent.createdAt ?? UInt32(Date().timeIntervalSince1970)

        guard let signedEvent = NostrEvent(
            content: unsignedEvent.content,
            keypair: keypair,
            kind: unsignedEvent.kind,
            tags: unsignedEvent.tags,
            createdAt: createdAt
        ) else {
            return handleError(
                request: request,
                message: "Failed to sign event",
                rejected: false
            )
        }

        // Build response
        let signature = hex_encode(signedEvent.sig.data)
        let eventJson = request.returnType == .event ? event_to_json(ev: signedEvent) : nil

        // For extension requests, store result in bridge storage
        if let requestId = request.extensionRequestId {
            SignerBridgeStorage.storeResult(
                requestId: requestId,
                signedEventJson: eventJson,
                signature: signature
            )
            return .extensionComplete
        }

        // For normal requests, build callback URL
        guard let url = NostrSignerResponse.signEventSuccess(
            request: request,
            signature: signature,
            signedEventJson: eventJson
        ) else {
            return .failed
        }

        return .callback(url)
    }

    /// Handles an error response, routing to extension storage or callback URL.
    private func handleError(
        request: NostrSignerRequest,
        message: String,
        rejected: Bool
    ) -> SignerHandlerResult {
        // For extension requests, store error in bridge storage
        if let requestId = request.extensionRequestId {
            SignerBridgeStorage.storeResult(
                requestId: requestId,
                error: message
            )
            return .extensionComplete
        }

        // For normal requests, build callback URL
        guard let url = NostrSignerResponse.error(
            request: request,
            message: message,
            rejected: rejected
        ) else {
            return .failed
        }
        return .callback(url)
    }

    // MARK: - Approval Flow

    /// Called when user approves the pending request.
    ///
    /// - Parameter rememberChoice: Whether to remember this choice for future requests.
    func approveRequest(rememberChoice: Bool = false) {
        guard let request = pendingRequest,
              let context = pendingContext else {
            return
        }

        // If remembering, update permissions
        if rememberChoice {
            SigningPolicyManager.shared.approveKind(
                context.event.kind,
                for: context.client
            )
        }

        // Clear pending state
        clearPendingRequest()

        // Resume continuation
        approvalContinuation?.resume(returning: true)
        approvalContinuation = nil
    }

    /// Called when user denies the pending request.
    ///
    /// - Parameter blockClient: Whether to block this client entirely.
    func denyRequest(blockClient: Bool = false) {
        guard let context = pendingContext else {
            return
        }

        // If blocking, update permissions
        if blockClient {
            SigningPolicyManager.shared.blockClient(context.client)
        }

        // Clear pending state
        clearPendingRequest()

        // Resume continuation
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }

    /// Waits for user to approve or deny the pending request.
    ///
    /// - Parameters:
    ///   - context: The approval context.
    ///   - request: The original request.
    /// - Returns: True if approved, false if denied.
    func waitForApproval(context: ApprovalContext, request: NostrSignerRequest) async -> Bool {
        // Store pending request for UI
        self.pendingRequest = request
        self.pendingContext = context

        // Wait for user decision
        return await withCheckedContinuation { continuation in
            self.approvalContinuation = continuation
        }
    }

    /// Completes the approval flow and returns the callback URL.
    ///
    /// - Parameters:
    ///   - approved: Whether the request was approved.
    ///   - request: The original request.
    ///   - context: The approval context.
    /// - Returns: The callback URL to open, or nil for extension requests (result stored in bridge).
    func completeApproval(
        approved: Bool,
        request: NostrSignerRequest,
        context: ApprovalContext
    ) -> URL? {
        guard approved else {
            // Handle rejection for extension requests
            if let requestId = request.extensionRequestId {
                SignerBridgeStorage.storeResult(
                    requestId: requestId,
                    error: "User rejected signing request"
                )
                return nil
            }
            return NostrSignerResponse.rejected(request: request)
        }

        // Get keypair and sign
        guard let keypair = SharedKeychainStorage.getKeypair() else {
            if let requestId = request.extensionRequestId {
                SignerBridgeStorage.storeResult(
                    requestId: requestId,
                    error: "Not logged in to Damus"
                )
                return nil
            }
            return NostrSignerResponse.notLoggedIn(request: request)
        }

        let result = signAndRespond(
            request: request,
            unsignedEvent: context.event,
            keypair: keypair
        )

        switch result {
        case .callback(let url):
            return url
        case .extensionComplete:
            // Result already stored in bridge storage
            return nil
        case .requiresApproval, .failed:
            if let requestId = request.extensionRequestId {
                SignerBridgeStorage.storeResult(
                    requestId: requestId,
                    error: "Signing failed"
                )
                return nil
            }
            return NostrSignerResponse.error(
                request: request,
                message: "Signing failed",
                rejected: false
            )
        }
    }

    // MARK: - Private Helpers

    /// Clears the pending request state.
    private func clearPendingRequest() {
        pendingRequest = nil
        pendingContext = nil
    }
}
