import SwiftUI
import Speech

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
            if model.draft?.takeID != nil || model.draft?.pendingTakeID != nil {
                HStack {
                    if model.draft?.takeID != nil {
                        Button { model.preview() } label: { Label("Listen", systemImage: "play.circle") }
                        if model.draft?.transcript == nil && model.draft?.eventJSON == nil {
                            Button("Retry transcription") { model.retryTranscription() }
                        }
                    }
                    Spacer()
                    if model.draft?.eventJSON == nil || model.draft?.phase == .accepted {
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
        .confirmationDialog("Discard this recording and its transcript?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard recording", role: .destructive) { model.discard() }
        }
    }
}

/// A sheet-bottom microphone with press/release and equivalent VoiceOver actions.
/// Drawn in the compose button's family: the same gradient orb, Damus red while recording.
struct VoiceRecordingBar: View {
    @ObservedObject var model: VoiceComposerModel
    @GestureState private var pressing = false
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recording: Bool { model.phase == .recording }
    private var elapsed: String { Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)) }

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            VStack(spacing: 8) {
                microphone
                caption
            }
            .padding(.top, 6)
        }
        .padding(.bottom, 12)
    }

    private var microphone: some View {
        ZStack {
            if recording { pulse }
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
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .updating($pressing) { _, state, _ in state = true }
            .onChanged { _ in model.beginHold() }
            .onEnded { _ in model.releaseHold() })
        .onChange(of: pressing) { value in if !value { model.releaseHold() } }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(recording ? "Stop recording" : "Start voice recording")
        .accessibilityHint("Hold to record, then release to transcribe on this device. Posting is a separate action.")
        .accessibilityIdentifier("voice.microphone")
        .accessibilityAction {
            if recording { model.releaseHold() } else { model.beginHold() }
        }
        .disabled((model.busy && model.phase != .recording && model.phase != .requestingPermission) || model.draft?.eventJSON != nil)
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

    /// The timer shares the caption line so the orb never moves under a held finger.
    private var caption: some View {
        HStack(spacing: 6) {
            if recording {
                Text(elapsed).monospacedDigit().fontWeight(.semibold).foregroundColor(DamusColors.danger)
                Text("Release to stop").foregroundColor(.secondary)
            } else {
                Text(model.draft?.takeID == nil ? "Hold to record" : "Hold to record a new take")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
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
                    Text("Your recording uploads only when you press Post.")
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
