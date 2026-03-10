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
    @State private var rotation = RotationState()

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
                            .onAppear { rotation.trackAppeared(ev.id) }
                            .onDisappear { rotation.trackDisappeared(ev.id) }
                    }
                    EndBlock(height: 1)
                }
                .padding(.horizontal)
                .background(
                    ScrollViewRotationHandler(
                        onWillRotate: {
                            guard let target = rotation.scrollTarget(in: dms.events) else { return }
                            rotation.freeze(targetID: target.id)
                        },
                        onScrollCorrection: {
                            guard let targetID = rotation.targetID else { return }
                            DispatchQueue.main.async {
                                scroller.scrollTo(targetID, anchor: .bottom)
                            }
                        },
                        onDidStabilize: {
                            rotation.unfreeze()
                        }
                    )
                )

            }
            .dismissKeyboardOnTap()
            .onAppear {
                scroll_to_end(scroller)
            }.onChange(of: dms.events.count) { _ in
                scroll_to_end(scroller, animated: true)
            }
            
            Footer
                .onReceive(keyboardPublisher) { visible in
                    guard visible else {
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scroll_to_end(scroller, animated: true)
                    }
                }
        }
        .padding(.bottom, isTextFieldFocused ? 0 : tabHeight)
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
        return NavigationLink(value: Route.ProfileByKey(pubkey: pubkey)) {
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

    var Footer: some View {
    
        HStack(spacing: 0) {
            InputField

            if !dms.draft.isEmpty {
                Button(
                    role: .none,
                    action: {
                        Task { await send_message() }
                    }
                ) {
                    Label("", image: "send")
                        .font(.title)
                }
            }
        }

        /*
        Text(dms.draft).opacity(0).padding(.all, 8)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 70, maxHeight: 150, alignment: .bottom)
         */
    }

    func send_message() async {
        let tags = [["p", pubkey.hex()]]
        guard let post_blocks = parse_post_blocks(content: dms.draft)?.blocks else {
            return
        }
        let content = post_blocks.map({ pb in pb.asString }).joined(separator: "")

        guard let dm = NIP04.create_dm(content, to_pk: pubkey, tags: tags, keypair: damus_state.keypair) else {
            print("error creating dm")
            return
        }

        dms.draft = ""

        await damus_state.nostrNetwork.postbox.send(dm)
        
        handle_incoming_dm(ev: dm, our_pubkey: damus_state.pubkey, dms: damus_state.dms, prev_events: NewEventsBits())

        end_editing()
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
        .onDisappear {
            if dms.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dms.draft = ""
            }
        }
    }
}

// MARK: - Rotation state

private struct RotationState {
    private var visibleMessageIDs: Set<NoteId> = []
    private(set) var isActive: Bool = false
    private(set) var targetID: NoteId? = nil

    mutating func trackAppeared(_ id: NoteId) {
        guard !isActive else { return }
        visibleMessageIDs.insert(id)
    }

    mutating func trackDisappeared(_ id: NoteId) {
        guard !isActive else { return }
        visibleMessageIDs.remove(id)
    }

    /// Returns the last visible message to use as scroll anchor after rotation.
    func scrollTarget(in events: [NostrEvent]) -> NostrEvent? {
        return events.last { visibleMessageIDs.contains($0.id) }
    }

    mutating func freeze(targetID: NoteId) {
        isActive = true
        self.targetID = targetID
    }

    mutating func unfreeze() {
        isActive = false
        targetID = nil
    }
}

// MARK: - Scroll position preservation during rotation
//
// LazyVStack aggressively recycles views during rotation, which corrupts
// SwiftUI's scroll position and any onAppear/onDisappear-based tracking.
// We freeze the visible-ID set during rotation to preserve the scroll target.
//
// UIViewControllerRepresentable is required because viewWillTransition(to:with:)
// fires BEFORE layout changes begin — the only reliable time to capture the
// visible set. UIDevice.orientationDidChangeNotification fires too late.
//
// KVO on the underlying UIScrollView's contentSize reactively corrects
// the scroll position as layout settles after rotation.

struct ScrollViewRotationHandler: UIViewControllerRepresentable {
    var onWillRotate: () -> Void
    var onScrollCorrection: () -> Void
    var onDidStabilize: () -> Void

    func makeUIViewController(context: Context) -> ScrollViewRotationVC {
        let vc = ScrollViewRotationVC()
        vc.onWillRotate = onWillRotate
        vc.onScrollCorrection = onScrollCorrection
        vc.onDidStabilize = onDidStabilize
        return vc
    }

    func updateUIViewController(_ vc: ScrollViewRotationVC, context: Context) {
        vc.onWillRotate = onWillRotate
        vc.onScrollCorrection = onScrollCorrection
        vc.onDidStabilize = onDidStabilize
    }

    class ScrollViewRotationVC: UIViewController {
        var onWillRotate: (() -> Void)?
        var onScrollCorrection: (() -> Void)?
        var onDidStabilize: (() -> Void)?

        private weak var scrollView: UIScrollView?
        private var contentSizeObservation: NSKeyValueObservation?
        private var cleanupWorkItem: DispatchWorkItem?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            scrollView = findParentScrollView()
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            guard scrollView != nil else { return }

            onWillRotate?()
            onScrollCorrection?()

            // Reactively correct scroll position each time content layout changes
            contentSizeObservation = scrollView?.observe(\.contentSize) { [weak self] _, _ in
                guard let self else { return }
                self.onScrollCorrection?()
                self.scheduleCleanup()
            }

            scheduleCleanup()
        }

        /// Stop observing and unfreeze once contentSize has stabilized (no KVO
        /// fires before the next run-loop iteration).
        private func scheduleCleanup() {
            cleanupWorkItem?.cancel()
            cleanupWorkItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.contentSizeObservation?.invalidate()
                self.contentSizeObservation = nil
                self.onDidStabilize?()
            }
            DispatchQueue.main.async(execute: cleanupWorkItem!)
        }

        private func findParentScrollView() -> UIScrollView? {
            var current: UIView? = view
            while let v = current {
                if let sv = v as? UIScrollView { return sv }
                current = v.superview
            }
            return nil
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

