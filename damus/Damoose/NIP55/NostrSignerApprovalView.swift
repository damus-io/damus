//
//  NostrSignerApprovalView.swift
//  damus
//
//  NIP-55 iOS Extension: Approval UI for external signing requests.
//

import SwiftUI

/// Approval sheet for external signing requests.
///
/// Displays the requesting app, what they want to sign, any detected risks,
/// and approve/deny buttons with optional "remember" checkboxes.
struct NostrSignerApprovalView: View {

    // MARK: - Properties

    let context: ApprovalContext
    let request: NostrSignerRequest
    let onApprove: (Bool) -> Void  // Bool = rememberChoice
    let onDeny: (Bool) -> Void     // Bool = blockClient

    @State private var rememberChoice = false
    @State private var blockClient = false

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // App info header
                    appHeader

                    Divider()

                    // What they want to sign
                    requestDetails

                    // Risk warnings (if any)
                    if !context.risks.isEmpty {
                        riskWarnings
                    }

                    Divider()

                    // Options
                    optionsSection

                    // Action buttons
                    actionButtons
                }
                .padding()
            }
            .background(backgroundColor)
            .navigationTitle("Signing Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDeny(blockClient)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    /// Header showing the requesting app.
    private var appHeader: some View {
        VStack(spacing: 12) {
            // App icon placeholder
            Image(systemName: "app.badge")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            // App name
            Text(context.client.name ?? context.client.id)
                .font(.headline)

            // Client ID
            Text(context.client.id)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    /// Details about the signing request.
    private var requestDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("wants to:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Summary of what's being signed
            HStack {
                kindIcon
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.summary)
                        .font(.body)
                        .fontWeight(.medium)

                    Text("Kind \(context.event.kind)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)

            // Content preview for text events
            if shouldShowContentPreview {
                contentPreview
            }
        }
    }

    /// Icon based on the event kind.
    private var kindIcon: some View {
        let icon: String
        switch context.event.kind {
        case 0: icon = "person.crop.circle"       // Metadata
        case 1: icon = "text.bubble"              // Text note
        case 3: icon = "person.2"                 // Contacts
        case 4: icon = "lock"                     // DM
        case 5: icon = "trash"                    // Deletion
        case 6: icon = "arrow.2.squarepath"       // Repost
        case 7: icon = "heart"                    // Reaction
        default: icon = "doc.text"
        }
        return Image(systemName: icon)
    }

    /// Whether to show a content preview.
    private var shouldShowContentPreview: Bool {
        let previewableKinds: Set<UInt32> = [1, 4, 7]  // Notes, DMs, reactions
        return previewableKinds.contains(context.event.kind) && !context.event.content.isEmpty
    }

    /// Preview of the event content.
    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content:")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(context.event.content.prefix(200) + (context.event.content.count > 200 ? "..." : ""))
                .font(.body)
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
        }
    }

    /// Risk warning section.
    private var riskWarnings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Warnings")
                    .font(.headline)
            }

            ForEach(context.risks.sorted { $0.severity > $1.severity }, id: \.description) { risk in
                riskRow(risk)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    /// A single risk warning row.
    private func riskRow(_ risk: SigningRisk) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: riskIcon(for: risk))
                .foregroundColor(riskColor(for: risk))

            Text(risk.description)
                .font(.subheadline)
        }
    }

    /// Icon for a risk type.
    private func riskIcon(for risk: SigningRisk) -> String {
        switch risk {
        case .contactListEmpty, .contactListTruncation:
            return "person.2.slash"
        case .deletionEvent:
            return "trash"
        case .encryptedContent:
            return "lock.shield"
        case .highFrequency:
            return "speedometer"
        case .unknownClient:
            return "questionmark.circle"
        }
    }

    /// Color for a risk type based on severity.
    private func riskColor(for risk: SigningRisk) -> Color {
        switch risk.severity {
        case 5: return .red
        case 4: return .orange
        case 3: return .yellow
        default: return .secondary
        }
    }

    /// Options section with checkboxes.
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $rememberChoice) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remember this choice")
                        .font(.subheadline)
                    Text("Auto-approve kind \(context.event.kind) from this app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(CheckboxToggleStyle())
        }
    }

    /// Approve and deny buttons.
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Approve button
            Button {
                onApprove(rememberChoice)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Approve")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // Deny button
            Button {
                onDeny(blockClient)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("Deny")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
        }
    }

    /// Background color based on color scheme.
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
}

// MARK: - Checkbox Toggle Style

/// A checkbox-style toggle for the options.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                    .font(.title3)

                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct NostrSignerApprovalView_Previews: PreviewProvider {
    static var previews: some View {
        let event = UnsignedEvent(
            kind: 1,
            content: "Hello, world! This is a test post from an external app.",
            tags: []
        )

        let client = SigningClient(
            id: "com.example.nostrapp",
            name: "Example Nostr App"
        )

        let context = ApprovalContext(
            client: client,
            event: event,
            risks: [.unknownClient]
        )

        let request = NostrSignerRequest(
            method: .signEvent,
            content: nil,
            callbackUrl: URL(string: "example://callback")!,
            returnType: .event,
            compressionType: .none,
            targetPubkey: nil,
            extensionRequestId: nil
        )

        NostrSignerApprovalView(
            context: context,
            request: request,
            onApprove: { _ in },
            onDeny: { _ in }
        )
    }
}
#endif
