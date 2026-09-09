import Foundation
import AVFoundation

protocol VoiceRecording: Sendable {
    func start(to url: URL) async throws
    func finish() async throws
}

private final class VoiceRecorderDelegate: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    let completion: @Sendable (Result<Void, Error>) -> Void
    init(completion: @escaping @Sendable (Result<Void, Error>) -> Void) { self.completion = completion }
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag { completion(.success(())) }
        else { completion(.failure(VoiceFailure("Recording was interrupted. The saved take can be reviewed or replaced."))) }
    }
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        completion(.failure(error ?? VoiceFailure("The recording could not be finalized.")))
    }
}

/// Serializes the audio writer and waits for its finish callback before any reader sees the file.
actor AppleVoiceRecorder: VoiceRecording {
    static let shared = AppleVoiceRecorder()
    private var recorder: AVAudioRecorder?
    private var starting = false
    private var finishing = false
    private var delegate: VoiceRecorderDelegate?
    private var generation = UUID()
    private var completion: Result<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?
    private var previousSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    func start(to url: URL) async throws {
        guard recorder == nil, !starting, !finishing else { throw VoiceFailure("A recording is already active.") }
        starting = true
        defer { starting = false }
        try Task.checkCancellation()
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard granted else { throw VoiceFailure("Allow Microphone access in Settings to record. Text posts remain available.") }
        let session = AVAudioSession.sharedInstance()
        previousSession = (session.category, session.mode, session.categoryOptions)
        let id = UUID()
        generation = id
        completion = nil
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            let delegate = VoiceRecorderDelegate { [weak self] result in
                Task { await self?.finished(result, generation: id) }
            }
            self.delegate = delegate
            self.recorder = recorder
            recorder.delegate = delegate
            guard recorder.prepareToRecord(), recorder.record(forDuration: VoiceLimits.recordingDuration) else {
                throw VoiceFailure("The microphone could not start recording.")
            }
        } catch {
            recorder?.stop()
            recorder = nil
            delegate = nil
            restoreSession()
            throw error
        }
    }

    func finish() async throws {
        guard !finishing else { throw VoiceFailure("The recording is already being finalized.") }
        finishing = true
        defer { finishing = false }
        let id = generation
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.awaitFinish(generation: id) }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    throw VoiceFailure("The audio writer did not finish. The saved take will be checked when reopened.")
                }
                defer { group.cancelAll() }
                _ = try await group.next()
            }
        } catch {
            // A timed-out finish must stop and release the writer before its caller inspects bytes.
            abort(generation: id)
            throw error
        }
    }

    private func awaitFinish(generation id: UUID) async throws {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                guard id == generation else { continuation.resume(throwing: CancellationError()); return }
                if let completion {
                    recorder = nil
                    delegate = nil
                    restoreSession()
                    continuation.resume(with: completion)
                } else if let recorder {
                    waiter = continuation
                    recorder.stop()
                } else {
                    restoreSession()
                    continuation.resume()
                }
            }
        }, onCancel: { Task { await self.abort(generation: id) } })
    }

    private func finished(_ result: Result<Void, Error>, generation id: UUID) {
        guard id == generation, completion == nil else { return }
        completion = result
        if let waiter {
            self.waiter = nil
            recorder = nil
            delegate = nil
            restoreSession()
            waiter.resume(with: result)
        }
    }

    private func abort(generation id: UUID) {
        guard id == generation else { return }
        recorder?.stop()
        recorder = nil
        delegate = nil
        let waiter = self.waiter
        self.waiter = nil
        completion = .failure(CancellationError())
        restoreSession()
        waiter?.resume(throwing: CancellationError())
    }

    private func restoreSession() {
        guard let previous = previousSession else { return }
        previousSession = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(previous.0, mode: previous.1, options: previous.2)
    }
}
