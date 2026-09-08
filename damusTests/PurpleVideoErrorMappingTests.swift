//
//  PurpleVideoErrorMappingTests.swift
//  damusTests
//
//  Turning the Purple hosted-video API's refusals into things a person can act
//  on.
//
//  There is one test per refusal the routes can answer, including the ones a
//  happy path never sees, because the whole value of this layer is what it does
//  on the day something goes wrong. Every body is copied verbatim from the
//  API's own fixture, so a server-side change to a refusal breaks a test here
//  rather than reaching a user as "upload failed".
//

import XCTest
@testable import damus

final class PurpleVideoErrorMappingTests: XCTestCase {

    // MARK: - Authentication

    func testA401CarriesNoCodeAndStillMapsCleanly() {
        // It comes from the NIP-98 middleware's `{"error": ...}` envelope, not
        // from the video routes' `{error, code, ...}` one, so a mapper that
        // requires a `code` throws on the most common failure there is.
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(401, PurpleVideoFixtures.refusalUnauthenticated))

        XCTAssertEqual(error, .unauthenticated(serverProvidedDetail: "Nostr authorization header missing"))
        XCTAssertTrue(error.shouldReportToSentry)
    }

    // MARK: - Subscription

    func testAPubkeyWithNoPurpleAccountIsToldASubscriptionIsRequired() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(403, PurpleVideoFixtures.refusalSubscriptionMissing))

        XCTAssertEqual(error, .subscriptionRequired(serverProvidedDetail: "Account not found"))
        XCTAssertFalse(error.shouldReportToSentry)
    }

    func testALapsedSubscriberGetsTheSameCaseAsSomeoneWhoNeverSubscribed() {
        // Both are `code: "subscription_required"`; only the English differs.
        // Branching on that sentence to choose between a sign-up CTA and a
        // renew CTA is exactly the thing that breaks silently, so the prose is
        // kept for diagnostics and nothing else.
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(403, PurpleVideoFixtures.refusalSubscriptionExpired))

        XCTAssertEqual(error, .subscriptionRequired(serverProvidedDetail: "Account expired"))
        XCTAssertEqual(error.failureReason, "Account expired")
        XCTAssertEqual(error.errorDescription, PurpleVideoAPIError.subscriptionRequired(serverProvidedDetail: "Account not found").errorDescription)
    }

    // MARK: - Requests this client should not have sent

    func testTheThreeMalformedRequestRefusalsAreReportedAsClientBugs() {
        let cases: [(String, String, String)] = [
            (PurpleVideoFixtures.refusalInvalidDeclaredBytes, "invalid_declared_bytes", "Declared upload size must be a positive whole number of bytes"),
            (PurpleVideoFixtures.refusalInvalidDuration, "invalid_duration", "Declared duration must be a positive number of seconds"),
            (PurpleVideoFixtures.refusalInvalidTitle, "invalid_title", "Title must be a string"),
        ]

        for (body, code, prose) in cases {
            let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(400, body))
            XCTAssertEqual(error, .invalidRequest(code: code, serverProvidedDetail: prose), "for \(code)")
            XCTAssertTrue(error.shouldReportToSentry, "for \(code)")
        }
    }

    // MARK: - Per-video limits

    func testAVideoPastThePerVideoSizeLimitIsRefusedWithItsAllowance() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(422, PurpleVideoFixtures.refusalVideoTooLarge))

        XCTAssertEqual(error, .videoTooLarge(
            quota: PurpleVideoQuota(usedStoredBytes: 0, limitStoredBytes: 2000, remainingStoredBytes: 2000, windowSeconds: 2_592_000),
            serverProvidedDetail: "Video is larger than the 1000 byte per-video limit"
        ))
        XCTAssertFalse(error.shouldReportToSentry)
    }

    func testAVideoPastThePerVideoDurationLimitIsRefusedWithItsAllowance() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(422, PurpleVideoFixtures.refusalVideoTooLong))

        XCTAssertEqual(error, .videoTooLong(
            quota: PurpleVideoQuota(usedStoredBytes: 0, limitStoredBytes: 2000, remainingStoredBytes: 2000, windowSeconds: 2_592_000),
            serverProvidedDetail: "Video is longer than the 600 second per-video limit"
        ))
    }

    func testTheLimitItselfStaysInTheServersProseAndOutOfOurCopy() throws {
        // The `422` bodies name the limit only inside an English sentence, and
        // the `quota` block beside them is in *stored* bytes, which is not the
        // same unit as the file the user picked. So our copy carries no number
        // and the sentence stays in `failureReason` — parsing it out is how a
        // client ends up telling someone "2 GB max" about a 0.21x-encoded
        // allowance.
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(422, PurpleVideoFixtures.refusalVideoTooLarge))

        let copy = try XCTUnwrap(error.errorDescription)
        XCTAssertFalse(copy.contains("1000"), "the localised copy must not quote a limit it cannot know")
        XCTAssertEqual(error.failureReason, "Video is larger than the 1000 byte per-video limit")
    }

    // MARK: - Allowance and pacing

    func testTheRollingMonthlyAllowanceIsRefusedWithTheSpentQuota() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(402, PurpleVideoFixtures.refusalMonthlyQuota))

        XCTAssertEqual(error, .monthlyQuotaExceeded(
            quota: PurpleVideoQuota(usedStoredBytes: 2000, limitStoredBytes: 2000, remainingStoredBytes: 0, windowSeconds: 2_592_000),
            serverProvidedDetail: "Video would exceed your monthly hosted-video allowance"
        ))
        XCTAssertEqual(error.quota?.remainingStoredBytes, 0)
        XCTAssertFalse(error.shouldReportToSentry)
    }

    func testTooManyPendingUploadsReportsHowManyAndTheMaximum() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(429, PurpleVideoFixtures.refusalTooManyPending))

        XCTAssertEqual(error, .tooManyPendingUploads(pending: 3, max: 3))
        XCTAssertEqual(error.errorDescription?.contains("3"), true)
    }

    func testThePendingCountAndTheMaximumComeFromDifferentFields() {
        // The fixture happens to have them equal, which would hide reading one
        // key twice.
        let body = PurpleVideoFixtures.refusalTooManyPending
            .replacingOccurrences(of: "\"max_pending_uploads\":3", with: "\"max_pending_uploads\":5")
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(429, body))

        XCTAssertEqual(error, .tooManyPendingUploads(pending: 3, max: 5))
    }

    // MARK: - Ownership and lifecycle

    func testSomeoneElsesVideoIsIndistinguishableFromOneThatDoesNotExist() {
        // Deliberate: a guid is the public playback URL, so a 403 would
        // disclose for nothing.
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(404, PurpleVideoFixtures.refusalVideoNotFound))

        XCTAssertEqual(error, .videoNotFound)
        XCTAssertFalse(error.shouldReportToSentry)
    }

    func testADeletedVideoAnswersWithItsTombstone() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(410, PurpleVideoFixtures.refusalVideoDeleted))

        XCTAssertEqual(error, .videoDeleted(
            videoId: "4fc2d3b2-fa74-42df-8fce-9f107a7c28ba",
            deletedAt: Date(timeIntervalSince1970: 1_706_659_200)
        ))
        XCTAssertFalse(error.shouldReportToSentry)
    }

    // MARK: - The service, rather than the caller

    func testAProviderFailureIsRetryableAndSaysSo() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(502, PurpleVideoFixtures.refusalProviderUnreachable))

        XCTAssertEqual(error, .providerUnreachable)
        XCTAssertEqual(error.errorDescription?.contains("try again"), true)
    }

    func testAVideoObjectWeCouldNotRecordIsAServerError() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(500, PurpleVideoFixtures.refusalVideoRowFailed))

        XCTAssertEqual(error, .serverError(
            code: "video_row_failed",
            serverProvidedDetail: "Could not record the upload. Please try again."
        ))
        XCTAssertTrue(error.shouldReportToSentry)
    }

    func testTheRustOnlyInternalErrorMapsEvenThoughTodaysDeploymentCannotSendIt() {
        // The Node implementation's store is LMDB and a read on a live
        // environment does not fail; the Rust port's Postgres can be down.
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(500, PurpleVideoFixtures.refusalInternalError))

        XCTAssertEqual(error, .serverError(code: "internal_error", serverProvidedDetail: "Internal server error"))
    }

    func testADeploymentWithNoVideoProviderSaysSoRatherThanFailingObscurely() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(503, PurpleVideoFixtures.refusalVideoUnavailable))

        XCTAssertEqual(error, .hostedVideoUnavailable)
    }

    func testA404ThatIsNotTheApisOwnBodyIsAnUnmountedRoute() {
        // What an older deployment, or one with the video routes off, looks
        // like from outside. Reporting it as "video not found" would send the
        // user hunting for a video that was never the problem.
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.html(404, "<!DOCTYPE html><html><body>Cannot GET /video/x</body></html>\n"))

        XCTAssertEqual(error, .routeNotAvailable)
    }

    // MARK: - Bodies that are not JSON at all

    func testAnHtmlBadRequestIsARefusalRatherThanADecodeCrash() {
        // Express answers a body that is valid JSON but not an object with its
        // own HTML error page, before any handler runs.
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.html(400, PurpleVideoFixtures.htmlBadRequest))

        XCTAssertEqual(error, .unrecognizedRefusal(status: 400, code: nil, serverProvidedDetail: nil))
        XCTAssertTrue(error.shouldReportToSentry)
    }

    func testAnHtmlInternalServerErrorIsARefusalRatherThanADecodeCrash() {
        // A nonsensical route knob, which the deployed express app re-reads
        // from its environment on every request.
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.html(500, PurpleVideoFixtures.htmlInternalServerError))

        XCTAssertEqual(error, .unrecognizedRefusal(status: 500, code: nil, serverProvidedDetail: nil))
    }

    func testAnHtmlErrorPageNeverReachesCopyWhole() throws {
        // A `bodySnippet` is what a report carries; an entire error page is not.
        let response = PurpleVideoFixtures.html(500, String(repeating: "<p>boom</p>", count: 100))
        let snippet = try XCTUnwrap(response.bodySnippet)
        XCTAssertEqual(snippet.count, 201)
        XCTAssertTrue(snippet.hasSuffix("…"))
    }

    // MARK: - Refusals this build has never seen

    func testAnUnrecognisedCodeFallsBackToTheServersOwnProse() {
        let body = "{\"error\":\"Uploads are paused for maintenance\",\"code\":\"maintenance_window\"}\n"
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(503, body))

        XCTAssertEqual(error, .unrecognizedRefusal(
            status: 503, code: "maintenance_window", serverProvidedDetail: "Uploads are paused for maintenance"
        ))
        XCTAssertEqual(error.errorDescription, "Uploads are paused for maintenance")
    }

    func testAnUnrecognisedCodeWithNoProseStillHasCopy() {
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(418, "{\"code\":\"teapot\"}\n"))

        XCTAssertEqual(error, .unrecognizedRefusal(status: 418, code: "teapot", serverProvidedDetail: nil))
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    func testTheCodeDecidesRatherThanTheStatus() {
        // Status is not discriminating — 403 carries two messages, 500 carries
        // two codes, 404 carries two meanings — so a refusal is classified by
        // its code wherever it has one.
        let error = PurpleVideoWire.refusal(PurpleVideoFixtures.json(499, PurpleVideoFixtures.refusalVideoNotFound))

        XCTAssertEqual(error, .videoNotFound)
    }

    // MARK: - Success bodies that are not

    func testATruncatedSuccessBodyIsMalformedRatherThanAnEmptyModel() {
        XCTAssertThrowsError(try PurpleVideoWire.authorization(PurpleVideoFixtures.json(200, PurpleVideoFixtures.truncatedJSON))) { error in
            guard case .malformedSuccessBody = error as? PurpleVideoAPIError else {
                return XCTFail("expected malformedSuccessBody, got \(error)")
            }
        }
    }

    func testASuccessBodyOfTheWrongShapeIsMalformed() {
        XCTAssertThrowsError(try PurpleVideoWire.status(PurpleVideoFixtures.json(200, PurpleVideoFixtures.jsonOfTheWrongShape))) { error in
            guard case .malformedSuccessBody = error as? PurpleVideoAPIError else {
                return XCTFail("expected malformedSuccessBody, got \(error)")
            }
        }
    }

    // MARK: - The guarantee Swift 5 cannot give us

    /// Swift 5 has no typed throws, so "only `PurpleVideoAPIError` escapes the
    /// wire layer" is not something the compiler can promise. This test is the
    /// enforcement mechanism: a raw `DecodingError` reaching a call site is how
    /// a person ends up reading "The data couldn't be read because it is
    /// missing." about their video.
    func testOnlyPurpleVideoAPIErrorEverEscapes() {
        let bodies: [(String, PurpleVideoHTTPResponse)] = [
            ("truncated json", PurpleVideoFixtures.json(200, PurpleVideoFixtures.truncatedJSON)),
            ("wrong shape", PurpleVideoFixtures.json(200, PurpleVideoFixtures.jsonOfTheWrongShape)),
            ("empty 200", PurpleVideoFixtures.json(200, "")),
            ("html 200", PurpleVideoFixtures.html(200, PurpleVideoFixtures.htmlBadRequest)),
            ("binary 200", PurpleVideoFixtures.untyped(200, PurpleVideoFixtures.binaryGarbage)),
            ("binary 500", PurpleVideoFixtures.untyped(500, PurpleVideoFixtures.binaryGarbage)),
            ("empty 502", PurpleVideoFixtures.untyped(502, Data())),
            ("html 400", PurpleVideoFixtures.html(400, PurpleVideoFixtures.htmlBadRequest)),
            ("html 500", PurpleVideoFixtures.html(500, PurpleVideoFixtures.htmlInternalServerError)),
            ("json refusal", PurpleVideoFixtures.json(402, PurpleVideoFixtures.refusalMonthlyQuota)),
            ("status body to authorize", PurpleVideoFixtures.json(200, PurpleVideoFixtures.statusReadyClean)),
            ("authorize body to delete", PurpleVideoFixtures.json(200, PurpleVideoFixtures.authorize200)),
        ]

        for (name, response) in bodies {
            for (route, call) in decoders() {
                do {
                    _ = try call(response)
                } catch let error as PurpleVideoAPIError {
                    XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(route) on \(name) has no copy")
                } catch {
                    XCTFail("\(route) on \(name) threw \(type(of: error)): \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Every entry point that decodes a response, so a new one cannot be added
    /// without the escape-hatch test covering it.
    private func decoders() -> [(String, (PurpleVideoHTTPResponse) throws -> Any)] {
        [
            ("authorization", { try PurpleVideoWire.authorization($0) }),
            ("status", { try PurpleVideoWire.status($0) }),
            ("deletion", { try PurpleVideoWire.deletion($0) }),
        ]
    }
}
