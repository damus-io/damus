import XCTest
@testable import damus

final class VoiceSpeechJobTests: XCTestCase {
    /// The async analyzer adapter uses the same validated final-text contract as callbacks.
    func testAsyncRecognitionValidatesFinalTextAndPropagatesFailure() async throws {
        let completed = AppleSpeechJob(operation: { "  Final transcript  " })
        let text = try await completed.run(timeout: 1)
        XCTAssertEqual(text, "Final transcript")
        for invalid in ["  ", String(repeating: "a", count: 12_001)] {
            let job = AppleSpeechJob(operation: { invalid })
            do { _ = try await job.run(timeout: 1); XCTFail("Unusable async transcript was accepted") }
            catch is VoiceFailure {}
        }
        let failed = AppleSpeechJob(operation: { throw VoiceFailure("result stream failed") })
        do { _ = try await failed.run(timeout: 1); XCTFail("Async failure was swallowed") }
        catch { XCTAssertEqual(error.localizedDescription, "result stream failed") }
    }

    /// A silent async analyzer is cancelled at the same deadline as the legacy recognizer.
    func testAsyncRecognitionTimeoutCancelsTheOperation() async throws {
        let cancelled = expectation(description: "async operation cancelled")
        let job = AppleSpeechJob(operation: {
            try await withTaskCancellationHandler(operation: {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return "Should not finish"
            }, onCancel: { cancelled.fulfill() })
        })
        do { _ = try await job.run(timeout: 0.1); XCTFail("Silent async recognition did not time out") }
        catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
        await fulfillment(of: [cancelled], timeout: 1)
    }

    /// Even an async operation that ignores cancellation cannot return a stale transcript.
    func testAsyncRecognitionCancellationRejectsLateSuccess() async throws {
        let started = expectation(description: "async operation started")
        let finished = expectation(description: "late operation finished")
        let job = AppleSpeechJob(operation: {
            started.fulfill()
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch {}
            finished.fulfill()
            return "Late success"
        })
        let task = Task { try await job.run(timeout: 5) }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled recognition returned a transcript") }
        catch is CancellationError {}
        await fulfillment(of: [finished], timeout: 1)
    }

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
