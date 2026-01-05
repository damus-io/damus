//
//  NostrSignerApprovalSheet.swift
//  damus
//
//  NIP-55 iOS Extension: Sheet wrapper that handles the full signing flow.
//

import SwiftUI

/// Sheet wrapper for NIP-55 signing requests.
///
/// This view handles the complete flow:
/// 1. Evaluates the request against SigningPolicyManager
/// 2. If auto-approved, immediately signs and opens callback
/// 3. If requires approval, shows NostrSignerApprovalView
/// 4. On user decision, signs (or rejects) and opens callback
struct NostrSignerApprovalSheet: View {

    let request: NostrSignerRequest
    let damus_state: DamusState

    @Environment(\.dismiss) var dismiss
    @State private var approvalContext: ApprovalContext?
    @State private var isProcessing = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isProcessing {
                processingView
            } else if let context = approvalContext {
                NostrSignerApprovalView(
                    context: context,
                    request: request,
                    onApprove: { rememberChoice in
                        handleApproval(approved: true, rememberChoice: rememberChoice, context: context)
                    },
                    onDeny: { blockClient in
                        handleApproval(approved: false, blockClient: blockClient, context: context)
                    }
                )
            } else if let error = errorMessage {
                errorView(error)
            }
        }
        .task {
            await processRequest()
        }
    }

    // MARK: - Subviews

    /// Loading/processing view.
    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Processing signing request...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Error view when something goes wrong.
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Signing Request Failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Request Processing

    /// Processes the signing request.
    @MainActor
    private func processRequest() async {
        let result = await NostrSignerHandler.shared.handle(request: request)

        switch result {
        case .callback(let url):
            // Auto-approved or simple request (like get_public_key)
            openCallback(url)
            dismiss()

        case .requiresApproval(let context, _):
            // Need user approval
            self.approvalContext = context
            self.isProcessing = false

        case .failed:
            // Something went wrong, no callback possible
            self.errorMessage = "Invalid signing request"
            self.isProcessing = false
        }
    }

    /// Handles user approval or denial.
    @MainActor
    private func handleApproval(approved: Bool, rememberChoice: Bool = false, blockClient: Bool = false, context: ApprovalContext) {
        // Update permissions if needed
        if approved && rememberChoice {
            SigningPolicyManager.shared.approveKind(context.event.kind, for: context.client)
        }
        if !approved && blockClient {
            SigningPolicyManager.shared.blockClient(context.client)
        }

        // Get callback URL
        guard let callbackUrl = NostrSignerHandler.shared.completeApproval(
            approved: approved,
            request: request,
            context: context
        ) else {
            self.errorMessage = "Failed to generate response"
            return
        }

        openCallback(callbackUrl)
        dismiss()
    }

    /// Opens the callback URL to return result to requesting app.
    private func openCallback(_ url: URL) {
        // Use UIApplication to open the URL
        // This will switch to the requesting app
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    print("NostrSigner: Failed to open callback URL: \(url)")
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct NostrSignerApprovalSheet_Previews: PreviewProvider {
    static var previews: some View {
        let request = NostrSignerRequest(
            method: .signEvent,
            content: nil,
            callbackUrl: URL(string: "example://callback")!,
            returnType: .event,
            compressionType: .none,
            targetPubkey: nil
        )

        Text("Preview requires DamusState")
    }
}
#endif
