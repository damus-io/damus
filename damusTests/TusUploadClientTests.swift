//
//  TusUploadClientTests.swift
//  damusTests
//
//  Created by Daniel D'Aquino on 2026-09-05.
//
//  End-to-end tests for the resumable uploader against a real tus 1.0.0 server.
//
//  These need a server, because the interesting behaviour *is* the negotiation:
//  a mock that always agrees with us would never catch resuming from the wrong
//  offset. Start one with either
//
//      tusd -port 1080
//      docker run -p 1080:1080 tusproject/tusd
//
//  and the tests run; without one they skip rather than fail, so CI stays green.
//  Point somewhere else with TUS_TEST_ENDPOINT.
//

import XCTest
import CryptoKit
@testable import damus

@MainActor
final class TusUploadClientTests: XCTestCase {
    /// Creation endpoint of the tus server under test.
    static var endpoint: URL {
        let raw = ProcessInfo.processInfo.environment["TUS_TEST_ENDPOINT"] ?? "http://127.0.0.1:1080/files/"
        return URL(string: raw)!
    }

    var directory: URL!
    var store: TusUploadStore!
    var clients: [TusUploadClient] = []

    override func setUp() async throws {
        try await super.setUp()
        let serverIsUp = await Self.serverIsUp()
        try XCTSkipUnless(
            serverIsUp,
            "No tus server at \(Self.endpoint). Start one with `tusd -port 1080` or set TUS_TEST_ENDPOINT."
        )
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tus-client-tests-\(UUID().uuidString)", isDirectory: true)
        store = try TusUploadStore(directory: directory)
    }

    override func tearDown() async throws {
        clients = []
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try await super.tearDown()
    }

    // MARK: - Tests

    func testUploadsAFileEndToEndAndTheServerHasTheRightBytes() async throws {
        let source = try makeFile(bytes: 512 * 1024)
        let client = makeClient(chunkSize: 64 * 1024)
        let spy = Spy()
        client.delegate = spy

        client.enqueueForTest(id: "e2e", source: source, store: store)
        client.start(id: "e2e")

        let uploadURL = try await waitForFinish(spy, timeout: 60)
        let uploaded = try await download(uploadURL)
        XCTAssertEqual(uploaded, try Data(contentsOf: source))
        XCTAssertEqual(client.state(for: "e2e")?.phase, .completed)
        XCTAssertEqual(client.state(for: "e2e")?.fractionComplete, 1)
    }

    func testProgressClimbsMonotonicallyToOne() async throws {
        let source = try makeFile(bytes: 512 * 1024)
        let client = makeClient(chunkSize: 32 * 1024)
        let spy = Spy()
        // Report every tick so the sequence is observable.
        client.delegate = spy

        client.enqueueForTest(id: "progress", source: source, store: store)
        client.start(id: "progress")
        _ = try await waitForFinish(spy, timeout: 60)

        let fractions = spy.states.map { $0.fractionComplete }
        XCTAssertGreaterThan(fractions.count, 2, "expected intermediate progress, not just start and finish")
        XCTAssertEqual(fractions.last, 1)
        XCTAssertEqual(fractions, fractions.sorted(), "progress went backwards without a retry")
    }

    /// The core of the card: an interrupted upload continues from where the
    /// server got to, rather than starting over.
    func testResumesFromTheServerOffsetAfterAnInterruption() async throws {
        let source = try makeFile(bytes: 2 * 1024 * 1024)
        let client = makeClient(chunkSize: 64 * 1024)
        let spy = Spy()
        client.delegate = spy

        client.enqueueForTest(id: "interrupt", source: source, store: store)
        client.start(id: "interrupt")

        // Let some of it land, then yank it.
        try await waitUntil(timeout: 30) { (try? self.store.load(id: "interrupt"))??.confirmedOffset ?? 0 > 128 * 1024 }
        client.pause(id: "interrupt")

        let offsetAtInterruption = try XCTUnwrap(try store.load(id: "interrupt")?.confirmedOffset)
        XCTAssertGreaterThan(offsetAtInterruption, 0)
        XCTAssertLessThan(offsetAtInterruption, 2 * 1024 * 1024)

        // And the server agrees with the record on disk.
        let record = try XCTUnwrap(try store.load(id: "interrupt"))
        let uploadURL = try XCTUnwrap(record.uploadURL)
        let offsetOnServer = try await serverOffset(uploadURL)
        XCTAssertEqual(offsetOnServer, offsetAtInterruption)

        spy.reset()
        client.start(id: "interrupt")
        _ = try await waitForFinish(spy, timeout: 60)

        // Nothing after the resume reported less progress than we had already
        // made — i.e. it picked up rather than restarting.
        let lowest = spy.states.map { $0.sentBytes }.min() ?? 0
        XCTAssertGreaterThanOrEqual(lowest, offsetAtInterruption)
        let uploaded = try await download(uploadURL)
        XCTAssertEqual(uploaded, try Data(contentsOf: source))
    }

    /// The app-relaunch case: a brand new client, over the same directory, with
    /// nothing carried over in memory.
    func testResumesWithAFreshClientAfterASimulatedRelaunch() async throws {
        let source = try makeFile(bytes: 2 * 1024 * 1024)
        let first = makeClient(chunkSize: 64 * 1024)
        let firstSpy = Spy()
        first.delegate = firstSpy

        first.enqueueForTest(id: "relaunch", source: source, store: store)
        first.start(id: "relaunch")
        try await waitUntil(timeout: 30) { (try? self.store.load(id: "relaunch"))??.confirmedOffset ?? 0 > 128 * 1024 }

        // Simulate the kill: stop everything and drop every reference. The
        // record left behind is `.uploading` with no live task, exactly as it
        // would be after a crash.
        first.pause(id: "relaunch")
        var killed = try XCTUnwrap(try store.load(id: "relaunch"))
        let offsetAtKill = killed.confirmedOffset
        killed.phase = .uploading
        try store.save(killed)
        clients.removeAll { $0 === first }

        let reopened = try TusUploadStore(directory: directory)
        let second = makeClient(chunkSize: 64 * 1024, store: reopened)
        let secondSpy = Spy()
        second.delegate = secondSpy

        // resumeAll() is the only thing the app calls at launch.
        await second.resumeAll()
        let uploadURL = try await waitForFinish(secondSpy, timeout: 60)

        XCTAssertGreaterThanOrEqual(secondSpy.states.map { $0.sentBytes }.min() ?? 0, offsetAtKill)
        let uploaded = try await download(uploadURL)
        XCTAssertEqual(uploaded, try Data(contentsOf: source))
    }

    /// A kill between a chunk landing on the server and us recording it leaves
    /// the persisted offset behind the truth. The `HEAD` has to win, or we would
    /// re-send bytes the server already has and get a 409.
    func testAStaleLocalOffsetIsCorrectedByTheServer() async throws {
        let source = try makeFile(bytes: 1024 * 1024)
        let client = makeClient(chunkSize: 64 * 1024)
        let spy = Spy()
        client.delegate = spy

        client.enqueueForTest(id: "stale", source: source, store: store)
        client.start(id: "stale")
        try await waitUntil(timeout: 30) { (try? self.store.load(id: "stale"))??.confirmedOffset ?? 0 > 256 * 1024 }
        client.pause(id: "stale")

        var record = try XCTUnwrap(try store.load(id: "stale"))
        let trueOffset = record.confirmedOffset
        // Rewind the record as a mid-write kill would.
        record.confirmedOffset = 0
        record.phase = .uploading
        try store.save(record)

        spy.reset()
        client.start(id: "stale")
        _ = try await waitForFinish(spy, timeout: 60)

        // The client reports the stale offset once, then the HEAD corrects it in
        // one jump. What must not happen is progress *through* the region the
        // server already has, which is what re-uploading those bytes looks like.
        let resent = spy.states.map { $0.sentBytes }.filter { $0 > 0 && $0 < trueOffset }
        XCTAssertEqual(resent, [], "re-sent bytes the server already had, up to \(trueOffset)")
        let uploaded = try await download(try XCTUnwrap(record.uploadURL))
        XCTAssertEqual(uploaded, try Data(contentsOf: source))
    }

    func testCancelDeletesTheUploadOnTheServerAndForgetsIt() async throws {
        let source = try makeFile(bytes: 512 * 1024)
        let client = makeClient(chunkSize: 64 * 1024)
        let spy = Spy()
        client.delegate = spy

        client.enqueueForTest(id: "cancelled", source: source, store: store)
        client.start(id: "cancelled")
        try await waitUntil(timeout: 30) { (try? self.store.load(id: "cancelled"))??.uploadURL != nil }
        let uploadURL = try XCTUnwrap(try store.load(id: "cancelled")?.uploadURL)

        client.cancel(id: "cancelled")

        XCTAssertNil(try store.load(id: "cancelled"))
        XCTAssertNil(client.state(for: "cancelled"))
        // Termination is best effort and asynchronous.
        try await waitUntil(timeout: 15) { (try? await self.statusCode(head: uploadURL)) == 404 }
    }

    func testChunkTempFilesAreNotLeftBehind() async throws {
        let source = try makeFile(bytes: 512 * 1024)
        let client = makeClient(chunkSize: 64 * 1024)
        let spy = Spy()
        client.delegate = spy

        client.enqueueForTest(id: "tidy", source: source, store: store)
        client.start(id: "tidy")
        _ = try await waitForFinish(spy, timeout: 60)

        let chunks = (try? FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent("chunks").path)) ?? []
        XCTAssertEqual(chunks, [], "leaked chunk temp files")
    }

    func testAMissingSourceFileFailsWithoutRetrying() async throws {
        let source = try makeFile(bytes: 4096)
        let client = makeClient(chunkSize: 1024)
        let spy = Spy()
        client.delegate = spy

        client.enqueueForTest(id: "gone", source: source, store: store)
        try FileManager.default.removeItem(at: source)
        client.start(id: "gone")

        try await waitUntil(timeout: 30) { spy.failure != nil }
        guard case .sourceFileMissing = try XCTUnwrap(spy.failure) else {
            return XCTFail("expected sourceFileMissing, got \(String(describing: spy.failure))")
        }
        XCTAssertEqual(client.state(for: "gone")?.phase, .failed)
    }

    /// Opt-in, because it moves real gigabytes. Run with e.g.
    /// `TUS_LARGE_FILE_MB=850 xcodebuild test-without-building ...`
    func testLargeFileSurvivesRepeatedInterruptions() async throws {
        guard let raw = ProcessInfo.processInfo.environment["TUS_LARGE_FILE_MB"], let megabytes = Int(raw) else {
            throw XCTSkip("Set TUS_LARGE_FILE_MB to run the large-file test.")
        }
        let total = megabytes * 1024 * 1024
        let source = try makeFile(bytes: total)
        let client = makeClient(chunkSize: 4 * 1024 * 1024)
        let spy = Spy()
        client.delegate = spy

        client.enqueueForTest(id: "large", source: source, store: store)
        client.start(id: "large")

        // Interrupt three times at roughly even intervals.
        for fraction in [0.2, 0.45, 0.7] {
            let target = Int64(Double(total) * fraction)
            try await waitUntil(timeout: 900) {
                ((try? self.store.load(id: "large"))??.confirmedOffset ?? 0) > target
                    || spy.finishedURL != nil
            }
            guard spy.finishedURL == nil else { break }
            client.pause(id: "large")
            let stopped = try XCTUnwrap(try self.store.load(id: "large")?.confirmedOffset)
            spy.reset()
            client.start(id: "large")
            try await waitUntil(timeout: 900) {
                (spy.states.map { $0.sentBytes }.max() ?? 0) > stopped || spy.finishedURL != nil
            }
            XCTAssertGreaterThanOrEqual(
                spy.states.map { $0.sentBytes }.min() ?? 0, stopped,
                "restarted from scratch instead of resuming at \(stopped)"
            )
        }

        let uploadURL = try await waitForFinish(spy, timeout: 3600)
        let finalOffset = try await serverOffset(uploadURL)
        XCTAssertEqual(finalOffset, Int64(total))
    }

    // MARK: - Helpers

    private func makeClient(chunkSize: Int, store overrideStore: TusUploadStore? = nil) -> TusUploadClient {
        var config = TusUploadClient.Configuration()
        // A plain session: a background session delivers out of process, which
        // makes assertions in a test host racy. The state machine is the same.
        config.sessionMode = .foreground
        config.chunkSize = chunkSize
        config.backoff = TusBackoff(base: 0.1, multiplier: 2, maxDelay: 2, jitter: 0)
        config.progressThrottle = 0
        let client = TusUploadClient(store: overrideStore ?? store, config: config)
        clients.append(client)
        return client
    }

    private func makeFile(bytes: Int) throws -> URL {
        let url = directory.appendingPathComponent("source-\(UUID().uuidString).bin")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        // Pseudo-random but reproducible, so a mis-ordered chunk shows up as a
        // content mismatch rather than matching zeroes.
        var remaining = bytes
        var seed: UInt64 = 0x2545F4914F6CDD1D
        while remaining > 0 {
            let size = min(remaining, 1 << 20)
            var block = Data(count: size)
            block.withUnsafeMutableBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                for index in 0..<size {
                    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                    base[index] = UInt8(truncatingIfNeeded: seed)
                }
            }
            try handle.write(contentsOf: block)
            remaining -= size
        }
        return url
    }

    private func waitForFinish(_ spy: Spy, timeout: TimeInterval) async throws -> URL {
        try await waitUntil(timeout: timeout) { spy.finishedURL != nil || spy.failure != nil }
        if let failure = spy.failure { throw failure }
        return try XCTUnwrap(spy.finishedURL)
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("timed out after \(timeout)s waiting for a condition")
    }

    // MARK: - Talking to the server directly

    private static func serverIsUp() async -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "OPTIONS"
        request.timeoutInterval = 3
        guard let (_, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.value(forHTTPHeaderField: "Tus-Resumable") != nil || http.statusCode == 204
    }

    private func serverOffset(_ uploadURL: URL) async throws -> Int64 {
        let request = TusRequest.head(uploadURL: uploadURL, headers: [:])
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return try XCTUnwrap(TusResponse.offset(from: try XCTUnwrap(response as? HTTPURLResponse)))
    }

    private func statusCode(head uploadURL: URL) async throws -> Int {
        let request = TusRequest.head(uploadURL: uploadURL, headers: [:])
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return try XCTUnwrap(response as? HTTPURLResponse).statusCode
    }

    private func download(_ uploadURL: URL) async throws -> Data {
        var request = URLRequest(url: uploadURL)
        request.setValue(Tus.version, forHTTPHeaderField: Tus.Header.resumable)
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        XCTAssertEqual(try XCTUnwrap(response as? HTTPURLResponse).statusCode, 200)
        return data
    }

    // MARK: - Delegate spy

    @MainActor
    final class Spy: TusUploadClientDelegate {
        private(set) var states: [TusUploadState] = []
        private(set) var finishedURL: URL?
        private(set) var failure: TusUploadError?

        func reset() {
            states = []
            finishedURL = nil
            failure = nil
        }

        func tusUploadClient(_ client: TusUploadClient, didUpdate state: TusUploadState) {
            states.append(state)
        }

        func tusUploadClient(_ client: TusUploadClient, didFinish id: TusUploadID, uploadURL: URL) {
            finishedURL = uploadURL
        }

        func tusUploadClient(_ client: TusUploadClient, didFail id: TusUploadID, error: TusUploadError) {
            failure = error
        }
    }
}

private extension TusUploadClient {
    /// Enqueue against the shared test endpoint, letting the client create the
    /// upload resource the way it would against a bare tus server.
    func enqueueForTest(id: TusUploadID, source: URL, store: TusUploadStore) {
        _ = try? enqueue(
            id: id,
            sourceURL: source,
            destination: .create(endpoint: TusUploadClientTests.endpoint),
            metadata: ["filename": source.lastPathComponent]
        )
    }
}
