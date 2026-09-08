//
//  PurpleVideoDecodingTests.swift
//  damusTests
//
//  Decoding the Purple hosted-video API's successful responses, against the
//  API's own recorded bytes.
//
//  These are not "does Codable work" tests. Each one pins a semantic the
//  server went out of its way to establish and that the client would otherwise
//  get wrong: that publishability is a field and not an inference, that
//  progress freezes rather than completes on failure, that the dimensions have
//  already been rotated, and that a PascalCase key survives the decoder.
//

import XCTest
@testable import damus

final class PurpleVideoDecodingTests: XCTestCase {

    // MARK: - POST /video

    func testAuthorizationDecodesEverythingNeededToStartAnUpload() throws {
        let authorization = try PurpleVideoFixtures.authorization()

        XCTAssertEqual(authorization.videoId, "1bdab18a-0dc5-4ad6-9874-092ec58cd6b5")
        XCTAssertEqual(authorization.authorizationSignature, "a7806312560fbbbcfd51e49a4df721dd281391bfffdd0b7267eb07c553fceb83")
        XCTAssertEqual(authorization.tusEndpoint, URL(string: "https://video.bunnycdn.com/tusupload"))
        XCTAssertEqual(authorization.playbackURL, URL(string: "https://mock-pull-zone.b-cdn.net/1bdab18a-0dc5-4ad6-9874-092ec58cd6b5/playlist.m3u8"))
        XCTAssertEqual(authorization.thumbnailURL, URL(string: "https://mock-pull-zone.b-cdn.net/1bdab18a-0dc5-4ad6-9874-092ec58cd6b5/thumbnail.jpg"))
        XCTAssertEqual(authorization.quota, PurpleVideoQuota(
            usedStoredBytes: 500, limitStoredBytes: 2000, remainingStoredBytes: 1500, windowSeconds: 2_592_000
        ))
    }

    func testLibraryIdIsAStringNotANumber() throws {
        // It is concatenated into the TUS signature server-side, so a client
        // that re-serializes it as a number produces a signature the provider
        // answers with a bare 401 and an empty body.
        let authorization = try PurpleVideoFixtures.authorization()
        XCTAssertEqual(authorization.libraryId, "mock-library")
        XCTAssertEqual(authorization.tusHeaders[PurpleVideoTusHeaderKey.libraryId], "mock-library")
    }

    func testThePascalCaseTusHeaderKeysSurviveDecoding() throws {
        // The whole reason this API is decoded without
        // `keyDecodingStrategy = .convertFromSnakeCase`: Foundation applies a
        // key strategy to dictionary keys too, and its snake-case converter
        // would deliver `authorizationsignature`.
        let authorization = try PurpleVideoFixtures.authorization()

        XCTAssertEqual(authorization.tusHeaders, [
            "AuthorizationSignature": "a7806312560fbbbcfd51e49a4df721dd281391bfffdd0b7267eb07c553fceb83",
            "AuthorizationExpire": "1706666400",
            "LibraryId": "mock-library",
            "VideoId": "1bdab18a-0dc5-4ad6-9874-092ec58cd6b5",
        ])
        for key in PurpleVideoTusHeaderKey.required {
            XCTAssertNotNil(authorization.tusHeaders[key], "missing TUS header \(key)")
        }
    }

    func testAnAuthorizationMissingATusHeaderIsRefusedHereRatherThanByTheProvider() {
        let mangled = PurpleVideoFixtures.authorize200
            .replacingOccurrences(of: "\"LibraryId\":\"mock-library\",", with: "")

        XCTAssertThrowsError(try PurpleVideoWire.authorization(PurpleVideoFixtures.json(200, mangled))) { error in
            guard case .malformedSuccessBody(let detail) = error as? PurpleVideoAPIError else {
                return XCTFail("expected malformedSuccessBody, got \(error)")
            }
            XCTAssertTrue(detail.contains("LibraryId"), detail)
        }
    }

    func testUnixSecondsAreReadAsUnixSecondsAndTheDeadlineOutlivesTheSignature() throws {
        // A bare `JSONDecoder()` reads a number into a `Date` as seconds since
        // 2001, which would land every deadline 31 years early and silently.
        let authorization = try PurpleVideoFixtures.authorization()

        XCTAssertEqual(authorization.expiry, Date(timeIntervalSince1970: 1_706_666_400))
        XCTAssertEqual(authorization.uploadDeadline, Date(timeIntervalSince1970: 1_706_680_800))
        // The reservation always outlives the TUS credential: bytes may still
        // be arriving under a re-minted signature.
        XCTAssertGreaterThan(authorization.uploadDeadline, authorization.expiry)
    }

    // MARK: - GET /video/{id}

    func testAnAuthorizedVideoHasNoProgressAndIsNotFinished() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusAuthorized)

        XCTAssertEqual(status.status, .authorized)
        XCTAssertFalse(status.publishable)
        XCTAssertFalse(status.terminal)
        XCTAssertEqual(status.encodeProgress, 0)
        XCTAssertTrue(status.availableResolutions.isEmpty)
        XCTAssertEqual(status.chargedStoredBytes, 500)
        XCTAssertNil(status.storedBytes)
    }

    func testAMidEncodeVideoReportsProgressAndIsNotPublishable() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusEncoding)

        XCTAssertEqual(status.status, .encoding)
        XCTAssertEqual(status.encodeProgress, 45)
        XCTAssertEqual(status.encodeProgressForDisplay, 45)
        XCTAssertFalse(status.publishable)
        XCTAssertFalse(status.terminal)
        XCTAssertNil(status.encodeClean)
        XCTAssertNil(status.durationSeconds)
    }

    func testACleanEncodeIsPublishableAndCarriesItsSize() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusReadyClean)

        XCTAssertEqual(status.status, .ready)
        XCTAssertTrue(status.publishable)
        XCTAssertTrue(status.terminal)
        XCTAssertEqual(status.encodeClean, true)
        XCTAssertEqual(status.durationSeconds, 93)
        XCTAssertEqual(status.storedBytes, 700)
        XCTAssertEqual(status.chargedStoredBytes, 700)
        XCTAssertFalse(status.stale)
    }

    func testADamagedEncodeIsNotPublishableEvenWithAFullRenditionLadder() throws {
        // The trap this exists for: a damaged encode reaches every rendition
        // and reports 100% progress, so anything gating on the ladder or on
        // progress publishes a broken video.
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusDamaged)

        XCTAssertEqual(status.status, .damaged)
        XCTAssertFalse(status.publishable)
        XCTAssertTrue(status.terminal)
        XCTAssertEqual(status.encodeProgress, 100)
        XCTAssertEqual(status.encodeClean, false)
        XCTAssertEqual(status.availableResolutions, ["360p", "480p", "720p"])
        // Only a clean encode gets a duration: the provider's `length` is the
        // source container's claim, not what it produced.
        XCTAssertNil(status.durationSeconds)
    }

    func testAFailedEncodeIsTerminalAtFivePercentAndNeverRendersAsProgress() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusFailed)

        XCTAssertEqual(status.status, .failed)
        XCTAssertTrue(status.terminal)
        XCTAssertFalse(status.publishable)
        // Frozen at 5 — not 0, not 100. `terminal` is the completion test.
        XCTAssertEqual(status.encodeProgress, 5)
        // ...and it must never reach a progress bar, or one parks at 5% forever.
        XCTAssertNil(status.encodeProgressForDisplay)
        XCTAssertEqual(status.storedBytes, 0)
        XCTAssertEqual(status.chargedStoredBytes, 0)
    }

    func testAnExpiredReservationIsTerminalAndCostsNothing() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusExpired)

        XCTAssertEqual(status.status, .expired)
        XCTAssertTrue(status.terminal)
        XCTAssertFalse(status.publishable)
        XCTAssertEqual(status.chargedStoredBytes, 0)
    }

    func testAFinishedEncodeCanBePublishableBeforeItsSizeIsBanked() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusReadyNoSizeYet)

        XCTAssertTrue(status.publishable)
        XCTAssertNil(status.storedBytes)
        // Still charged the reservation until the real size lands.
        XCTAssertEqual(status.chargedStoredBytes, 500)
    }

    func testAStaleResponseIsTheLastKnownStateAndNotAnError() throws {
        // The server could not reach the provider and answered from its own
        // row. Keep polling; show nothing to the user.
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusStale)

        XCTAssertTrue(status.stale)
        XCTAssertEqual(status.status, .encoding)
        XCTAssertEqual(status.encodeProgress, 45)
    }

    func testACacheHitIsNotStale() throws {
        XCTAssertFalse(try PurpleVideoFixtures.status(PurpleVideoFixtures.statusReadyClean).stale)
    }

    // MARK: - Dimensions

    func testDimensionsArriveAlreadyRotatedForDisplay() throws {
        // The server ran `display_dimensions_of` before answering, so this
        // portrait clip reports 1080x1920 even though it is stored 1920x1080
        // and `rotation` never reaches the wire. Re-rotating here would turn
        // every portrait video sideways.
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusReadyClean)

        XCTAssertEqual(status.displayWidth, 1080)
        XCTAssertEqual(status.displayHeight, 1920)
        XCTAssertGreaterThan(status.displayHeight ?? 0, status.displayWidth ?? 0)
    }

    func testDimensionsAreAbsentUntilTheEncodeProducesThem() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusEncoding)
        XCTAssertNil(status.displayWidth)
        XCTAssertNil(status.displayHeight)
    }

    // MARK: - Resolutions

    func testResolutionsAreASetAndTheTallestIsComputedNotIndexed() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusDamaged)

        XCTAssertEqual(status.availableResolutions, ["360p", "480p", "720p"])
        XCTAssertEqual(status.highestAvailableResolutionLines, 720)
    }

    func testAPartialLadderReportsWhatHasLandedSoFar() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusEncoding)

        XCTAssertEqual(status.availableResolutions, ["360p", "480p"])
        XCTAssertEqual(status.highestAvailableResolutionLines, 480)
    }

    func testNoRenditionsMeansNoTallestRendition() throws {
        XCTAssertNil(try PurpleVideoFixtures.status(PurpleVideoFixtures.statusFailed).highestAvailableResolutionLines)
    }

    // MARK: - Issues

    func testTheVariableFrameRateNoticeIsInformationalNotAProblem() throws {
        // It fires on essentially every iPhone upload. Reading it as an error
        // would make a clean encode look broken.
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusReadyClean)

        XCTAssertEqual(status.issues.count, 1)
        let issue = try XCTUnwrap(status.issues.first)
        XCTAssertEqual(issue.code, 4)
        XCTAssertEqual(issue.level, 1)
        XCTAssertEqual(issue.severity, .info)
        XCTAssertFalse(issue.severity.isProblem)
        XCTAssertTrue(issue.message.contains("variable frame rate"))
    }

    func testADamagedEncodeCarriesBothTheNoticeAndTheProblem() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusDamaged)

        XCTAssertEqual(status.issues.map(\.severity), [.info, .damaged])
        XCTAssertEqual(status.issues.map(\.code), [4, 2])
        XCTAssertEqual(status.issues.filter { $0.severity.isProblem }.count, 1)
    }

    func testAFatalIssueLeaksNothingFromTheProvider() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusFailed)

        let issue = try XCTUnwrap(status.issues.first)
        XCTAssertEqual(issue.severity, .fatal)
        XCTAssertEqual(issue.code, 7)
        XCTAssertEqual(issue.message, "The uploaded file could not be read as a video.")
    }

    func testUnknownIssueCodesAndAMissingCodeStillDecode() throws {
        let status = try PurpleVideoFixtures.status(PurpleVideoFixtures.statusUnknownIssueCodes)

        XCTAssertEqual(status.issues.map(\.code), [99, 98, 97, nil, 4])
        XCTAssertEqual(status.issues.map(\.severity), [.info, .damaged, .fatal, .damaged, .info])
        // A missing `level` is 0, which is informational.
        XCTAssertEqual(status.issues.map(\.level), [1, 2, 3, 2, 0])
        for issue in status.issues {
            XCTAssertFalse(issue.message.isEmpty, "issue \(String(describing: issue.code)) has no copy")
        }
    }

    // MARK: - Open enums

    func testAnUnknownStatusDecodesRatherThanThrowing() throws {
        // A server that grows a state must not break an app already shipped.
        let body = PurpleVideoFixtures.statusEncoding
            .replacingOccurrences(of: "\"status\":\"encoding\"", with: "\"status\":\"transmogrifying\"")
        let status = try PurpleVideoFixtures.status(body)

        XCTAssertEqual(status.status, .unknown("transmogrifying"))
        XCTAssertEqual(status.status.rawValue, "transmogrifying")
    }

    func testAnUnknownSeverityDecodesAndCountsAsAProblem() throws {
        let body = PurpleVideoFixtures.statusReadyClean
            .replacingOccurrences(of: "\"severity\":\"info\"", with: "\"severity\":\"catastrophic\"")
        let status = try PurpleVideoFixtures.status(body)

        let issue = try XCTUnwrap(status.issues.first)
        XCTAssertEqual(issue.severity, .unknown("catastrophic"))
        // Conservative: shows as a warning. It cannot become a hard block,
        // because nothing gates publishing on severity.
        XCTAssertTrue(issue.severity.isProblem)
    }

    func testEveryKnownStatusRoundTripsThroughItsRawValue() {
        // `PendingVideo` persists a status to disk, so a value written by a
        // newer build has to survive being read and rewritten by an older one.
        let names = ["authorized", "uploading", "encoding", "ready", "damaged",
                     "failed", "expired", "deleted", "something-new"]
        for name in names {
            XCTAssertEqual(PurpleVideoState(rawValue: name).rawValue, name, "\(name) did not round-trip")
        }
    }

    // MARK: - DELETE /video/{id}

    func testDeletingAVideoTombstonesTheRowAndReportsTheAllowance() throws {
        let deletion = try PurpleVideoWire.deletion(PurpleVideoFixtures.json(200, PurpleVideoFixtures.deleteFresh))

        XCTAssertEqual(deletion.videoId, "4fc2d3b2-fa74-42df-8fce-9f107a7c28ba")
        XCTAssertEqual(deletion.status, .deleted)
        XCTAssertTrue(deletion.deleted)
        XCTAssertFalse(deletion.alreadyDeleted)
        XCTAssertEqual(deletion.deletedAt, Date(timeIntervalSince1970: 1_706_659_200))
        // Deleting does not refund stored bytes inside the rolling window.
        XCTAssertEqual(deletion.chargedStoredBytes, 700)
        XCTAssertEqual(deletion.quota.remainingStoredBytes, 1300)
    }

    func testDeletingTwiceIsASuccessNotAnError() throws {
        let deletion = try PurpleVideoWire.deletion(PurpleVideoFixtures.json(200, PurpleVideoFixtures.deleteAlreadyDeleted))

        XCTAssertTrue(deletion.deleted)
        XCTAssertTrue(deletion.alreadyDeleted)
        XCTAssertEqual(deletion.quota.remainingStoredBytes, 1300)
    }

    func testCancellingAnUploadThatNeverArrivedReleasesItsReservation() throws {
        let deletion = try PurpleVideoWire.deletion(PurpleVideoFixtures.json(200, PurpleVideoFixtures.deleteNeverUploaded))

        XCTAssertEqual(deletion.chargedStoredBytes, 0)
        XCTAssertEqual(deletion.quota.usedStoredBytes, 0)
        XCTAssertEqual(deletion.quota.remainingStoredBytes, 2000)
    }

    // MARK: - Body shape

    func testTheTrailingNewlineExpressWritesDoesNotBreakDecoding() throws {
        // Every recorded body ends with one.
        XCTAssertTrue(PurpleVideoFixtures.authorize200.hasSuffix("\n"))
        XCTAssertTrue(PurpleVideoFixtures.statusReadyClean.hasSuffix("\n"))
        XCTAssertTrue(PurpleVideoFixtures.deleteFresh.hasSuffix("\n"))
        XCTAssertNoThrow(try PurpleVideoFixtures.authorization())
        XCTAssertNoThrow(try PurpleVideoFixtures.status(PurpleVideoFixtures.statusReadyClean))
    }
}
