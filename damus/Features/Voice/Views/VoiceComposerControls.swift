import SwiftUI
import UIKit

/// Readable transcript review replaces the normal tappable text editor in Audio mode.
struct VoiceTranscriptReview: View {
    @ObservedObject var model: VoiceComposerModel
    @State private var settingsPresented = false
    @State private var confirmDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                ProfilePicView(pubkey: model.state.pubkey, size: PFP_SIZE, highlight: .none,
                               profiles: model.state.profiles, disable_animation: model.state.settings.disable_animation,
                               damusState: model.state)
                Text(model.status).font(.subheadline).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("voice.status")
                Button { settingsPresented = true } label: {
                    Image(systemName: "gearshape").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Voice recording settings")
                .disabled(model.busy)
            }
            if let take = model.draft?.takeID {
                VoiceRecordingPreview(model: model, takeID: take).id(take)
            }
            if let text = model.draft?.transcript {
                Text(text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("voice.transcript")
            } else {
                Text("Your on-device transcript will appear here after recording.")
                    .foregroundColor(.secondary)
            }
            VoiceAttachmentReview(model: model)
            if model.draft?.takeID != nil || model.draft?.pendingTakeID != nil {
                HStack {
                    if model.draft?.takeID != nil && model.draft?.transcript == nil && model.draft?.eventJSON == nil {
                        Button("Retry transcription") { model.retryTranscription() }
                    }
                    Spacer()
                    if model.draft?.eventJSON == nil {
                        Button(role: .destructive) { confirmDiscard = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel("Discard recording")
                    }
                }
                .disabled(model.busy)
            }
            if let error = model.error {
                Text(error).foregroundColor(.red).font(.callout).accessibilityIdentifier("voice.error")
            }
            Button("Voice uploads: nostr.build") { settingsPresented = true }
                .font(.caption).disabled(model.busy)
            if let results = model.draft?.relayResults, !results.isEmpty {
                DisclosureGroup("Delivery details") {
                    ForEach(results.keys.sorted(), id: \.self) { relay in
                        VStack(alignment: .leading) { Text(relay).font(.caption); Text(results[relay] ?? "").font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
        }
        .sheet(isPresented: $settingsPresented) { VoiceRecordingSettings(model: model) }
        .confirmationDialog("Are you sure you want to discard this audio post before posting it?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Yes, discard", role: .destructive) { model.discard() }
            Button("Keep editing", role: .cancel) {}
        }
    }
}

/// The draft player uses local bytes and the shared feed controls, above the transcription.
private struct VoiceRecordingPreview: View {
    @ObservedObject var model: VoiceComposerModel
    let takeID: UUID
    @ObservedObject private var playback = VoicePlayback.shared

    private var owns: Bool { playback.owner == takeID.uuidString }

    var body: some View {
        VoicePlayerControls(
            position: Binding(get: { owns ? playback.position : model.previewPosition }, set: model.seekPreview),
            duration: owns ? playback.duration : model.draft?.duration,
            ownsPlayback: owns, isPlaying: owns && playback.isPlaying,
            loading: model.previewLoading, playbackRate: playback.playbackRate,
            toggle: model.preview, cycleRate: playback.cyclePlaybackRate,
            onEditingChanged: { editing in
                if !editing && !owns && !model.previewLoading { model.preview() }
            })
        .disabled(model.busy)
        .onDisappear(perform: model.stopPreview)
    }
}

/// The compose button's gradient style with continuous touch ownership for slide-to-trash.
struct VoiceRecordingBar: View {
    @ObservedObject var model: VoiceComposerModel
    @State private var overTrash = false
    @State private var pressing = false
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recording: Bool { model.phase == .recording || model.phase == .requestingPermission }
    private var elapsed: String { Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)) }

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    VoiceAttachmentButtons(model: model)
                        .opacity(recording ? 0 : 1)
                        .allowsHitTesting(!recording)
                    microphone
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                caption
            }
            .padding(.top, 6)
        }
        .padding(.bottom, 12)
    }

    private var microphone: some View {
        ZStack {
            if model.phase == .recording { pulse }
            ZStack {
                Circle().fill(LINEAR_GRADIENT)
                Circle().fill(DamusColors.danger).opacity(recording ? 1 : 0)
            }
            .shadow(color: (recording ? DamusColors.danger : DamusColors.purple).opacity(0.38), radius: 8, x: 0, y: 6)
            Image(systemName: recording ? "waveform" : "mic.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 58, height: 58)
        .scaleEffect(pressing ? 0.95 : 1)
        .animation(.easeOut(duration: 0.15), value: pressing)
        .animation(.easeInOut(duration: 0.2), value: recording)
        // Keep the tested touch coordinates fixed while only the button artwork animates.
        .frame(width: 76, height: 76)
        .overlay {
            VoiceRecordingTouchArea(
                onBegin: { pressing = true; overTrash = false; model.beginHold() },
                onHover: { value in
                    if value && !overTrash { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    overTrash = value
                    model.updateTrashHover(value)
                },
                onRelease: { result in
                    pressing = false
                    overTrash = false
                    model.releaseHold(discard: result == .discard)
                })
                .allowsHitTesting((!model.busy || recording) && model.draft?.eventJSON == nil)
        }
        .overlay {
            if recording {
                Image(systemName: "trash.fill")
                    .font(.system(size: 24))
                    .foregroundColor(overTrash ? .white : DamusColors.danger)
                    .frame(width: 60, height: 60)
                    .background(overTrash ? DamusColors.danger : DamusColors.danger.opacity(0.12), in: Circle())
                    .scaleEffect(overTrash ? 1.1 : 1)
                    .offset(x: -96)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(recording ? "Stop recording" : "Start voice recording")
        .accessibilityHint("Hold to record. Release to transcribe, or slide left onto the trash to discard. Press Post separately.")
        .accessibilityIdentifier("voice.microphone")
        .accessibilityAction {
            if recording { model.releaseHold() } else { model.beginHold() }
        }
        .accessibilityAction(named: Text("Discard recording")) { model.cancelHold() }
        .onChange(of: recording) { active in
            if !active { pressing = false; overTrash = false }
        }
        .opacity(model.draft?.eventJSON != nil ? 0.4 : 1)
    }

    /// An expanding, fading ring; a still halo when the system asks for reduced motion.
    private var pulse: some View {
        Circle()
            .stroke(DamusColors.danger.opacity(0.5), lineWidth: 4)
            .scaleEffect(reduceMotion ? 1.15 : (pulsing ? 1.4 : 1))
            .opacity(reduceMotion ? 0.6 : (pulsing ? 0 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulsing = true }
            }
            .onDisappear { pulsing = false }
    }

    /// Keep the timer in the caption so starting a recording does not move the touch area.
    private var caption: some View {
        HStack(spacing: 6) {
            if recording {
                Text(elapsed).monospacedDigit().fontWeight(.semibold).foregroundColor(DamusColors.danger)
            }
            Text(recording ? (overTrash ? "Release to discard" : "Slide left to discard") :
                    (model.draft?.takeID == nil ? "Hold to record" : "Hold to record a new take"))
                .foregroundColor(overTrash ? DamusColors.danger : .secondary)
        }
        .font(.caption)
    }
}

/// UIKit supplies explicit cancelled/ended events without SwiftUI gesture-state reset ordering.
private struct VoiceRecordingTouchArea: UIViewRepresentable {
    let onBegin: () -> Void
    let onHover: (Bool) -> Void
    let onRelease: (VoiceRecordingGesture.Release) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.cancel() }

    final class Coordinator: NSObject {
        var parent: VoiceRecordingTouchArea
        var gesture = VoiceRecordingGesture()
        init(_ parent: VoiceRecordingTouchArea) { self.parent = parent }

        @objc func changed(_ press: UILongPressGestureRecognizer) {
            let location = press.location(in: press.view)
            switch press.state {
            case .began:
                gesture.begin()
                parent.onBegin()
            case .changed:
                gesture.move(to: location)
                parent.onHover(gesture.isOverTrash)
            case .ended:
                if let release = gesture.end(at: location) { parent.onRelease(release) }
            case .cancelled, .failed:
                cancel()
            default: break
            }
        }

        func cancel() {
            if let release = gesture.end(at: .zero, cancelled: true) { parent.onRelease(release) }
        }
    }
}

/// Observe the composer's presentation controller to confirm a swipe dismissal too.
/// The original delegate still receives dismissal callbacks used by SwiftUI's sheet binding.
struct VoiceComposerDismissGuard: UIViewControllerRepresentable {
    let blocked: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> Observer { Observer() }

    func updateUIViewController(_ controller: Observer, context: Context) {
        controller.blocked = blocked
        controller.onAttempt = onAttempt
        controller.install()
    }

    static func dismantleUIViewController(_ controller: Observer, coordinator: ()) { controller.uninstall() }

    final class Observer: UIViewController, UIAdaptivePresentationControllerDelegate {
        var blocked = false
        var onAttempt: () -> Void = {}
        weak var observedPresentation: UIPresentationController?
        weak var originalDelegate: (any UIAdaptivePresentationControllerDelegate)?

        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); install() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); install() }

        func install() {
            var ancestor = parent
            while let controller = ancestor {
                if controller.presentingViewController != nil, let presentation = controller.presentationController {
                    if presentation.delegate !== self {
                        originalDelegate = presentation.delegate
                        presentation.delegate = self
                    }
                    observedPresentation = presentation
                    controller.isModalInPresentation = blocked
                    return
                }
                ancestor = controller.parent
            }
        }

        func uninstall() {
            if observedPresentation?.delegate === self { observedPresentation?.delegate = originalDelegate }
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !blocked && (originalDelegate?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if blocked { onAttempt() }
            else { originalDelegate?.presentationControllerDidAttemptToDismiss?(presentationController) }
        }

        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            originalDelegate?.presentationControllerWillDismiss?(presentationController)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            originalDelegate?.presentationControllerDidDismiss?(presentationController)
        }
    }
}


/// nostr.build upload destination and the device's transcription language.
private struct VoiceRecordingSettings: View {
    @ObservedObject var model: VoiceComposerModel
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var locale = Locale.current.identifier
    @State private var locales = [Locale.current.identifier]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("nostr.build voice uploads") {
                    TextField("https://blossom.band", text: $server)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("The shared server supports free audio uploads. If you have a paid nostr.build Blossom subdomain, enter its HTTPS address here.")
                        .font(.caption).foregroundColor(.secondary)
                    Text("Your recording and photos upload only when you press Post.")
                        .font(.caption).foregroundColor(.secondary)
                    Link("nostr.build Blossom service", destination: URL(string: "https://blossom.band")!)
                }
                Section("On-device transcription") {
                    Picker("Language", selection: $locale) {
                        ForEach(Array(Set(locales + [locale])).sorted(), id: \.self) { identifier in
                            Text(Locale.current.localizedString(forIdentifier: identifier) ?? identifier).tag(identifier)
                        }
                    }
                    Text("Transcription runs on this device. Supported iOS 26 devices use Apple's latest speech model. A language model may need to download before its first use; your recording is never sent for transcription.")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let error { Text(error).foregroundColor(.red) }
            }
            .navigationTitle("Voice settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let origin = try VoiceBlossomUploader.origin(server)
                            model.state.settings.voice_blossom_server = origin.absoluteString
                            model.locale = locale
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .onAppear { server = model.state.settings.voice_blossom_server; locale = model.locale }
            .task { locales = await AppleVoiceTranscriber.supportedLocaleIdentifiers() }
        }
    }
}
