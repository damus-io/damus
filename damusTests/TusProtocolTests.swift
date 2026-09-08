//
//  TusProtocolTests.swift
//  damusTests
//
//  Created by Daniel D'Aquino on 2026-09-05.
//
//  Covers the pure half of the tus client: request construction, response
//  parsing, retry classification and backoff. No server, no disk, no clock.
//

import XCTest
@testable import damus

final class TusProtocolTests: XCTestCase {
    let endpoint = URL(string: "https://video.example.com/tus/files")!
    let uploadURL = URL(string: "https://video.example.com/tus/files/abc123")!

    // MARK: - Metadata encoding

    func testMetadataIsBase64EncodedAndSorted() {
        let encoded = TusRequest.encodeMetadata(["filename": "clip.mov", "authorization": "sig"])
        // Sorted by key so the header is byte-stable across runs, which matters
        // for any server that signs over it.
        XCTAssertEqual(encoded, "authorization \(b64("sig")),filename \(b64("clip.mov"))")
    }

    func testMetadataEncodesNonAsciiValues() {
        let encoded = TusRequest.encodeMetadata(["filename": "vidéo 🎬.mov"])
        XCTAssertEqual(encoded, "filename \(b64("vidéo 🎬.mov"))")
        // And round-trips.
        let payload = encoded!.split(separator: " ")[1]
        let decoded = String(data: Data(base64Encoded: String(payload))!, encoding: .utf8)
        XCTAssertEqual(decoded, "vidéo 🎬.mov")
    }

    func testMetadataEmitsBareKeyForEmptyValue() {
        XCTAssertEqual(TusRequest.encodeMetadata(["draft": ""]), "draft")
    }

    func testMetadataDropsKeysThatCannotBeRepresented() {
        // A space or comma in a key would be parsed as a separator by the
        // server, silently corrupting neighbouring pairs.
        XCTAssertEqual(TusRequest.encodeMetadata(["bad key": "x", "ok": "y"]), "ok \(b64("y"))")
        XCTAssertEqual(TusRequest.encodeMetadata(["bad,key": "x"]), nil)
        XCTAssertNil(TusRequest.encodeMetadata([:]))
    }

    // MARK: - Request construction

    func testCreationRequestCarriesLengthMetadataAndCallerHeaders() {
        let request = TusRequest.creation(
            endpoint: endpoint,
            length: 850_000_000,
            metadata: ["filename": "clip.mov"],
            headers: ["AuthorizationSignature": "deadbeef", "LibraryId": "42"]
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Upload-Length"), "850000000")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Tus-Resumable"), "1.0.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Upload-Metadata"), "filename \(b64("clip.mov"))")
        // Caller headers are what Bunny authenticates with; they must survive.
        XCTAssertEqual(request.value(forHTTPHeaderField: "AuthorizationSignature"), "deadbeef")
        XCTAssertEqual(request.value(forHTTPHeaderField: "LibraryId"), "42")
    }

    func testCreationRequestOmitsMetadataHeaderWhenThereIsNone() {
        let request = TusRequest.creation(endpoint: endpoint, length: 1, metadata: [:], headers: [:])
        XCTAssertNil(request.value(forHTTPHeaderField: "Upload-Metadata"))
    }

    func testPatchRequestUsesTheOffsetContentType() {
        let request = TusRequest.patch(uploadURL: uploadURL, offset: 4_194_304, contentLength: 8_388_608, headers: ["X-Auth": "t"])
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Upload-Offset"), "4194304")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/offset+octet-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Tus-Resumable"), "1.0.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Auth"), "t")
    }

    func testHeadRequestBypassesCache() {
        let request = TusRequest.head(uploadURL: uploadURL, headers: [:])
        XCTAssertEqual(request.httpMethod, "HEAD")
        // Resuming from a cached offset would silently corrupt the upload.
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    }

    func testTerminationRequestIsADelete() {
        let request = TusRequest.termination(uploadURL: uploadURL, headers: [:])
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Tus-Resumable"), "1.0.0")
    }

    func testCallerHeadersCannotOverrideTheProtocolVersion() {
        let request = TusRequest.patch(uploadURL: uploadURL, offset: 0, contentLength: 1, headers: ["Tus-Resumable": "0.2.2"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Tus-Resumable"), "1.0.0")
    }

    // MARK: - Response parsing

    func testOffsetIsParsedCaseInsensitively() {
        let response = http(status: 204, headers: ["upload-offset": "12345"])
        XCTAssertEqual(TusResponse.offset(from: response), 12345)
    }

    func testOffsetIsNilWhenAbsentOrGarbage() {
        XCTAssertNil(TusResponse.offset(from: http(status: 204, headers: [:])))
        XCTAssertNil(TusResponse.offset(from: http(status: 204, headers: ["Upload-Offset": "banana"])))
    }

    func testAbsoluteLocationIsUsedAsIs() {
        let response = http(status: 201, headers: ["Location": "https://cdn.example.com/tus/xyz"])
        XCTAssertEqual(
            TusResponse.location(from: response, relativeTo: endpoint),
            URL(string: "https://cdn.example.com/tus/xyz")
        )
    }

    func testRelativeLocationIsResolvedAgainstTheCreationEndpoint() {
        // tusd answers with a path, not an absolute URL.
        let response = http(status: 201, headers: ["Location": "/files/xyz789"])
        XCTAssertEqual(
            TusResponse.location(from: response, relativeTo: endpoint),
            URL(string: "https://video.example.com/files/xyz789")
        )
    }

    func testMissingLocationIsNil() {
        XCTAssertNil(TusResponse.location(from: http(status: 201, headers: [:]), relativeTo: endpoint))
        XCTAssertNil(TusResponse.location(from: http(status: 201, headers: ["Location": "  "]), relativeTo: endpoint))
    }

    // MARK: - Retry classification

    func testExpiredAuthorizationAndMissingUploadsAreFatal() {
        for status in [400, 401, 403, 404, 410, 412, 413, 415, 460] {
            XCTAssertEqual(TusRetryPolicy.forStatus(status), .fatal, "HTTP \(status) should not be retried")
        }
    }

    func testTransientStatusesAreRetried() {
        for status in [408, 423, 429, 500, 502, 503, 504] {
            XCTAssertEqual(TusRetryPolicy.forStatus(status), .retry, "HTTP \(status) should be retried")
        }
    }

    func testOffsetConflictTriggersAResync() {
        XCTAssertEqual(TusRetryPolicy.forStatus(409), .resync)
    }

    func testAuthorizationFailuresAskTheCallerToReauthorize() {
        XCTAssertTrue(TusUploadClient.mapStatus(401).needsReauthorization)
        XCTAssertTrue(TusUploadClient.mapStatus(403).needsReauthorization)
        XCTAssertTrue(TusUploadClient.mapStatus(404).needsReauthorization)
        XCTAssertTrue(TusUploadClient.mapStatus(410).needsReauthorization)
        XCTAssertFalse(TusUploadClient.mapStatus(500).needsReauthorization)
        XCTAssertFalse(TusUploadError.transport("offline").needsReauthorization)
    }

    // MARK: - Backoff

    func testBackoffGrowsExponentiallyAndCaps() {
        let backoff = TusBackoff(base: 1, multiplier: 2, maxDelay: 30, jitter: 0)
        XCTAssertEqual(backoff.delay(forAttempt: 1, randomness: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(backoff.delay(forAttempt: 2, randomness: 1), 2, accuracy: 0.0001)
        XCTAssertEqual(backoff.delay(forAttempt: 3, randomness: 1), 4, accuracy: 0.0001)
        XCTAssertEqual(backoff.delay(forAttempt: 6, randomness: 1), 30, accuracy: 0.0001)
        XCTAssertEqual(backoff.delay(forAttempt: 40, randomness: 1), 30, accuracy: 0.0001)
    }

    func testJitterOnlyEverShortensTheDelay() {
        let backoff = TusBackoff(base: 4, multiplier: 2, maxDelay: 60, jitter: 0.25)
        // randomness 0 = full jitter applied, randomness 1 = none.
        XCTAssertEqual(backoff.delay(forAttempt: 1, randomness: 0), 3, accuracy: 0.0001)
        XCTAssertEqual(backoff.delay(forAttempt: 1, randomness: 1), 4, accuracy: 0.0001)
        XCTAssertEqual(backoff.delay(forAttempt: 1, randomness: 0.5), 3.5, accuracy: 0.0001)
    }

    func testBackoffIsZeroBeforeTheFirstRetry() {
        XCTAssertEqual(TusBackoff().delay(forAttempt: 0, randomness: 1), 0)
    }

    // MARK: - Helpers

    private func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }

    private func http(status: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: uploadURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}
