//
//  DMRelayListView.swift
//  damus
//
//  Created for NIP-17 DM relay list (kind:10050) management
//

import SwiftUI

/// View for managing the user's DM relay list (kind:10050)
///
/// Per NIP-17, users publish a kind:10050 event listing relays where they receive DMs.
/// This view allows users to view, add, and remove relays from that list.
struct DMRelayListView: View {
    let state: DamusState

    @State private var dmRelays: [RelayURL] = []
    @State private var isLoading = true
    @State private var showAddRelay = false
    @State private var newRelayURL = ""
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    @State private var hasExistingList = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("DM Relays", comment: "Title for DM relay list section")
                        .font(.system(size: 32, weight: .bold))

                    Spacer()

                    if state.keypair.privkey != nil {
                        Button(action: { showAddRelay = true }) {
                            Text("Add relay", comment: "Button to add a DM relay")
                                .padding(10)
                        }
                        .buttonStyle(NeutralButtonStyle())
                    }
                }
                .padding(.top, 5)

                // Explanation text
                Text("Relays where you receive encrypted private messages (NIP-17)", comment: "Explanation of what DM relays are for")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                } else if dmRelays.isEmpty {
                    VStack(spacing: 12) {
                        Text("No DM relays configured", comment: "Message when user has no DM relays")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Add relays to receive encrypted DMs from other NIP-17 compatible apps.", comment: "Hint to add DM relays")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        if state.keypair.privkey != nil {
                            Button(action: setupDefaultRelays) {
                                Text("Use default relays", comment: "Button to set up default DM relays")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(GradientButtonStyle(padding: 10))
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // Relay list
                    ForEach(dmRelays, id: \.absoluteString) { relay in
                        DMRelayRowView(
                            state: state,
                            relay: relay,
                            onRemove: { removeRelay(relay) }
                        )
                        Divider()
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }

                Spacer()
                    .padding(25)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showAddRelay) {
            AddDMRelaySheet(
                newRelayURL: $newRelayURL,
                onAdd: addRelay,
                onCancel: { showAddRelay = false }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            Task { await loadDMRelays() }
        }
    }

    // MARK: - Actions

    private func loadDMRelays() async {
        isLoading = true
        errorMessage = nil

        let relays = await state.fetchOwnDMRelayList()

        await MainActor.run {
            self.dmRelays = relays
            self.hasExistingList = !relays.isEmpty
            self.isLoading = false
        }
    }

    private func addRelay() {
        guard !newRelayURL.isEmpty else { return }

        var urlString = newRelayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("wss://") && !urlString.hasPrefix("ws://") {
            urlString = "wss://" + urlString
        }

        guard let url = RelayURL(urlString) else {
            errorMessage = NSLocalizedString("Invalid relay URL", comment: "Error when relay URL is invalid")
            return
        }

        // Check for duplicates
        if dmRelays.contains(where: { $0.absoluteString == url.absoluteString }) {
            errorMessage = NSLocalizedString("Relay already in list", comment: "Error when relay is already added")
            return
        }

        dmRelays.append(url)
        newRelayURL = ""
        showAddRelay = false
        errorMessage = nil

        Task { await publishDMRelayList() }
    }

    private func removeRelay(_ relay: RelayURL) {
        dmRelays.removeAll { $0.absoluteString == relay.absoluteString }
        Task { await publishDMRelayList() }
    }

    private func setupDefaultRelays() {
        // Use same defaults as bootstrap relays, but subset for DMs
        let defaultDMRelays = [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://nostr.wine"
        ].compactMap { RelayURL($0) }

        dmRelays = defaultDMRelays
        Task { await publishDMRelayList() }
    }

    private func publishDMRelayList() async {
        guard let keypair = state.keypair.to_full()?.to_keypair() else {
            await MainActor.run {
                errorMessage = NSLocalizedString("Cannot publish: no private key", comment: "Error when user has no private key")
            }
            return
        }

        await MainActor.run { isSaving = true }

        guard let event = NIP17.createDMRelayList(relays: dmRelays, keypair: keypair) else {
            await MainActor.run {
                errorMessage = NSLocalizedString("Failed to create relay list event", comment: "Error creating kind:10050 event")
                isSaving = false
            }
            return
        }

        // Publish to our relays
        await state.nostrNetwork.postbox.send(event)

        await MainActor.run {
            isSaving = false
            hasExistingList = true
            errorMessage = nil
        }

        #if DEBUG
        print("[DM-Relays] Published kind:10050 with \(dmRelays.count) relays")
        #endif
    }
}

// MARK: - DMRelayRowView

struct DMRelayRowView: View {
    let state: DamusState
    let relay: RelayURL
    let onRemove: () -> Void

    @ObservedObject private var modelCache: RelayModelCache

    init(state: DamusState, relay: RelayURL, onRemove: @escaping () -> Void) {
        self.state = state
        self.relay = relay
        self.onRemove = onRemove
        self.modelCache = state.relay_model_cache
    }

    var body: some View {
        HStack {
            let meta = modelCache.model(with_relay_id: relay)?.metadata

            RelayPicView(relay: relay, icon: meta?.icon, size: 55, highlight: .none, disable_animation: false)

            VStack(alignment: .leading) {
                HStack {
                    Text(meta?.name ?? relay.url.host() ?? relay.url.absoluteString)
                        .font(.headline)
                        .padding(.bottom, 2)
                        .lineLimit(1)

                    if relay.absoluteString.hasSuffix(".onion") {
                        Image("tor")
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 20, height: 20)
                    }
                }
                Text(relay.absoluteString)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            if state.keypair.privkey != nil {
                Button(action: onRemove) {
                    Image("minus-circle")
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.red)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - AddDMRelaySheet

struct AddDMRelaySheet: View {
    @Binding var newRelayURL: String
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack {
            Text("Add DM Relay", comment: "Title for add DM relay sheet")
                .font(.system(size: 20, weight: .bold))
                .padding(.vertical)

            Divider()
                .padding(.bottom)

            HStack {
                Label("", image: "copy2")
                    .onTapGesture {
                        if let pasted = UIPasteboard.general.string {
                            newRelayURL = pasted
                        }
                    }

                TextField(
                    NSLocalizedString("wss://some.relay.com", comment: "Placeholder for relay URL"),
                    text: $newRelayURL
                )
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)

                Label("", image: "close-circle")
                    .foregroundColor(.accentColor)
                    .opacity(newRelayURL.isEmpty ? 0.0 : 1.0)
                    .onTapGesture { newRelayURL = "" }
            }
            .padding(10)
            .background(.secondary.opacity(0.2))
            .cornerRadius(10)

            Button(action: onAdd) {
                HStack {
                    Text("Add relay", comment: "Button to add relay")
                        .bold()
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle(padding: 10))
            .padding(.vertical)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Preview

struct DMRelayListView_Previews: PreviewProvider {
    static var previews: some View {
        DMRelayListView(state: test_damus_state)
    }
}
