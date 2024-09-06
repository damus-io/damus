//
//  LoadableThreadView.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-01-08.
//

import SwiftUI


/// A view model for `LoadableThreadView`
///
/// This takes a note reference, automatically tries to load it, and updates itself to reflect its current state
///
///
class LoadableThreadModel: ObservableObject {
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
            self.state = await executeLoadingLogic()
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
    
    private func executeLoadingLogic() async -> ThreadModelLoadingState {
        switch note_reference {
        case .note_id(let note_id):
            let res = await find_event(state: damus_state, query: .event(evid: note_id))
            guard let res, case .event(let ev) = res else { return .not_found }
            return .loaded(model: ThreadModel(event: ev, damus_state: damus_state))
        case .naddr(let naddr):
            guard let event = await naddrLookup(damus_state: damus_state, naddr: naddr) else { return .not_found }
            return .loaded(model: ThreadModel(event: event, damus_state: damus_state))
        }
    }
    
    enum ThreadModelLoadingState {
        case loading
        case loaded(model: ThreadModel)
        case not_found
    }
    
    enum NoteReference: Hashable {
        case note_id(NoteId)
        case naddr(NAddr)
    }
}

struct LoadableThreadView: View {
    let state: DamusState
    @StateObject var loadable_thread: LoadableThreadModel
    var loading: Bool {
        switch loadable_thread.state {
        case .loading:
            return true
        case .loaded, .not_found:
            return false
        }
    }
    
    init(state: DamusState, note_reference: LoadableThreadModel.NoteReference) {
        self.state = state
        self._loadable_thread = StateObject.init(wrappedValue: LoadableThreadModel(damus_state: state, note_reference: note_reference))
    }
    
    var body: some View {
        switch self.loadable_thread.state {
        case .loading:
            ScrollView(.vertical) {
                self.skeleton
                    .redacted(reason: loading ? .placeholder : [])
                    .shimmer(loading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(NSLocalizedString("Loading thread", comment: "Accessibility label for the thread view when it is loading"))
            }
        case .loaded(model: let thread_model):
            ChatroomThreadView(damus: state, thread: thread_model)
        case .not_found:
            self.not_found
        }
    }
    
    var not_found: some View {
        VStack(spacing: 6) {
            Image(systemName: "questionmark.app")
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            Text("Note not found", comment: "Heading for the thread view in a not found error state")
                .font(.title)
                .bold()
                .padding(.bottom, 10)
            Text("We were unable to find the note you were looking for.", comment: "Text for the thread view when it is unable to find the note the user is looking for")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .accessibilityHidden(true)
                    Text("Advice", comment: "Heading for some advice text to help the user with an error")
                        .font(.headline)
                }
                Text("Try checking the link again, your internet connection, whether you need to connect to a specific relay to access this content.", comment: "Tips on what to do if a note cannot be found.")
            }
            .padding()
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(10)
            .padding(.vertical, 30)
        }
        .padding()
    }
    
    // MARK: Skeleton views
    // Implementation notes
    // - No localization is needed because the text will be redacted
    // - No accessibility label is needed because these will be summarized into a single accessibility label at the top-level view. See `body` in this struct
    
    var skeleton: some View {
        VStack(alignment: .leading, spacing: 40) {
            self.skeleton_selected_event
            self.skeleton_chat_event(message: "Nice! Have you tried Damus?", right: false)
            self.skeleton_chat_event(message: "Yes, it's awesome.", right: true)
            Spacer()
        }
        .padding()
    }
    
    func skeleton_chat_event(message: String, right: Bool) -> some View {
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
                    Text(message)
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
    
    var skeleton_selected_event: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .frame(width: 50, height: 50)
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("Satoshi Nakamoto")
                    .bold()
            }
            Text("Nostr is the super app. Because it’s actually an ecosystem of apps, all of which make each other better. People haven’t grasped that yet. They will when it’s more accessible and onboarding is more straightforward and intuitive.")
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
    
    var skeleton_chat_user_avatar: some View {
        Circle()
            .fill(.secondary.opacity(0.5))
            .frame(width: 35, height: 35)
            .padding(.bottom, -21)
    }
    
    var skeleton_action_item: some View {
        Circle()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 25, height: 25)
    }
}

#Preview("Loadable") {
    LoadableThreadView(state: test_damus_state, note_reference: .note_id(test_thread_note_1.id))
}
