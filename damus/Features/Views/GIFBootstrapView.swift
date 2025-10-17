//
//  GIFBootstrapView.swift
//  damus
//
//  Simple UI for publishing the starter GIF catalog to Nostr.
//

import SwiftUI

struct GIFBootstrapView: View {
    @Environment(\.dismiss) private var dismiss

    let damus_state: DamusState

    @State private var isPublishing = false
    @State private var progressValue: (current: Int, total: Int)?
    @State private var errorMessage: String?
    @State private var publishedEventIds: [NoteId] = []

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bootstrap the community GIF catalog by publishing a curated starter set of reactions to your relays.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                if let progressValue {
                    ProgressView(value: Double(progressValue.current), total: Double(progressValue.total))
                        .accessibilityLabel("Publishing progress")
                    Text("Publishing GIF \(progressValue.current) of \(progressValue.total)…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if !publishedEventIds.isEmpty {
                    Text("Published events")
                        .font(.headline)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(publishedEventIds, id: \.self) { noteId in
                                Text(noteId.hex())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 180)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }

                Spacer()

                Button(action: startPublishing) {
                    if isPublishing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Publish Starter Catalog")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPublishing)
            }
            .padding()
            .navigationTitle("GIF Catalog")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func startPublishing() {
        guard !isPublishing else { return }
        guard let keypair = damus_state.keypair.to_full() else {
            errorMessage = NSLocalizedString("A private key is required to publish GIF metadata.", comment: "Bootstrap error")
            return
        }

        isPublishing = true
        errorMessage = nil
        publishedEventIds = []
        progressValue = (0, GIFCatalogBootstrap.getStarterCatalog().count)

        let entries = GIFCatalogBootstrap.getStarterCatalog()
        let postbox = damus_state.nostrNetwork.postbox
        let relayHints = damus_state.nostrNetwork.pool.our_descriptors.map { $0.url }

        Task {
            do {
                let events = try await GIFCatalogBootstrap.batchPublishGIFs(
                    entries,
                    keypair: keypair,
                    postbox: postbox,
                    relayHints: relayHints
                ) { current, total in
                    Task { @MainActor in
                        progressValue = (current, total)
                    }
                }

                await MainActor.run {
                    publishedEventIds = events.map { $0.id }
                    isPublishing = false
                }
            } catch {
                await MainActor.run {
                    isPublishing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    GIFBootstrapView(damus_state: test_damus_state)
}
