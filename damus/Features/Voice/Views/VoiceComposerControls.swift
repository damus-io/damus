import SwiftUI
import Speech
import UIKit

/// Readable transcript review replaces the normal tappable text editor in Audio mode.
struct VoiceTranscriptReview: View {
    @ObservedObject var model: VoiceComposerModel
    @State private var settingsPresented = false
    @State private var confirmDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.status).font(.subheadline).foregroundColor(.secondary)
                    .accessibilityIdentifier("voice.status")
                Spacer()
                Button { settingsPresented = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Voice recording settings")
                    .disabled(model.busy)
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
                    if model.draft?.takeID != nil {
                        Button { model.preview() } label: { Label("Listen", systemImage: "play.circle") }
                        if model.draft?.transcript == nil && model.draft?.eventJSON == nil {
                            Button("Retry transcription") { model.retryTranscription() }
                        }
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

/// The microphone owns a continuous touch even when the finger moves into the trash target.
struct VoiceRecordingBar: View {
    @ObservedObject var model: VoiceComposerModel
    @State private var overTrash = false
    private var recording: Bool { model.phase == .recording || model.phase == .requestingPermission }

    var body: some View {
        VStack(spacing: 6) {
            Divider()
            if model.phase == .recording {
                Text(Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit().foregroundColor(.red)
            }
            HStack(spacing: 12) {
                VoiceAttachmentButtons(model: model)
                    .opacity(recording ? 0 : 1)
                    .allowsHitTesting(!recording)
                microphone
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            Text(recording ? (overTrash ? "Release to discard" : "Slide left to discard") :
                    (model.draft?.takeID == nil ? "Hold to record" : "Hold to record a new take"))
                .font(.caption).foregroundColor(overTrash ? .red : .secondary)
        }
        .padding(.bottom, 12)
    }

    private var microphone: some View {
        Image(systemName: recording ? "waveform" : "mic.fill")
            .font(.system(size: 32)).foregroundColor(.white)
            .frame(width: 76, height: 76)
            .background(recording ? Color.red : Color.accentColor)
            .clipShape(Circle())
            .overlay {
                VoiceRecordingTouchArea(
                    onBegin: { overTrash = false; model.beginHold() },
                    onHover: { value in
                        if value && !overTrash { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                        overTrash = value
                        model.updateTrashHover(value)
                    },
                    onRelease: { result in
                        overTrash = false
                        model.releaseHold(discard: result == .discard)
                    })
                    .allowsHitTesting((!model.busy || recording) && model.draft?.eventJSON == nil)
            }
            .overlay {
                if recording {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 24))
                        .foregroundColor(overTrash ? .white : .red)
                        .frame(width: 60, height: 60)
                        .background(overTrash ? Color.red : Color.red.opacity(0.12), in: Circle())
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
            .opacity(model.draft?.eventJSON != nil ? 0.4 : 1)
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
                        ForEach(SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted(), id: \.self) { identifier in
                            Text(Locale.current.localizedString(forIdentifier: identifier) ?? identifier).tag(identifier)
                        }
                    }
                    Text("Apple recognition runs on this device. Availability depends on your device and language; there is no cloud fallback.")
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
        }
    }
}
