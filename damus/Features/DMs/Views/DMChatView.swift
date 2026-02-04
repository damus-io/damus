//
//  DMChatView.swift
//  damus
//
//  Created by William Casarin on 2022-06-30.
//

import SwiftUI
import Combine

struct DMChatView: View, KeyboardReadable {
    let damus_state: DamusState
    @FocusState private var isTextFieldFocused: Bool
    @ObservedObject var dms: DirectMessageModel
    @State private var showRelayWarning = false
    @State private var pendingMessageContent: String? = nil
    @State private var isSending = false

    var pubkey: Pubkey {
        dms.pubkey
    }

    var Messages: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(Array(zip(dms.events, dms.events.indices)).filter { should_show_event(state: damus_state, ev: $0.0)}, id: \.0.id) { (ev, ind) in
                        DMView(event: dms.events[ind], damus_state: damus_state)
                            .contextMenu{MenuItems(damus_state: damus_state, event: ev, target_pubkey: ev.pubkey, profileModel: ProfileModel(pubkey: ev.pubkey, damus: damus_state))}
                    }
                    EndBlock(height: 1)
                }
                .padding(.horizontal)
            }
            .dismissKeyboardOnTap()
            .onAppear {
                scroll_to_end(scroller)
            }
            .onChange(of: dms.events.count) { _ in
                scroll_to_end(scroller, animated: true)
            }
            .onReceive(keyboardPublisher) { visible in
                guard visible else {
                    return
                }
                // Note: Simulator hardware keyboards can bypass keyboard insets; the iOS software keyboard behaves correctly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scroll_to_end(scroller, animated: true)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Footer
                .padding(.bottom, isTextFieldFocused ? 0 : tabHeight)
        }
    }
    
    func scroll_to_end(_ scroller: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation {
                scroller.scrollTo("endblock")
            }
        } else {
            scroller.scrollTo("endblock")
        }
    }

    var Header: some View {
        NavigationLink(value: Route.ProfileByKey(pubkey: pubkey)) {
            HStack {
                ProfilePicView(pubkey: pubkey, size: 24, highlight: .none, profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation, damusState: damus_state)

                ProfileName(pubkey: pubkey, damus: damus_state)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    var InputField: some View {
        TextEditor(text: $dms.draft)
            .textEditorBackground {
                InputBackground()
            }
            .focused($isTextFieldFocused)
            .cornerRadius(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: .init(lineWidth: 2))
                    .foregroundColor(.secondary.opacity(0.2))
            )
            .padding(16)
            .foregroundColor(Color.primary)
            .frame(minHeight: 70, maxHeight: 150, alignment: .bottom)
            .fixedSize(horizontal: false, vertical: true)
    }

    @Environment(\.colorScheme) var colorScheme

    func InputBackground() -> Color {
        if colorScheme == .light {
            return Color.init(.sRGB, red: 0.9, green: 0.9, blue: 0.9, opacity: 1.0)
        } else {
            return Color.init(.sRGB, red: 0.1, green: 0.1, blue: 0.1, opacity: 1.0)
        }
    }

    /// Whether we'll send using NIP-17 (requires private key)
    private var willSendNIP17: Bool {
        damus_state.keypair.privkey != nil
    }

    var Footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                InputField

                if !dms.draft.isEmpty || isSending {
                    // Keep the tap target at least 44x44 per HIG.
                    Button(
                        role: .none,
                        action: {
                            guard !isSending else { return }
                            let draftContent = dms.draft
                            dms.draft = ""  // Clear immediately for responsive feel
                            isSending = true
                            Task {
                                await send_message(content: draftContent)
                                await MainActor.run { isSending = false }
                            }
                        }
                    ) {
                        if isSending {
                            ProgressView()
                                .frame(width: 24, height: 24)
                        } else {
                            Label("", image: "send")
                                .font(.title)
                        }
                    }
                    .disabled(isSending)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    func send_message(content draftContent: String) async {
        guard let post_blocks = parse_post_blocks(content: draftContent)?.blocks else {
            return
        }
        let content = post_blocks.map({ pb in pb.asString }).joined(separator: "")

        // Try NIP-17 first (more private), fall back to NIP-04
        if let fullKeypair = damus_state.keypair.to_full() {
            // Check for recipient's DM relay list (kind 10050)
            let recipientDMRelays = await fetchDMRelayList(for: pubkey)

            if recipientDMRelays.isEmpty {
                // No DM relay list - show warning and ask user
                pendingMessageContent = content
                showRelayWarning = true
            } else {
                // DM Outbox: Send to recipient's DM relays
                // sendToEphemeralRelays handles connect, send, and lease lifecycle
                #if DEBUG
                print("[DM-DEBUG] DM Outbox: Attempting to send to \(recipientDMRelays.count) DM relays")
                #endif
                let success = await send_nip17_message(content: content, sender: fullKeypair, toRelays: recipientDMRelays)

                if !success {
                    // Failed to connect to any of recipient's DM relays - show warning
                    #if DEBUG
                    print("[DM-DEBUG] DM Outbox: Connection failed, showing fallback warning")
                    #endif
                    pendingMessageContent = content
                    showRelayWarning = true
                }
            }
        } else {
            // Read-only mode or no private key - try NIP-04
            await send_nip04_message(content: content)
            end_editing()
        }
    }

    /// Fetches the DM relay list (kind 10050) for a pubkey.
    /// Returns the most recent relay list (by created_at) to handle replaceable events correctly.
    /// Performs a quick local lookup, then does a bounded network fetch if needed.
    private func fetchDMRelayList(for target: Pubkey) async -> [RelayURL] {
        let filter = NostrFilter(kinds: [.dm_relay_list], authors: [target])

        // Step 1: Check local cache first (fast path)
        if let localEvent = await fetchLatestEvent(filter: filter, timeout: .seconds(1), streamMode: .ndbOnly, targetRelays: nil) {
            #if DEBUG
            print("[DM-DEBUG] DM Relay List: Found local kind:10050 for \(target.npub)")
            #endif
            return NIP17.parseDMRelayList(event: localEvent)
        }

        // Step 2: Try network via best-effort relays
        await damus_state.nostrNetwork.awaitConnection(timeout: .seconds(5))
        let bestEffortRelays = await MainActor.run {
            Array(damus_state.nostrNetwork.userRelayList.getBestEffortRelayList().relays.keys)
        }

        if !bestEffortRelays.isEmpty {
            let _ = await damus_state.nostrNetwork.ensureConnected(to: bestEffortRelays, timeout: .seconds(5))
            if let networkEvent = await fetchLatestEvent(filter: filter, timeout: .seconds(6), streamMode: .ndbAndNetworkParallel(networkOptimization: nil), targetRelays: bestEffortRelays) {
                #if DEBUG
                print("[DM-DEBUG] DM Relay List: Found network kind:10050 for \(target.npub)")
                #endif
                return NIP17.parseDMRelayList(event: networkEvent)
            }
        }

        // Step 3: Try relay hints from NIP-65
        let relayHints = await fetchNIP65RelayHints(for: target)
        guard !relayHints.isEmpty else {
            #if DEBUG
            print("[DM-DEBUG] DM Relay List: No kind:10050 found for \(target.npub)")
            #endif
            return []
        }

        await damus_state.nostrNetwork.acquireEphemeralRelays(relayHints)
        defer { Task { await damus_state.nostrNetwork.releaseEphemeralRelays(relayHints) } }

        let connectedRelays = await damus_state.nostrNetwork.ensureConnected(to: relayHints, timeout: .seconds(5))
        let targetRelays = connectedRelays.isEmpty ? nil : connectedRelays

        if let hintedEvent = await fetchLatestEvent(filter: filter, timeout: .seconds(6), streamMode: .ndbAndNetworkParallel(networkOptimization: nil), targetRelays: targetRelays) {
            #if DEBUG
            print("[DM-DEBUG] DM Relay List: Found hinted kind:10050 for \(target.npub)")
            #endif
            return NIP17.parseDMRelayList(event: hintedEvent)
        }

        #if DEBUG
        print("[DM-DEBUG] DM Relay List: No kind:10050 found for \(target.npub)")
        #endif
        return []
    }

    /// Fetches relay hints (kind 10002) to locate a user's DM relay list.
    private func fetchNIP65RelayHints(for target: Pubkey) async -> [RelayURL] {
        let filter = NostrFilter(kinds: [.relay_list], authors: [target])

        guard let relayListNote = await fetchLatestEvent(filter: filter, timeout: .seconds(6), streamMode: .ndbAndNetworkParallel(networkOptimization: nil), targetRelays: nil),
              let relayList = try? NIP65.RelayList(event: relayListNote) else {
            #if DEBUG
            print("[DM-DEBUG] DM Relay List: No relay hints found for \(target.npub)")
            #endif
            return []
        }

        let relays = Array(relayList.relays.keys)
        #if DEBUG
        print("[DM-DEBUG] DM Relay List: Found \(relays.count) relay hint(s) for \(target.npub)")
        #endif
        return relays
    }

    /// Finds the most recent replaceable event matching the filter within the given timeout.
    /// Works for any replaceable event kind (10050, 10002, etc.).
    private func fetchLatestEvent(
        filter: NostrFilter,
        timeout: Duration,
        streamMode: NostrNetworkManager.StreamMode,
        targetRelays: [RelayURL]?
    ) async -> NdbNote? {
        var latestEvent: NdbNote? = nil
        var latestTimestamp: UInt32 = 0

        for await lender in damus_state.nostrNetwork.reader.streamExistingEvents(
            filters: [filter],
            to: targetRelays,
            timeout: timeout,
            streamMode: streamMode
        ) {
            lender.justUseACopy { event in
                if event.created_at > latestTimestamp {
                    latestTimestamp = event.created_at
                    latestEvent = event
                }
            }
        }

        return latestEvent
    }

    /// Ensures our own DM relay list (kind 10050) is published
    private func ensureOwnDMRelayListPublished(sender: FullKeypair) async {
        // Check if we've already published
        let filter = NostrFilter(kinds: [.dm_relay_list], authors: [sender.pubkey])
        var hasExisting = false

        for await lender in damus_state.nostrNetwork.reader.streamExistingEvents(
            filters: [filter],
            timeout: .seconds(2)
        ) {
            lender.justUseACopy { _ in hasExisting = true }
            if hasExisting { break }
        }

        if hasExisting { return }

        // Get 2-3 of our relays to use as DM relays
        let relayList = await MainActor.run {
            damus_state.nostrNetwork.userRelayList.getBestEffortRelayList()
        }
        let ourRelays = Array(relayList.relays.keys.prefix(3))

        guard !ourRelays.isEmpty,
              let dmRelayList = NIP17.createDMRelayList(relays: ourRelays, keypair: sender.to_keypair()) else {
            return
        }

        // Publish our DM relay list
        await damus_state.nostrNetwork.postbox.send(dmRelayList)
    }

    /// Send a NIP-17 private direct message (kind 14 wrapped in kind 1059)
    /// - Returns: true if message was sent successfully, false if connection to relays failed
    @discardableResult
    private func send_nip17_message(content: String, sender: FullKeypair, toRelays: [RelayURL]?) async -> Bool {
        #if DEBUG
        print("[DM-DEBUG] NIP-17: Starting send to \(pubkey.npub)")
        #endif

        // Ensure our own DM relay list is published (for receiving replies)
        await ensureOwnDMRelayListPublished(sender: sender)

        // Create gift-wrapped message (one for recipient, one for sender)
        guard let (recipientWrap, senderWrap) = await NIP17.createMessage(
            content: content,
            to: pubkey,
            from: sender
        ) else {
            #if DEBUG
            print("[DM-DEBUG] NIP-17: Failed to create gift wraps, falling back to NIP-04")
            #endif
            await send_nip04_message(content: content)
            return true // NIP-04 fallback succeeded
        }

        #if DEBUG
        print("[DM-DEBUG] NIP-17: Created gift wraps - recipient:\(recipientWrap.id.hex().prefix(8)) sender:\(senderWrap.id.hex().prefix(8))")
        #endif

        // Send recipient's gift wrap to their DM relays (with proper ephemeral relay lifecycle)
        if let targetRelays = toRelays, !targetRelays.isEmpty {
            #if DEBUG
            print("[DM-DEBUG] NIP-17: Sending to recipient's DM relays: \(targetRelays.map { $0.absoluteString })")
            #endif
            let sentTo = await damus_state.nostrNetwork.sendToEphemeralRelays(recipientWrap, to: targetRelays)
            #if DEBUG
            print("[DM-DEBUG] NIP-17: Connected to \(sentTo.count)/\(targetRelays.count) relays")
            #endif

            if sentTo.isEmpty {
                #if DEBUG
                print("[DM-DEBUG] NIP-17: Failed to connect to any DM relays")
                #endif
                return false
            }
        } else {
            #if DEBUG
            print("[DM-DEBUG] NIP-17: Sending to our relays (fallback)")
            #endif
            await damus_state.nostrNetwork.postbox.send(recipientWrap)
        }

        dms.draft = ""

        // Send sender's self-wrap to our own DM relays for cross-device recovery
        // Fetch our own 10050 relay list (should exist after ensureOwnDMRelayListPublished)
        let senderDMRelays = await fetchDMRelayList(for: sender.pubkey)
        if !senderDMRelays.isEmpty {
            #if DEBUG
            print("[DM-DEBUG] NIP-17: Sending self-wrap to our DM relays: \(senderDMRelays.map { $0.absoluteString })")
            #endif
            let sentTo = await damus_state.nostrNetwork.sendToEphemeralRelays(senderWrap, to: senderDMRelays)
            #if DEBUG
            print("[DM-DEBUG] NIP-17: Self-wrap sent to \(sentTo.count)/\(senderDMRelays.count) DM relays")
            #endif
        } else {
            #if DEBUG
            print("[DM-DEBUG] NIP-17: No DM relays found for self, sending to regular relays")
            #endif
            await damus_state.nostrNetwork.postbox.send(senderWrap)
        }

        // Note: We don't create a local display event here because the self-wrap
        // will be received back from our DM relays very quickly. Creating a display
        // event with a different ID than the actual rumor causes duplicate messages.
        // The self-wrap flow ensures the message appears in the UI with the correct ID.

        end_editing()
        return true
    }

    /// Called when user confirms sending without DM relay list
    private func sendWithFallback() async {
        guard let content = pendingMessageContent,
              let sender = damus_state.keypair.to_full() else {
            return
        }
        pendingMessageContent = nil
        await send_nip17_message(content: content, sender: sender, toRelays: nil)
    }

    /// Send a NIP-04 direct message (legacy, kind 4)
    private func send_nip04_message(content: String) async {
        #if DEBUG
        print("[DM-DEBUG] NIP-04: Starting send to \(pubkey.npub)")
        #endif

        let tags = [["p", pubkey.hex()]]

        guard let dm = NIP04.create_dm(content, to_pk: pubkey, tags: tags, keypair: damus_state.keypair) else {
            #if DEBUG
            print("[DM-DEBUG] NIP-04: Failed to create DM")
            #endif
            return
        }

        #if DEBUG
        print("[DM-DEBUG] NIP-04: Created DM id:\(dm.id.hex().prefix(8))")
        #endif

        dms.draft = ""

        await damus_state.nostrNetwork.postbox.send(dm)
        #if DEBUG
        print("[DM-DEBUG] NIP-04: Sent to relays")
        #endif

        handle_incoming_dm(ev: dm, our_pubkey: damus_state.pubkey, dms: damus_state.dms, prev_events: NewEventsBits())
    }

    var body: some View {
        ZStack {
            Messages

            Text("Send a message to start the conversation...", comment: "Text prompt for user to send a message to the other user.")
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(((dms.events.count == 0) ? 1.0 : 0.0))
                .foregroundColor(.gray)
        }
        .navigationTitle(NSLocalizedString("DMs", comment: "Navigation title for DMs view, where DM is the English abbreviation for Direct Message."))
        .toolbar { Header }
        .alert(
            NSLocalizedString("No DM Relay List", comment: "Alert title when recipient has no kind 10050"),
            isPresented: $showRelayWarning
        ) {
            Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {
                pendingMessageContent = nil
                end_editing()
            }
            Button(NSLocalizedString("Send Anyway", comment: "Send message despite privacy warning")) {
                Task { await sendWithFallback() }
            }
        } message: {
            Text(NSLocalizedString(
                "This user hasn't published DM relay preferences. Sending to your connected relays may reduce privacy as metadata will be visible to those relays.",
                comment: "Privacy warning when recipient lacks kind 10050 DM relay list"
            ))
        }
        .onDisappear {
            if dms.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dms.draft = ""
            }
        }
    }
}

struct DMChatView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "hi", keypair: test_keypair, kind: 1, tags: [])!

        let model = DirectMessageModel(events: [ev], our_pubkey: test_pubkey, pubkey: test_pubkey)

        DMChatView(damus_state: test_damus_state, dms: model)
    }
}

extension View {
/// Layers the given views behind this ``TextEditor``.
    func textEditorBackground<V>(@ViewBuilder _ content: () -> V) -> some View where V : View {
        self
            .onAppear {
                UITextView.appearance().backgroundColor = .clear
            }
            .background(content())
    }
}
