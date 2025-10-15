//
//  RelayDetailView.swift
//  damus
//
//  Created by Joel Klabo on 2/1/23.
//

import SwiftUI
import Combine

struct RelayDetailView: View {
    let state: DamusState
    let relay: RelayURL
    let nip11: RelayMetadata?

    @StateObject private var previewModel: RelayPreviewModel

    @Environment(\.dismiss) var dismiss

    init(state: DamusState, relay: RelayURL, nip11: RelayMetadata?) {
        self.state = state
        self.relay = relay
        self.nip11 = nip11
        
        _previewModel = StateObject(wrappedValue: RelayPreviewModel(state: state, relay: relay))
    }
    
    func check_connection() -> Bool {
        return state.nostrNetwork.userRelayList.getUserCurrentRelayList()?.relays.keys.contains(self.relay) == true
    }

    @ViewBuilder
    private var connectionControl: some View {
        if state.keypair.to_full() != nil {
            let isConnected = check_connection()

            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    if isConnected {
                        removeRelay()
                    } else {
                        connectRelay()
                    }
                } label: {
                    Text(isConnected ? NSLocalizedString("Disconnect", comment: "Button to disconnect from the relay preview.") : NSLocalizedString("Add Relay", comment: "Button to add the relay after previewing."))
                        .font(.footnote.weight(.semibold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(isConnected ? Color(.systemGray5) : Color.accentColor)
                        .foregroundColor(isConnected ? Color.primary : Color.white)
                        .clipShape(Capsule())
                }
                .accessibilityIdentifier("relay-preview-action-button")

                if isConnected {
                    Label {
                        Text(NSLocalizedString("In your relay list", comment: "Subtle status text indicating the relay is already in the user's list"))
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .imageScale(.small)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("relay-preview-connected-indicator")
                }
            }
        }
    }

    private var previewHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                RelayPicView(relay: relay, icon: nip11?.icon, size: 72, highlight: .none, disable_animation: false)

                VStack(alignment: .leading, spacing: 4) {
                    Text(nip11?.name ?? relay.absoluteString)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)

                    Text(relay.absoluteString)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                connectionControl
            }

            if let description = nip11?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            } else {
                Text(NSLocalizedString("Glance at what’s happening before you decide to connect.", comment: "Relay preview subtitle explaining the preview experience."))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }


    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    previewHeader
                    RelayPreviewSectionView(state: state, model: previewModel)
                }
                .padding(.horizontal)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
        .navigationTitle(NSLocalizedString("Relay Preview", comment: "Navigation title for the relay preview experience"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: BackNav())
        .onAppear {
            previewModel.start()
        }
        .onDisappear {
            previewModel.stop()
        }
        .toolbar {
            if let relay_connection {
                RelayStatusView(connection: relay_connection)
            }
        }
    }

    private var relay_object: RelayPool.Relay? {
        state.nostrNetwork.pool.get_relay(relay)
    }

    private var relay_connection: RelayConnection? {
        relay_object?.connection
    }
    
    func removeRelay() {
        do {
            try state.nostrNetwork.userRelayList.remove(relayURL: self.relay)
            dismiss()
        }
        catch {
            present_sheet(.error(error.humanReadableError))
        }
    }
    
    func connectRelay() {
        do {
            try state.nostrNetwork.userRelayList.insert(relay: NIP65.RelayList.RelayItem(url: relay, rwConfiguration: .readWrite))
            dismiss()
        }
        catch {
            present_sheet(.error(error.humanReadableError))
        }
    }
}

@MainActor
final class RelayPreviewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case loaded
        case empty
        case error(String)
    }

    struct KnownAuthor: Identifiable {
        enum Relationship {
            case you
            case friend
            case friendOfFriend
        }

        let pubkey: Pubkey
        let displayName: String
        let relationship: Relationship

        var id: String {
            "\(relationshipTag)-\(pubkey.hex())"
        }

        private var relationshipTag: String {
            switch relationship {
            case .you:
                return "self"
            case .friend:
                return "friend"
            case .friendOfFriend:
                return "friendOfFriend"
            }
        }

        var relationshipPriority: Int {
            switch relationship {
            case .you: return 0
            case .friend: return 1
            case .friendOfFriend: return 2
            }
        }
    }

    @Published private(set) var loadingState: LoadingState = .idle
    @Published private(set) var sampleEvents: [NostrEvent] = []
    @Published private(set) var knownAuthors: [KnownAuthor] = []

    private let state: DamusState
    private let relay: RelayURL
    private let subscriptionId = "relay-preview-" + UUID().uuidString
    private var observedNoteIds: Set<NoteId> = []
    private var hasAddedEphemeralRelay = false
    private var isActive = false
    private var hasReceivedTerminalEvent = false

    private let sampleLimit = 32
    private let lookbackWindow: TimeInterval = 60 * 60 * 24

    init(state: DamusState, relay: RelayURL) {
        self.state = state
        self.relay = relay
    }

    deinit {
        guard hasAddedEphemeralRelay else { return }
        let state = state
        let relay = relay
        Task { @MainActor in
            let pool = state.nostrNetwork.pool
            if let relayObject = pool.get_relay(relay), relayObject.descriptor.ephemeral {
                pool.remove_relay(relay)
            }
        }
    }

    var directConnections: [KnownAuthor] {
        knownAuthors.filter { $0.relationship == .you || $0.relationship == .friend }
    }

    var extendedConnections: [KnownAuthor] {
        knownAuthors.filter { $0.relationship == .friendOfFriend }
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        hasReceivedTerminalEvent = false
        observedNoteIds.removeAll()
        sampleEvents.removeAll()
        knownAuthors.removeAll()
        loadingState = .loading

        guard ensureRelayConnection() else {
            isActive = false
            return
        }

        subscribe()
    }

    func stop() {
        if isActive {
            unsubscribe()
        } else {
            cleanupRelayIfNeeded()
        }
    }

    private func ensureRelayConnection() -> Bool {
        let pool = state.nostrNetwork.pool
        if let existing = pool.get_relay(relay) {
            if !existing.connection.isConnected && !existing.connection.isConnecting {
                pool.connect(to: [relay])
            }
            return true
        }

        do {
            let descriptor = RelayPool.RelayDescriptor(url: relay, info: .read, variant: .ephemeral)
            try pool.add_relay(descriptor)
            hasAddedEphemeralRelay = true
            pool.connect(to: [relay])
            return true
        } catch {
            loadingState = .error(NSLocalizedString("We couldn't preview this relay right now.", comment: "Relay preview error message when relay connection fails"))
            return false
        }
    }

    private func subscribe() {
        let pool = state.nostrNetwork.pool
        pool.register_handler(sub_id: subscriptionId) { [weak self] relayURL, event in
            guard let self else { return }
            Task { @MainActor in
                self.handleConnectionEvent(relayURL: relayURL, event: event)
            }
        }
        let request = NostrRequest.subscribe(NostrSubscribe(filters: [makeFilter()], sub_id: subscriptionId))
        pool.send(request, to: [relay], skip_ephemeral: false)
    }

    private func handleConnectionEvent(relayURL: RelayURL, event: NostrConnectionEvent) {
        guard isActive else { return }

        switch event {
        case .ws_connection_event(let wsEvent):
            if case .error = wsEvent {
                if case .loading = loadingState {
                    loadingState = .error(NSLocalizedString("We lost the preview connection to this relay.", comment: "Relay preview connection lost error message"))
                }
                unsubscribe()
            }
        case .nostr_event(let response):
            guard response.subid == subscriptionId else { return }
            switch response {
            case .event(_, let nostrEvent):
                ingest(event: nostrEvent)
            case .eose:
                hasReceivedTerminalEvent = true
                finalizeLoadingIfNeeded()
            case .notice:
                break
            case .ok:
                break
            case .auth:
                break
            }
        }
    }

    private func ingest(event: NostrEvent) {
        guard isActive else { return }
        guard event.known_kind == .text else { return }
        guard observedNoteIds.insert(event.id).inserted else { return }

        sampleEvents.append(event)
        sampleEvents.sort { $0.created_at > $1.created_at }
        preload_events(state: state, events: [event])
        recomputeDerivedData()

        if sampleEvents.count >= sampleLimit {
            finalizeLoadingIfNeeded()
        }
    }

    private func finalizeLoadingIfNeeded() {
        guard isActive else { return }
        if sampleEvents.count >= sampleLimit || hasReceivedTerminalEvent {
            loadingState = sampleEvents.isEmpty ? .empty : .loaded
            unsubscribe()
        }
    }

    private func unsubscribe() {
        let pool = state.nostrNetwork.pool
        pool.send(.unsubscribe(subscriptionId), to: [relay], skip_ephemeral: false)
        pool.remove_handler(sub_id: subscriptionId)
        cleanupRelayIfNeeded()
        isActive = false
    }

    private func cleanupRelayIfNeeded() {
        guard hasAddedEphemeralRelay else { return }
        let pool = state.nostrNetwork.pool
        if let relayObject = pool.get_relay(relay), relayObject.descriptor.ephemeral {
            pool.remove_relay(relay)
        }
        hasAddedEphemeralRelay = false
    }

    private func makeFilter() -> NostrFilter {
        let since = max(0, Int(Date().addingTimeInterval(-lookbackWindow).timeIntervalSince1970))
        return NostrFilter(kinds: [.text], since: UInt32(since), limit: UInt32(sampleLimit * 3))
    }

    private func recomputeDerivedData() {
        var seenAuthors = Set<Pubkey>()
        var authors: [KnownAuthor] = []

        for event in sampleEvents {
            let pubkey = event.pubkey
            if seenAuthors.contains(pubkey) {
                continue
            }
            seenAuthors.insert(pubkey)

            let relationship: KnownAuthor.Relationship
            if pubkey == state.pubkey {
                relationship = .you
            } else if state.contacts.is_friend(pubkey) {
                relationship = .friend
            } else if state.contacts.is_friend_of_friend(pubkey) {
                relationship = .friendOfFriend
            } else {
                continue
            }

            let display = displayName(for: pubkey)
            authors.append(KnownAuthor(pubkey: pubkey, displayName: display, relationship: relationship))
        }

        knownAuthors = authors.sorted { lhs, rhs in
            if lhs.relationshipPriority != rhs.relationshipPriority {
                return lhs.relationshipPriority < rhs.relationshipPriority
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func displayName(for pubkey: Pubkey) -> String {

        if let txn = state.profiles.lookup(id: pubkey, txn_name: "relay-preview"),
           let profile = txn.unsafeUnownedValue {
            let display = Profile.displayName(profile: profile, pubkey: pubkey)
            let preferred = display.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preferred.isEmpty {
                return preferred
            }
            let username = display.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !username.isEmpty {
                return username
            }
        }

        return abbrev_identifier(pubkey.hex())
    }
}

struct RelayPreviewSectionView: View {
    let state: DamusState
    @ObservedObject var model: RelayPreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("See what’s happening here", comment: "Headline for relay preview section"))
                .font(.headline)

            statusView
            
            if hasTrustIndicators {
                RelayPreviewTrustIndicator(
                    state: state,
                    extendedConnections: model.extendedConnections
                )
            }

            if !sampleEventsPreview.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(sampleEventsPreview.enumerated()), id: \.element.id) { index, event in
                        EventView(damus: state, event: event, options: [.embedded, .no_translate, .no_show_more])
                        if index != sampleEventsPreview.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            // Intentionally omit additional people list below the preview feed to keep focus on the relay timeline.
        }
    }

    private var sampleEventsPreview: [NostrEvent] {
        Array(model.sampleEvents.prefix(10))
    }

    private var hasTrustIndicators: Bool {
        !model.extendedConnections.isEmpty
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.loadingState {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text(NSLocalizedString("Fetching a glimpse from this relay…", comment: "Relay preview loading message"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        case .loaded:
            if sampleEventsPreview.isEmpty && !hasTrustIndicators {
                Text(NSLocalizedString("No recent notes were returned from this relay.", comment: "Relay preview empty state message"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        case .empty:
            Text(NSLocalizedString("No recent notes were returned from this relay.", comment: "Relay preview empty state message"))
                .font(.footnote)
                .foregroundColor(.secondary)
        case .error(let message):
            Text(message)
                .font(.footnote)
                .foregroundColor(.red)
        }
    }
}

struct RelayPreviewTrustIndicator: View {
    let state: DamusState
    let extendedConnections: [RelayPreviewModel.KnownAuthor]

    private var displayedPubkeys: [Pubkey] {
        Array(extendedConnections.map { $0.pubkey }.prefix(24))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Who’s posting here", comment: "Relay preview section title for web-of-trust indicator"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !displayedPubkeys.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(displayedPubkeys, id: \.self) { pubkey in
                            ProfilePicView(
                                pubkey: pubkey,
                                size: 36,
                                highlight: .none,
                                profiles: state.profiles,
                                disable_animation: state.settings.disable_animation
                            )
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                notify(.present_sheet(Sheets.profile_action(pubkey)))
                            }
                            .onLongPressGesture(minimumDuration: 0.1) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct RelayDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let admission = Admission(amount: 1000000, unit: "msats")
        let sub = Subscription(amount: 5000000, unit: "msats", period: 2592000)
        let pub = Publication(kinds: [4], amount: 100, unit: "msats")
        let fees = Fees(admission: [admission], subscription: [sub], publication: [pub])
        let metadata = RelayMetadata(name: "name", description: "Relay description", pubkey: test_pubkey, contact: "contact@mail.com", supported_nips: [1,2,3], software: "software", version: "version", limitation: Limitations.empty, payments_url: "https://jb55.com", icon: "", fees: fees)
        RelayDetailView(state: test_damus_state, relay: RelayURL("wss://relay.damus.io")!, nip11: metadata)
    }
}
