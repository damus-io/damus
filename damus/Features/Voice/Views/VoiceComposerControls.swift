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
struct VoiceRecordingBar: View {
    @ObservedObject var model: VoiceComposerModel
    @GestureState private var pressing = false
    var body: some View {
        VStack(spacing: 6) {
            Divider()
            if model.phase == .recording {
                Text(Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit().foregroundColor(.red)
            }
            Image(systemName: model.phase == .recording ? "waveform" : "mic.fill")
                .font(.system(size: 32))
                .foregroundColor(.white)
                .frame(width: 76, height: 76)
                .background(model.phase == .recording ? Color.red : Color.accentColor)
                .clipShape(Circle())
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { _ in model.beginHold() }
                    .onEnded { _ in model.releaseHold() })
                .onChange(of: pressing) { value in if !value { model.releaseHold() } }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(model.phase == .recording ? "Stop recording" : "Start voice recording")
                .accessibilityHint("Hold to record, then release to transcribe on this device. Posting is a separate action.")
                .accessibilityIdentifier("voice.microphone")
                .accessibilityAction {
                    if model.phase == .recording { model.releaseHold() } else { model.beginHold() }
                }
                .disabled((model.busy && model.phase != .recording && model.phase != .requestingPermission) || model.draft?.eventJSON != nil)
                .opacity(model.draft?.eventJSON != nil ? 0.4 : 1)
            Text(model.draft?.takeID == nil ? "Hold to record" : "Hold to record a new take")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.bottom, 12)
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
