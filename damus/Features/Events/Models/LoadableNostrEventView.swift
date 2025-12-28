//
//  LoadableNostrEventView.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-01-08.
//

import SwiftUI


/// A view model for `LoadableNostrEventView`
///
/// This takes a nostr event reference, automatically tries to load it, and updates itself to reflect its current state
///
/// ## Implementation notes
///
/// - This is on the main actor because `ObservableObjects` with `Published` properties should be on the main actor for thread-safety.
///
@MainActor
class LoadableNostrEventViewModel: ObservableObject {
    let damus_state: DamusState
    let note_reference: NoteReference
    @Published var state: ThreadModelLoadingState = .loading
    /// The time period after which it will give up loading the view.
    /// Written in nanoseconds
    let TIMEOUT: UInt64 = 10 * 1_000_000_000    // 10 seconds
    
    init(damus_state: DamusState, note_reference: NoteReference) {
        self.damus_state = damus_state
        self.note_reference = note_reference
        Task { await self.load() }
    }
    
    func load() async {
        // Start the loading process in a separate task to manage the timeout independently.
        let loadTask = Task { @MainActor in
            self.state = await executeLoadingLogic(note_reference: self.note_reference)
        }

        // Setup a timer to cancel the load after the timeout period
        let timeoutTask = Task { @MainActor in
            try await Task.sleep(nanoseconds: TIMEOUT)
            loadTask.cancel() // This sends a cancellation signal to the load task.
            self.state = .not_found
        }
        
        await loadTask.value
        timeoutTask.cancel() // Cancel the timeout task if loading finishes earlier.
    }
    
    /// Asynchronously find an event from NostrDB or from the network (if not available on NostrDB)
    private func loadEvent(noteId: NoteId, relays: [RelayURL]) async -> NostrEvent? {
        let targetRelays = relays.isEmpty ? nil : relays
        let res = await damus_state.nostrNetwork.reader.findEvent(query: .event(evid: noteId, find_from: targetRelays))
        guard let res, case .event(let ev) = res else { return nil }
        return ev
    }
    
    /// Gets the note reference and tries to load it, outputting a new state for this view model.
    private func executeLoadingLogic(note_reference: NoteReference) async -> ThreadModelLoadingState {
        switch note_reference {
        case .note_id(let note_id, let relays):
            guard let ev = await self.loadEvent(noteId: note_id, relays: relays) else { return .not_found }
            guard let known_kind = ev.known_kind else { return .unknown_or_unsupported_kind }
            switch known_kind {
            case .text, .highlight:
                return .loaded(route: Route.Thread(thread: ThreadModel(event: ev, damus_state: damus_state)))
            case .dm:
                let dm_model = damus_state.dms.lookup_or_create(ev.pubkey)
                return .loaded(route: Route.DMChat(dms: dm_model))
            case .like:
                guard let first_referenced_note_id = ev.referenced_ids.first else { return .not_found }
                return await self.executeLoadingLogic(note_reference: .note_id(first_referenced_note_id, relays: []))
            case .zap, .zap_request:
                guard let zap = await get_zap(from: ev, state: damus_state) else { return .not_found }
                return .loaded(route: Route.Zaps(target: zap.target))
            case .contacts, .metadata, .delete, .boost, .chat, .mute_list, .list_deprecated, .draft, .longform, .nwc_request, .nwc_response, .http_auth, .status, .relay_list, .follow_list, .interest_list, .contact_card, .live, .live_chat:
                return .unknown_or_unsupported_kind
            }
        case .naddr(let naddr):
            let targetRelays = naddr.relays.isEmpty ? nil : naddr.relays
            guard let event = await damus_state.nostrNetwork.reader.lookup(naddr: naddr, to: targetRelays) else { return .not_found }
            return .loaded(route: Route.Thread(thread: ThreadModel(event: event, damus_state: damus_state)))
        }
    }
    
    enum ThreadModelLoadingState {
        case loading
        case loaded(route: Route)
        case not_found
        case unknown_or_unsupported_kind
    }
    
    enum NoteReference: Hashable {
        case note_id(NoteId, relays: [RelayURL])
        case naddr(NAddr)
    }
}

/// A view for a Nostr event that has not been loaded yet.
/// This takes a Nostr event reference and loads it, while providing nice loading UX and graceful error handling.
struct LoadableNostrEventView: View {
    let state: DamusState
    @StateObject var loadableModel: LoadableNostrEventViewModel
    var loading: Bool {
        switch loadableModel.state {
        case .loading:
            return true
        case .loaded, .not_found, .unknown_or_unsupported_kind:
            return false
        }
    }
    
    init(state: DamusState, note_reference: LoadableNostrEventViewModel.NoteReference) {
        self.state = state
        self._loadableModel = StateObject.init(wrappedValue: LoadableNostrEventViewModel(damus_state: state, note_reference: note_reference))
    }
    
    var body: some View {
        switch self.loadableModel.state {
        case .loading:
            ScrollView(.vertical) {
                self.skeleton
                    .redacted(reason: loading ? .placeholder : [])
                    .shimmer(loading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(NSLocalizedString("Loading thread", comment: "Accessibility label for the thread view when it is loading"))
            }
        case .loaded(route: let route):
            route.view(navigationCoordinator: state.nav, damusState: state)
        case .not_found:
            self.not_found
        case .unknown_or_unsupported_kind:
            self.unknown_or_unsupported_kind
        }
    }
    
    var not_found: some View {
        SomethingWrong(
            imageSystemName: "questionmark.app",
            heading: NSLocalizedString("Note not found", comment: "Heading for the thread view in a not found error state."),
            description: NSLocalizedString("We were unable to find the note you were looking for.", comment: "Text for the thread view when it is unable to find the note the user is looking for"),
            advice: NSLocalizedString("Try checking the link again, your internet connection, or contact the person who provided you the link for help.", comment: "Tips on what to do if a note cannot be found.")
        )
    }
    
    var unknown_or_unsupported_kind: some View {
        SomethingWrong(
            imageSystemName: "questionmark.app",
            heading: NSLocalizedString("Can’t display note", comment: "User-visible heading for an error message indicating a note has an unknown kind or is unsupported for viewing."),
            description: NSLocalizedString("We do not yet support viewing this type of content.", comment: "User-visible description of an error indicating a note has an unknown kind or is unsupported for viewing."),
            advice: NSLocalizedString("Please try opening this content on another Nostr app that supports this type of content.", comment: "User-visible advice on what to do if they see the error indicating a note has an unknown kind or is unsupported for viewing.")
        )
    }
    
    // MARK: Skeleton views
    // Implementation notes
    // - No localization is needed because the text will be redacted
    // - No accessibility label is needed because these will be summarized into a single accessibility label at the top-level view. See `body` in this struct
    
    var skeleton: some View {
        VStack(alignment: .leading, spacing: 40) {
            Self.skeleton_selected_event
            Self.skeleton_chat_event(message: "Nice! Have you tried Damus?", right: false)
            Self.skeleton_chat_event(message: "Yes, it's awesome.", right: true)
            Spacer()
        }
        .padding()
    }
    
    static func skeleton_chat_event(message: String, right: Bool) -> some View {
        HStack(alignment: .center) {
            if !right {
                self.skeleton_chat_user_avatar
            }
            else {
                Spacer()
            }
            ChatBubble(
                direction: right ? .right : .left,
                stroke_content: Color.accentColor.opacity(0),
                stroke_style: .init(lineWidth: 4),
                background_style: Color.secondary.opacity(0.5),
                content: {
                    Text(verbatim: message)
                        .padding()
                }
            )
            if right {
                self.skeleton_chat_user_avatar
            }
            else {
                Spacer()
            }
        }
    }
    
    static var skeleton_selected_event: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .frame(width: 50, height: 50)
                    .foregroundStyle(.secondary.opacity(0.5))
                Text(verbatim: "Satoshi Nakamoto")
                    .bold()
            }
            Text(verbatim: "Nostr is the super app. Because it’s actually an ecosystem of apps, all of which make each other better. People haven’t grasped that yet. They will when it’s more accessible and onboarding is more straightforward and intuitive.")
            HStack {
                self.skeleton_action_item
                Spacer()
                self.skeleton_action_item
                Spacer()
                self.skeleton_action_item
                Spacer()
                self.skeleton_action_item
            }
        }
    }
    
    static var skeleton_chat_user_avatar: some View {
        Circle()
            .fill(.secondary.opacity(0.5))
            .frame(width: 35, height: 35)
            .padding(.bottom, -21)
    }
    
    static var skeleton_action_item: some View {
        Circle()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 25, height: 25)
    }
}

extension LoadableNostrEventView {
    struct SomethingWrong: View {
        let imageSystemName: String
        let heading: String
        let description: String
        let advice: String
        
        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: imageSystemName)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                Text(heading)
                    .font(.title)
                    .bold()
                    .padding(.bottom, 10)
                Text(description)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .accessibilityHidden(true)
                        Text("Advice", comment: "Heading for some advice text to help the user with an error")
                            .font(.headline)
                    }
                    Text(advice)
                }
                .padding()
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(10)
                .padding(.vertical, 30)
            }
            .padding()
        }
    }
}

#Preview("Loadable") {
    LoadableNostrEventView(state: test_damus_state, note_reference: .note_id(test_thread_note_1.id, relays: []))
}
