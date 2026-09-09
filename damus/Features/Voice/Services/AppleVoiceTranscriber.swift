import Foundation
import Speech
import AVFoundation

/// Injected at the composer boundary so failures and late results can be tested deterministically.
protocol VoiceTranscribing: Sendable {
    func supports(locale: String) async -> Bool
    func transcribe(_ url: URL, locale: String) async throws -> String
}

/// Uses Nosis's SpeechTranscriber configuration on supported iOS 26 devices.
/// Older devices/languages use SFSpeechRecognizer with on-device recognition required.
actor AppleVoiceTranscriber: VoiceTranscribing {
    func supports(locale: String) async -> Bool {
#if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *), await Self.modernLocale(locale) != nil { return true }
#endif
        return SFSpeechRecognizer(locale: Locale(identifier: locale))?.supportsOnDeviceRecognition == true
    }

    /// Include the modern model's downloadable languages in the composer's picker.
    static func supportedLocaleIdentifiers() async -> [String] {
        var locales = SFSpeechRecognizer.supportedLocales()
#if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *), SpeechTranscriber.isAvailable {
            locales.formUnion(await SpeechTranscriber.supportedLocales)
        }
#endif
        return locales.map(\.identifier).sorted()
    }

    func transcribe(_ url: URL, locale: String) async throws -> String {
        try Task.checkCancellation()
#if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *), let supported = await Self.modernLocale(locale) {
            return try await AppleSpeechJob(operation: {
                try await Self.analyze(url, locale: supported)
            }).run()
        }
#endif
        return try await transcribeLegacy(url, locale: locale)
    }

    /// The legacy API must never fall back to remote recognition.
    private func transcribeLegacy(_ url: URL, locale: String) async throws -> String {
        try Task.checkCancellation()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              recognizer.supportsOnDeviceRecognition else {
            throw VoiceFailure("On-device transcription is unavailable for this language on this device. You can still post with Text.")
        }
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard permission == .authorized else {
            throw VoiceFailure("Allow Speech Recognition in Settings to transcribe locally. Keep this composer open to retry.")
        }
        guard recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            throw VoiceFailure("On-device transcription is currently unavailable. Keep this composer open to retry.")
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true
        let job = AppleSpeechJob { callback in
            let task = recognizer.recognitionTask(with: request) { result, error in
                callback(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
            }
            return { task.cancel() }
        }
        return try await job.run()
    }
}

#if compiler(>=6.2)
extension AppleVoiceTranscriber {
    /// Availability is about hardware and language support; assets can be installed on first use.
    @available(iOS 26.0, macOS 26.0, *)
    private static func modernLocale(_ identifier: String) async -> Locale? {
        guard SpeechTranscriber.isAvailable else { return nil }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
    }

    /// Fresh modules per take, the same `.transcription` preset as Nosis, and final results only.
    /// Both input and results must finish successfully; stream errors never become partial posts.
    @available(iOS 26.0, macOS 26.0, *)
    private static func analyze(_ url: URL, locale: Locale) async throws -> String {
        try Task.checkCancellation()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        do {
            let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
            if let installation {
                try await installation.downloadAndInstall()
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            throw VoiceFailure("The on-device language model could not be prepared. Connect to download it, then retry transcription. \(error.localizedDescription)")
        }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        return try await withTaskCancellationHandler(operation: {
            try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask {
                    var transcript = ""
                    for try await result in transcriber.results {
                        try Task.checkCancellation()
                        guard result.isFinal else { continue }
                        transcript += String(result.text.characters)
                        guard transcript.utf8.count <= 12_000 else {
                            throw VoiceFailure("The transcript is too long for a post. Record a shorter take.")
                        }
                    }
                    return transcript
                }
                group.addTask {
                    try Task.checkCancellation()
                    let file = try AVAudioFile(forReading: url)
                    let lastSample = try await analyzer.analyzeSequence(from: file)
                    if let lastSample {
                        try await analyzer.finalizeAndFinish(through: lastSample)
                    } else {
                        await analyzer.cancelAndFinishNow()
                    }
                    return nil
                }
                do {
                    var transcript = ""
                    for try await result in group {
                        if let result { transcript = result }
                    }
                    try Task.checkCancellation()
                    return transcript
                } catch {
                    group.cancelAll()
                    await analyzer.cancelAndFinishNow()
                    throw error
                }
            }
        }, onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        })
    }
}
#endif

/// Serializes Speech callbacks, cancellation and task-install races; a terminal result wins once.
/// The injected request start permits deterministic error-only, timeout and late-callback tests.
final class AppleSpeechJob: @unchecked Sendable {
    typealias Callback = @Sendable (String?, Bool, Error?) -> Void
    typealias Start = @Sendable (@escaping Callback) -> (@Sendable () -> Void)
    private let lock = NSLock()
    private let start: Start
    private var continuation: CheckedContinuation<String, Error>?
    private var cancelRequest: (@Sendable () -> Void)?
    private var result: Result<String, Error>?

    init(start: @escaping Start) { self.start = start }

    /// Async recognition shares the same timeout, cancellation, and final-text validation.
    convenience init(operation: @escaping @Sendable () async throws -> String) {
        self.init { callback in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let text = try await operation()
                    try Task.checkCancellation()
                    callback(text, true, nil)
                } catch { callback(nil, false, error) }
            }
            return { task.cancel() }
        }
    }

    func run(timeout: TimeInterval = VoiceLimits.recognitionTimeout) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.waitForResult() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                throw VoiceFailure("On-device transcription timed out. Keep this composer open to retry.")
            }
            defer { group.cancelAll() }
            guard let text = try await group.next() else { throw CancellationError() }
            return text
        }
    }

    private func waitForResult() async throws -> String {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
                let cancel = start { [weak self] transcript, isFinal, error in
                    if let error { self?.finish(.failure(error)); return }
                    guard isFinal else { return }
                    let text = transcript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if text.isEmpty {
                        self?.finish(.failure(VoiceFailure("No speech was recognized. Listen to your recording or try transcription again.")))
                    } else if text.utf8.count > 12_000 {
                        self?.finish(.failure(VoiceFailure("The transcript is too long for a post. Record a shorter take.")))
                    } else { self?.finish(.success(text)) }
                }
                lock.lock()
                let finished = self.result != nil
                if !finished { cancelRequest = cancel }
                lock.unlock()
                if finished { cancel() }
            }
        }, onCancel: { self.finish(.failure(CancellationError())) })
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation, cancel = cancelRequest
        self.continuation = nil
        cancelRequest = nil
        lock.unlock()
        cancel?()
        continuation?.resume(with: result)
    }
}
