//
//  TusProcessKillTests.swift
//  damusTests
//
//  Created by Daniel D'Aquino on 2026-09-05.
//
//  The card's actual bar: an upload interrupted by the app being *killed*
//  resumes from its last offset rather than restarting. That cannot be done
//  inside one test process, so it is two, driven from outside:
//
//      1. run only `testPhaseA_startLargeUploadAndBlockUntilKilled`
//      2. `kill -9` the simulator app while it is mid-upload
//      3. run only `testPhaseB_resumeAfterProcessKill`
//
//  Both phases share a fixed directory in the app container — nothing is carried
//  in memory, and phase B has no knowledge of phase A beyond what is on disk.
//  Neither is meaningful on its own, so both *skip* rather than fail unless
//  TUS_KILL_TEST_MB is set, which keeps an ordinary CI run green.
//
//  See docs/tus-upload-testing.md for the driver script.
//

import XCTest
import CryptoKit
@testable import damus

@MainActor
final class TusProcessKillTests: XCTestCase {
    /// Size of the upload, in megabytes. Also the switch that enables these.
    static var megabytes: Int? {
        ProcessInfo.processInfo.environment["TUS_KILL_TEST_MB"].flatMap(Int.init)
    }

    static var endpoint: URL {
        URL(string: ProcessInfo.processInfo.environment["TUS_TEST_ENDPOINT"] ?? "http://127.0.0.1:1080/files/")!
    }

    static let uploadID = "process-kill-test"

    /// Fixed, not a per-run temp directory: phase B has to find what phase A
    /// left behind, in a different process.
    static var storeDirectory: URL {
        let support = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("tus-kill-test", isDirectory: true)
    }

    static var sourceURL: URL {
        let documents = try! FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return documents.appendingPathComponent("tus-kill-test-source.bin")
    }

    // MARK: - Phase A: start it, then sit there waiting to be killed

    func testPhaseA_startLargeUploadAndBlockUntilKilled() async throws {
        guard let megabytes = Self.megabytes else {
            throw XCTSkip("Set TUS_KILL_TEST_MB to run the process-kill phases; see docs/tus-upload-testing.md for the driver script.")
        }
        let total = Int64(megabytes) * 1024 * 1024

        // Start from nothing so phase B cannot be fooled by an earlier run.
        try? FileManager.default.removeItem(at: Self.storeDirectory)
        try? FileManager.default.removeItem(at: Self.sourceURL)
        try Self.generateSource(bytes: total)

        let store = try TusUploadStore(directory: Self.storeDirectory)
        let client = TusUploadClient(store: store, config: Self.config())
        _ = try client.enqueue(
            id: Self.uploadID,
            sourceURL: Self.sourceURL,
            destination: .create(endpoint: Self.endpoint),
            metadata: ["filename": "kill-test.bin"]
        )
        client.start(id: Self.uploadID)

        print("TUS-KILL-TEST: phase A started, \(total) bytes, store at \(Self.storeDirectory.path)")

        // Hold the process open so the driver can kill it mid-flight. If we are
        // still alive when a good chunk has landed, keep going — the driver
        // decides when to pull the plug.
        let deadline = Date().addingTimeInterval(1800)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 200_000_000)
            let offset = ((try? store.load(id: Self.uploadID))??.confirmedOffset) ?? 0
            print("TUS-KILL-TEST: offset=\(offset)/\(total)")
            if offset >= total {
                return XCTFail("phase A finished before it was killed; use a larger TUS_KILL_TEST_MB")
            }
        }
        XCTFail("phase A was never killed")
    }

    // MARK: - Phase B: a cold process picks it up

    func testPhaseB_resumeAfterProcessKill() async throws {
        guard let megabytes = Self.megabytes else {
            throw XCTSkip("Set TUS_KILL_TEST_MB to run the process-kill phases; see docs/tus-upload-testing.md for the driver script.")
        }
        let total = Int64(megabytes) * 1024 * 1024

        let store = try TusUploadStore(directory: Self.storeDirectory)
        let survived = try XCTUnwrap(
            try store.load(id: Self.uploadID),
            "no record survived the kill — run phase A first"
        )
        XCTAssertEqual(survived.phase, .uploading, "the killed upload should still read as in-progress")
        XCTAssertEqual(survived.totalBytes, total)
        let offsetAtKill = survived.confirmedOffset
        XCTAssertGreaterThan(offsetAtKill, 0, "phase A was killed before anything landed; kill it later")
        XCTAssertLessThan(offsetAtKill, total, "phase A finished; nothing to resume")
        print("TUS-KILL-TEST: phase B resuming from \(offsetAtKill)/\(total)")

        let client = TusUploadClient(store: store, config: Self.config())
        let spy = Spy()
        client.delegate = spy

        // The only thing the app does at launch.
        await client.resumeAll()

        let deadline = Date().addingTimeInterval(1800)
        while Date() < deadline, spy.finishedURL == nil, spy.failure == nil {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        if let failure = spy.failure { throw failure }
        let uploadURL = try XCTUnwrap(spy.finishedURL, "resume did not finish in time")

        // Never reported less progress than the kill left us with, i.e. it
        // picked up rather than starting over.
        XCTAssertGreaterThanOrEqual(
            spy.states.map { $0.sentBytes }.min() ?? 0, offsetAtKill,
            "restarted from scratch instead of resuming at \(offsetAtKill)"
        )

        // And the bytes on the server are the bytes we meant to send.
        let (serverLength, serverDigest) = try await Self.downloadAndHash(uploadURL)
        XCTAssertEqual(serverLength, total)
        XCTAssertEqual(serverDigest, try Self.hashFile(Self.sourceURL))

        try? FileManager.default.removeItem(at: Self.sourceURL)
        try? FileManager.default.removeItem(at: Self.storeDirectory)
    }

    // MARK: - Helpers

    private static func config() -> TusUploadClient.Configuration {
        var config = TusUploadClient.Configuration()
        // The realistic configuration: a background session is what lets the
        // transfer outlive the app in the first place.
        config.sessionMode = .background(identifier: "io.damus.tus.upload.killtest")
        config.chunkSize = 8 * 1024 * 1024
        config.progressThrottle = 0.25
        return config
    }

    /// Deterministic pseudo-random content, so a chunk landing at the wrong
    /// offset shows up as a digest mismatch rather than matching zeroes.
    private static func generateSource(bytes: Int64) throws {
        FileManager.default.createFile(atPath: sourceURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sourceURL)
        defer { try? handle.close() }
        var remaining = bytes
        var seed: UInt64 = 0x9E3779B97F4A7C15
        while remaining > 0 {
            let size = Int(min(remaining, 4 << 20))
            var block = Data(count: size)
            block.withUnsafeMutableBytes { raw in
                guard let base = raw.bindMemory(to: UInt64.self).baseAddress else { return }
                for index in 0..<(size / 8) {
                    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                    base[index] = seed
                }
            }
            // The throwing API: the deprecated `write(_:)` raises an ObjC
            // exception on a short write and takes the process down with it.
            try handle.write(contentsOf: block)
            remaining -= Int64(size)
        }
    }

    private static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try handle.read(upToCount: 4 << 20), !block.isEmpty {
            hasher.update(data: block)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Streams the server's copy to a file rather than into memory — the point
    /// of the test is that this is a large upload.
    private static func downloadAndHash(_ uploadURL: URL) async throws -> (Int64, String) {
        var request = URLRequest(url: uploadURL)
        request.setValue(Tus.version, forHTTPHeaderField: Tus.Header.resumable)
        let (temp, response) = try await URLSession(configuration: .ephemeral).download(for: request)
        defer { try? FileManager.default.removeItem(at: temp) }
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let size = try temp.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return (Int64(size), try hashFile(temp))
    }

    @MainActor
    final class Spy: TusUploadClientDelegate {
        private(set) var states: [TusUploadState] = []
        private(set) var finishedURL: URL?
        private(set) var failure: TusUploadError?

        func tusUploadClient(_ client: TusUploadClient, didUpdate state: TusUploadState) { states.append(state) }
        func tusUploadClient(_ client: TusUploadClient, didFinish id: TusUploadID, uploadURL: URL) { finishedURL = uploadURL }
        func tusUploadClient(_ client: TusUploadClient, didFail id: TusUploadID, error: TusUploadError) { failure = error }
    }
}
