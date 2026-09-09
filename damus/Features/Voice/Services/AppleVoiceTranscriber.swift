import Foundation
import Speech

/// Injected at the composer boundary so failures and late results can be tested deterministically.
protocol VoiceTranscribing: Sendable {
    func supports(locale: String) async -> Bool
    func transcribe(_ url: URL, locale: String) async throws -> String
}

/// Uses only recognizers that explicitly support on-device recognition.
/// No request is created with a server fallback, even when the device is online.
actor AppleVoiceTranscriber: VoiceTranscribing {
    func supports(locale: String) async -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: locale))?.supportsOnDeviceRecognition == true
    }

    func transcribe(_ url: URL, locale: String) async throws -> String {
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
            throw VoiceFailure("Allow Speech Recognition in Settings to transcribe locally. Your recording has been saved.")
        }
        guard recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
            throw VoiceFailure("On-device transcription is currently unavailable. Your recording has been saved for retry.")
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

    func run(timeout: TimeInterval = VoiceLimits.recognitionTimeout) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await self.waitForResult() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                throw VoiceFailure("On-device transcription timed out. Your recording has been saved for retry.")
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
