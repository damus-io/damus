import XCTest
@testable import damus

final class VoiceSpeechJobTests: XCTestCase {
    func testErrorWithoutRecognitionResultFinishesAndCancelsInstalledTask() async throws {
        let probe = SpeechRequestProbe()
        let job = AppleSpeechJob { callback in
            probe.install(callback)
            callback(nil, false, VoiceFailure("recognizer unavailable"))
            return { probe.cancel() }
        }
        do { _ = try await job.run(timeout: 1); XCTFail("An error-only callback was ignored") }
        catch { XCTAssertEqual(error.localizedDescription, "recognizer unavailable") }
        XCTAssertEqual(probe.cancellations, 1)
    }

    func testPartialThenFinalWinsOverLateErrorAndDuplicateCompletion() async throws {
        let probe = SpeechRequestProbe()
        let job = AppleSpeechJob { callback in
            probe.install(callback)
            callback("partial", false, nil)
            callback("  Final transcript  ", true, nil)
            callback(nil, false, VoiceFailure("late error"))
            callback("duplicate", true, nil)
            return { probe.cancel() }
        }
        let transcript = try await job.run(timeout: 1)
        XCTAssertEqual(transcript, "Final transcript")
        XCTAssertEqual(probe.cancellations, 1)
    }

    func testTimeoutCancelsARecognizerThatNeverCallsBack() async throws {
        let probe = SpeechRequestProbe()
        let job = AppleSpeechJob { callback in probe.install(callback); return { probe.cancel() } }
        do { _ = try await job.run(timeout: 0.02); XCTFail("Silent recognizer did not time out") }
        catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        XCTAssertEqual(probe.cancellations, 1)
        probe.emit("late result", final: true)
    }

    func testCancellationFinishesOnceAndIgnoresLateFinalResult() async throws {
        let started = expectation(description: "recognizer installed")
        let probe = SpeechRequestProbe()
        let job = AppleSpeechJob { callback in
            probe.install(callback); started.fulfill()
            return { probe.cancel() }
        }
        let task = Task { try await job.run(timeout: 5) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled recognition returned a transcript") }
        catch is CancellationError {}
        XCTAssertEqual(probe.cancellations, 1)
        probe.emit("late transcript", final: true)
    }

    func testEmptyAndExcessiveFinalTranscriptsAreFailures() async throws {
        for text in ["  ", String(repeating: "a", count: 12_001)] {
            let job = AppleSpeechJob { callback in callback(text, true, nil); return {} }
            do { _ = try await job.run(timeout: 1); XCTFail("Unusable transcript was accepted") }
            catch is VoiceFailure {}
        }
    }
}

private final class SpeechRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: AppleSpeechJob.Callback?
    private var count = 0
    var cancellations: Int { lock.lock(); defer { lock.unlock() }; return count }
    func install(_ callback: @escaping AppleSpeechJob.Callback) { lock.lock(); self.callback = callback; lock.unlock() }
    func cancel() { lock.lock(); count += 1; lock.unlock() }
    func emit(_ text: String, final: Bool) {
        lock.lock(); let callback = callback; lock.unlock()
        callback?(text, final, nil)
    }
}
