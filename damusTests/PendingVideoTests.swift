//
//  PendingVideoTests.swift
//  damusTests
//
//  The durable record that makes "your video is ready" work at all.
//
//  A push from Purple is only a latency optimisation; the record on disk plus a
//  foreground reconcile is the mechanism. So these tests are about durability
//  and about convergence: does a record survive an app kill intact, does a
//  hostile id stay inside the directory, and do a push and a poll racing the
//  same guid land on one answer.
//

import XCTest
@testable import damus

final class PendingVideoTests: XCTestCase {
    var directory: URL!
    var store: PendingVideoStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-video-tests-\(UUID().uuidString)", isDirectory: true)
        store = try PendingVideoStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - Durability

    func testRoundTripPreservesEverythingNeededToFinishTheJob() throws {
        var record = try makeRecord(composerDraftID: "draft-abc")
        record.state = .encoding
        record.lastCheckedAt = Date(timeIntervalSince1970: 1_706_659_999)
        try store.save(record)

        let loaded = try XCTUnwrap(store.load(id: record.videoId))
        XCTAssertEqual(loaded, record)
        XCTAssertEqual(loaded.composerDraftID, "draft-abc")
        XCTAssertEqual(loaded.playbackURL, record.playbackURL)
        XCTAssertEqual(loaded.asset, record.asset)
        XCTAssertEqual(loaded.expiry, record.expiry)
        XCTAssertEqual(loaded.uploadDeadline, record.uploadDeadline)
    }

    func testASecondStoreOverTheSameDirectorySeesTheRecord() throws {
        // The app-relaunch case: nothing carries over in memory.
        let record = try makeRecord()
        try store.save(record)

        let reopened = try PendingVideoStore(directory: directory)
        XCTAssertEqual(try reopened.load(id: record.videoId), record)
        XCTAssertEqual(reopened.loadAll().count, 1)
    }

    func testSaveOverwritesRatherThanAccumulating() throws {
        var record = try makeRecord()
        try store.save(record)
        record.state = .uploading
        try store.save(record)

        XCTAssertEqual(store.loadAll().count, 1)
        XCTAssertEqual(try store.load(id: record.videoId)?.state, .uploading)
    }

    func testAHostileVideoIdStaysInsideTheDirectory() throws {
        // Ids come from a server, so they are not trusted as path components.
        let hostile = "../../../../etc/passwd"
        let record = try makeRecord(videoId: hostile)
        try store.save(record)

        XCTAssertEqual(try store.load(id: hostile), record)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
    }

    func testAnEmptyVideoIdIsRefusedRatherThanWritingAStrayFile() throws {
        let record = PendingVideo(authorization: try authorization(videoId: ""), asset: assetURL)
        XCTAssertThrowsError(try store.save(record))
    }

    func testOneUnreadableRecordDoesNotHideTheOthers() throws {
        try store.save(try makeRecord(videoId: "video-a"))
        try store.save(try makeRecord(videoId: "video-b"))
        try Data("not json".utf8).write(to: directory.appendingPathComponent("garbage.json"))

        XCTAssertEqual(store.loadAll().count, 2)
    }

    func testDeleteRemovesOnlyTheRecordAsked() throws {
        try store.save(try makeRecord(videoId: "video-a"))
        try store.save(try makeRecord(videoId: "video-b"))

        try store.delete(id: "video-a")

        XCTAssertNil(try store.load(id: "video-a"))
        XCTAssertNotNil(try store.load(id: "video-b"))
    }

    // MARK: - The ladder

    func testStateOnlyEverMovesForward() throws {
        var record = try makeRecord()

        XCTAssertTrue(record.advance(to: .uploading))
        XCTAssertTrue(record.advance(to: .encoding))
        XCTAssertEqual(record.state, .encoding)

        // A late arrival from earlier in the upload must not walk it back.
        XCTAssertFalse(record.advance(to: .authorized))
        XCTAssertFalse(record.advance(to: .uploading))
        XCTAssertEqual(record.state, .encoding)
    }

    func testReapplyingTheCurrentStateIsANoOp() throws {
        var record = try makeRecord()
        record.state = .encoding

        XCTAssertFalse(record.advance(to: .encoding))
        XCTAssertEqual(record.state, .encoding)
    }

    func testATerminalStateNeverBecomesAnotherTerminalState() throws {
        // Four states share a rank precisely so this cannot happen: a failed
        // video must not turn ready because a stale response arrived late.
        for terminal in [PendingVideoState.ready, .damaged, .failed, .expired] {
            for other in [PendingVideoState.ready, .damaged, .failed, .expired] {
                var record = try makeRecord()
                record.state = terminal
                XCTAssertFalse(record.advance(to: other), "\(terminal) accepted \(other)")
                XCTAssertEqual(record.state, terminal)
            }
        }
    }

    func testPublishingAndAbandoningSitAboveEveryServerState() throws {
        for terminal in [PendingVideoState.ready, .damaged, .failed, .expired] {
            var record = try makeRecord()
            record.state = terminal
            XCTAssertTrue(record.advance(to: .published), "\(terminal) refused publish")
        }
    }

    // MARK: - Reconciling against the API

    func testAuthorizedBecomesReadyFromASingleStatusResponse() throws {
        // The common case: the app was in the background for the whole encode
        // and comes back to one answer.
        var record = try makeRecord(videoId: readyStatusVideoId)
        record.state = .authorized

        let folded = try XCTUnwrap(record.folding(try readyStatus(), now: now))

        XCTAssertEqual(folded.state, .ready)
        XCTAssertEqual(folded.lastCheckedAt, now)
    }

    func testAPushAndAPollRacingTheSameGuidApplyOnce() throws {
        // Two reconciles of the same response, in either order, land in the
        // same place — which is the whole reason the ladder exists.
        let record = try makeRecord(videoId: readyStatusVideoId)
        let status = try readyStatus()

        let first = try XCTUnwrap(record.folding(status, now: now))
        let second = try XCTUnwrap(first.folding(status, now: now.addingTimeInterval(1)))

        XCTAssertEqual(first.state, .ready)
        XCTAssertEqual(second.state, .ready)
        XCTAssertEqual(second.lastCheckedAt, now.addingTimeInterval(1))
    }

    func testADamagedEncodeDoesNotBecomeReady() throws {
        // `publishable` is the gate. A damaged encode reaches a full rendition
        // ladder and reports 100% progress, so anything else here publishes a
        // broken video.
        let record = try makeRecord(videoId: damagedStatusVideoId)
        let folded = try XCTUnwrap(record.folding(try PurpleVideoFixtures.status(PurpleVideoFixtures.statusDamaged), now: now))

        XCTAssertEqual(folded.state, .damaged)
    }

    func testAFailedEncodeIsTerminalDespiteItsFrozenProgress() throws {
        let record = try makeRecord(videoId: failedStatusVideoId)
        let folded = try XCTUnwrap(record.folding(try PurpleVideoFixtures.status(PurpleVideoFixtures.statusFailed), now: now))

        XCTAssertEqual(folded.state, .failed)
        XCTAssertTrue(folded.state.isTerminal)
    }

    func testAStaleResponseMovesOnlyTheTimestamp() throws {
        // The server could not reach the provider and answered from its own
        // row. Keep polling, keep the last state, show no error.
        var record = try makeRecord(videoId: staleStatusVideoId)
        record.state = .encoding
        record.lastCheckedAt = nil

        let folded = try XCTUnwrap(record.folding(try PurpleVideoFixtures.status(PurpleVideoFixtures.statusStale), now: now))

        XCTAssertEqual(folded.state, .encoding)
        XCTAssertEqual(folded.lastCheckedAt, now)
    }

    func testAStaleResponseCannotWalkATerminalRecordBackwards() throws {
        var record = try makeRecord(videoId: staleStatusVideoId)
        record.state = .ready

        let folded = try XCTUnwrap(record.folding(try PurpleVideoFixtures.status(PurpleVideoFixtures.statusStale), now: now))

        XCTAssertEqual(folded.state, .ready)
    }

    func testAResponseForADifferentVideoIsRefusedOutright() throws {
        // Otherwise one video's state quietly folds into another's.
        let record = try makeRecord(videoId: "some-other-video")
        XCTAssertNil(record.folding(try readyStatus(), now: now))
    }

    func testAnUnknownServerStateLeavesTheRecordWhereItIs() throws {
        let body = PurpleVideoFixtures.statusEncoding
            .replacingOccurrences(of: "\"status\":\"encoding\"", with: "\"status\":\"transmogrifying\"")
        var record = try makeRecord(videoId: encodingStatusVideoId)
        record.state = .uploading

        let folded = try XCTUnwrap(record.folding(try PurpleVideoFixtures.status(body), now: now))

        XCTAssertEqual(folded.state, .uploading)
        XCTAssertEqual(folded.lastCheckedAt, now)
    }

    // MARK: - Merging

    func testUpsertKeepsTheLocalAssetAPushCouldNotKnowAbout() throws {
        var local = try makeRecord(videoId: readyStatusVideoId, composerDraftID: "draft-abc")
        local.state = .uploading
        try store.save(local)

        // What a reconcile driven by a push would produce: the right guid and
        // state, and a placeholder for everything only this device knows.
        var incoming = PendingVideo(
            authorization: try authorization(videoId: readyStatusVideoId),
            asset: URL(fileURLWithPath: "/dev/null"),
            now: now
        )
        incoming.state = .ready

        let merged = try store.upsert(incoming)

        XCTAssertEqual(merged.state, .ready)
        XCTAssertEqual(merged.asset, local.asset)
        XCTAssertEqual(merged.composerDraftID, "draft-abc")
        XCTAssertEqual(merged.createdAt, local.createdAt)
    }

    func testUpsertNeverWalksStateBackwards() throws {
        var local = try makeRecord(videoId: "video-a")
        local.state = .ready
        try store.save(local)

        var stale = try makeRecord(videoId: "video-a")
        stale.state = .encoding

        XCTAssertEqual(try store.upsert(stale).state, .ready)
    }

    func testUpsertWritesARecordThatIsNotThereYet() throws {
        let record = try makeRecord(videoId: "video-new")
        XCTAssertEqual(try store.upsert(record), record)
        XCTAssertEqual(try store.load(id: "video-new"), record)
    }

    func testMutateReadsChangesAndWritesWithoutDeadlocking() throws {
        // `NSLock` is not recursive, so a `mutate` built on the public
        // `load`/`save` would hang here rather than fail.
        let record = try makeRecord(videoId: "video-a")
        try store.save(record)

        let updated = try store.mutate(id: "video-a") { record in
            _ = record.advance(to: .uploading, now: self.now)
        }

        XCTAssertEqual(updated?.state, .uploading)
        XCTAssertEqual(try store.load(id: "video-a")?.state, .uploading)
    }

    func testMutateOnAMissingRecordChangesNothing() throws {
        XCTAssertNil(try store.mutate(id: "not-here") { $0.state = .ready })
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    // MARK: - Credentials

    func testAReservationNeedsReMintingOnceTheSignatureHasExpired() throws {
        let record = try makeRecord()

        XCTAssertFalse(record.requiresFreshReservation(now: record.expiry.addingTimeInterval(-1)))
        XCTAssertTrue(record.requiresFreshReservation(now: record.expiry))
        XCTAssertTrue(record.requiresFreshReservation(now: record.expiry.addingTimeInterval(1)))
    }

    func testTheReservationOutlivesTheSignature() throws {
        // Bytes may still be arriving under a re-minted signature, so the
        // server holds the reservation longer than the credential lives.
        let record = try makeRecord()
        XCTAssertGreaterThan(record.uploadDeadline, record.expiry)
    }

    // MARK: - Helpers

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let assetURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/clip.mov")

    private let readyStatusVideoId = "29d51095-efff-4952-8e81-d1a546a78351"
    private let damagedStatusVideoId = "41832318-ea59-4933-8ed5-bc7d281de31a"
    private let failedStatusVideoId = "5fc049f9-dff9-4355-a3da-11581592d153"
    private let staleStatusVideoId = "a99119aa-5d05-4b8b-9616-aa9502eb2fc6"
    private let encodingStatusVideoId = "37e755d0-1be3-49bc-b159-9fd1b8ec860a"

    private func readyStatus() throws -> PurpleVideoStatus {
        try PurpleVideoFixtures.status(PurpleVideoFixtures.statusReadyClean)
    }

    /// A real authorization from the fixture, with the guid swapped so a record
    /// can be pointed at whichever status body a test needs.
    private func authorization(videoId: PurpleVideoID) throws -> PurpleVideoAuthorization {
        let body = PurpleVideoFixtures.authorize200
            .replacingOccurrences(of: "1bdab18a-0dc5-4ad6-9874-092ec58cd6b5", with: videoId)
        return try PurpleVideoWire.authorization(PurpleVideoFixtures.json(200, body))
    }

    private func makeRecord(
        videoId: PurpleVideoID = "1bdab18a-0dc5-4ad6-9874-092ec58cd6b5",
        composerDraftID: String? = nil
    ) throws -> PendingVideo {
        PendingVideo(
            authorization: try authorization(videoId: videoId),
            asset: assetURL,
            composerDraftID: composerDraftID,
            now: now
        )
    }
}
