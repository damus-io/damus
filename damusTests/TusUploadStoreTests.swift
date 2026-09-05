//
//  TusUploadStoreTests.swift
//  damusTests
//
//  Created by Daniel D'Aquino on 2026-09-05.
//
//  The store is what makes resume-after-app-kill possible, so these tests are
//  about durability rather than convenience: does a record survive a round trip
//  intact, does a hostile id stay inside the directory, and does one unreadable
//  file take the others down with it.
//

import XCTest
@testable import damus

final class TusUploadStoreTests: XCTestCase {
    var directory: URL!
    var store: TusUploadStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tus-store-tests-\(UUID().uuidString)", isDirectory: true)
        store = try TusUploadStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeRecord(id: String = "video-1", source: URL? = nil) -> TusUploadRecord {
        var record = TusUploadRecord(
            id: id,
            source: source ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/clip.mov"),
            uploadURL: URL(string: "https://video.example.com/tus/\(id)"),
            totalBytes: 850_000_000,
            headers: ["AuthorizationSignature": "deadbeef"],
            metadata: ["filename": "clip.mov"],
            chunkSize: 8 * 1024 * 1024
        )
        record.confirmedOffset = 16_777_216
        record.phase = .uploading
        record.pendingChunk = TusPendingChunk(offset: 16_777_216, length: 8_388_608, fileName: "chunk-a")
        return record
    }

    func testRoundTripPreservesEverythingNeededToResume() throws {
        let record = makeRecord()
        try store.save(record)

        let loaded = try XCTUnwrap(store.load(id: "video-1"))
        XCTAssertEqual(loaded.id, record.id)
        XCTAssertEqual(loaded.uploadURL, record.uploadURL)
        XCTAssertEqual(loaded.totalBytes, record.totalBytes)
        XCTAssertEqual(loaded.confirmedOffset, 16_777_216)
        XCTAssertEqual(loaded.headers, ["AuthorizationSignature": "deadbeef"])
        XCTAssertEqual(loaded.metadata, ["filename": "clip.mov"])
        XCTAssertEqual(loaded.chunkSize, 8 * 1024 * 1024)
        XCTAssertEqual(loaded.phase, .uploading)
        XCTAssertEqual(loaded.pendingChunk, record.pendingChunk)
        XCTAssertEqual(loaded.source, record.source)
    }

    func testASecondStoreOverTheSameDirectorySeesTheRecord() throws {
        // This is the app-relaunch case: nothing carries over in memory.
        try store.save(makeRecord())
        let reopened = try TusUploadStore(directory: directory)
        XCTAssertEqual(try reopened.load(id: "video-1")?.confirmedOffset, 16_777_216)
        XCTAssertEqual(reopened.loadAll().count, 1)
    }

    func testSaveOverwritesRatherThanAccumulating() throws {
        var record = makeRecord()
        try store.save(record)
        record.confirmedOffset = 99
        try store.save(record)
        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(try store.load(id: "video-1")?.confirmedOffset, 99)
    }

    func testMissingRecordLoadsAsNil() throws {
        XCTAssertNil(try store.load(id: "never-saved"))
    }

    func testDeleteRemovesTheRecord() throws {
        try store.save(makeRecord())
        try store.delete(id: "video-1")
        XCTAssertNil(try store.load(id: "video-1"))
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testHostileIdentifiersStayInsideTheDirectory() throws {
        // Upload ids come from a server, so they are untrusted path components.
        let nasty = "../../../../etc/passwd"
        try store.save(makeRecord(id: nasty))
        XCTAssertEqual(try store.load(id: nasty)?.id, nasty)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].contains("/"))
        XCTAssertFalse(files[0].contains(".."))
    }

    func testIdentifiersDifferingOnlyByCaseDoNotCollide() throws {
        try store.save(makeRecord(id: "Video-A"))
        try store.save(makeRecord(id: "video-a"))
        XCTAssertEqual(store.loadAll().count, 2)
    }

    func testEmptyIdentifierIsRejected() {
        XCTAssertThrowsError(try store.save(makeRecord(id: "")))
    }

    func testAnUnreadableRecordDoesNotHideTheOthers() throws {
        // A kill during a write, or a record from an older schema, must not
        // strand every other upload.
        try store.save(makeRecord(id: "good-1"))
        try store.save(makeRecord(id: "good-2"))
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("corrupt.json"))

        let all = store.loadAll()
        XCTAssertEqual(Set(all.map { $0.id }), ["good-1", "good-2"])
    }

    // MARK: - Source file relocation

    func testSourcePathInsideTheContainerIsReanchoredToTheCurrentHome() throws {
        // The container path carries a UUID that changes on reinstall, so a
        // persisted absolute path is not a stable way to find the asset.
        let inContainer = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/exports/clip.mov")
        let ref = TusSourceFile(url: inContainer)

        let data = try JSONEncoder().encode(ref)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["relativeToHome"] as? String, "Documents/exports/clip.mov")

        let decoded = try JSONDecoder().decode(TusSourceFile.self, from: data)
        XCTAssertEqual(decoded.url.path, inContainer.standardizedFileURL.path)
    }

    func testSourcePathOutsideTheContainerIsKeptVerbatim() throws {
        let outside = URL(fileURLWithPath: "/var/mobile/Media/DCIM/100APPLE/IMG_0001.MOV")
        let ref = TusSourceFile(url: outside)
        let decoded = try JSONDecoder().decode(TusSourceFile.self, from: JSONEncoder().encode(ref))
        XCTAssertEqual(decoded.url.path, outside.path)
    }

    func testARecordWrittenUnderADifferentContainerStillResolves() throws {
        // Hand-write a record as an older install would have, with a stale
        // container UUID, and check we look in today's container instead.
        let stalePath = "/var/mobile/Containers/Data/Application/DEAD-BEEF/Documents/clip.mov"
        let json = """
        {"relativeToHome":"Documents/clip.mov","recordedPath":"\(stalePath)"}
        """
        let decoded = try JSONDecoder().decode(TusSourceFile.self, from: Data(json.utf8))
        XCTAssertEqual(
            decoded.url.standardizedFileURL.path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/clip.mov").standardizedFileURL.path
        )
        XCTAssertNotEqual(decoded.url.path, stalePath)
    }

    // MARK: - Chunk arithmetic

    func testNextChunkRangeWalksTheFileAndStops() {
        var record = TusUploadRecord(id: "x", source: URL(fileURLWithPath: "/tmp/x"), totalBytes: 25, chunkSize: 10)
        XCTAssertEqual(record.nextChunkRange()?.offset, 0)
        XCTAssertEqual(record.nextChunkRange()?.length, 10)

        record.confirmedOffset = 20
        // The last chunk is short, not a full chunkSize read past the end.
        XCTAssertEqual(record.nextChunkRange()?.length, 5)

        record.confirmedOffset = 25
        XCTAssertNil(record.nextChunkRange())
        XCTAssertTrue(record.isFinished)
    }

    func testFractionCompleteIsSafeOnAnEmptyFile() {
        let record = TusUploadRecord(id: "x", source: URL(fileURLWithPath: "/tmp/x"), totalBytes: 0, chunkSize: 10)
        XCTAssertEqual(record.fractionComplete, 0)
        XCTAssertNil(record.nextChunkRange())
    }
}
