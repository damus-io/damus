//
//  PurpleVideoAPIClient.swift
//  damus
//
//  The transport half of the Purple hosted-video client: three NIP-98
//  authenticated calls, and nothing else.
//
//  Everything that can be decided without a network is in `PurpleVideoRoutes`
//  and `PurpleVideoWire`, which are pure and covered by tests against the
//  API's own fixture bytes. What is left here is ~25 lines of plumbing, which
//  is deliberate: `make_nip98_authenticated_request` hardwires
//  `URLSession.shared`, so anything left in this file is only reachable by a
//  real call.
//
//  Standalone, like `PurpleGIFAPIClient`: constructed with a `DamusPurple` by
//  whoever owns an upload. It is deliberately **not** an `extension
//  DamusPurple` and not hung off `DamusState` — `DamusPurple.swift` compiles
//  into three targets, and reaching these types from it would drag them into
//  builds that have no business with them.
//

import Foundation

/// Talks to Damus Purple's hosted-video routes as the signed-in user.
///
/// Using `purple.environment.api_base_url()` is what makes local, staging and
/// production work with no extra plumbing — including the developer setting
/// that points the app at a Purple API on localhost.
///
/// Known limitation: requests inherit `URLSession.shared`'s 60-second timeout,
/// because the NIP-98 helper owns the session. That is fine for these three
/// calls, all of which are small and fast, but it is not configurable from
/// here.
actor PurpleVideoAPIClient {
    /// The Purple account these calls are made as.
    let purple: DamusPurple

    init(purple: DamusPurple) {
        self.purple = purple
    }

    // MARK: - Routes

    /// `POST /video` — asks Purple for permission to upload one video.
    ///
    /// The returned authorization already contains the public playback URL:
    /// the provider hands back a guid at creation time, before a byte is
    /// uploaded, and it never changes. Waiting for the encode is only about
    /// not publishing a link to a video that cannot play yet.
    ///
    /// - Parameters:
    ///   - declaredBytes: The size of the file about to be uploaded. The
    ///     server reserves against the subscriber's allowance on this number,
    ///     so it must be the real size.
    ///   - durationSeconds: Optional. Lets the server refuse an over-long
    ///     video before anything is created.
    ///   - title: Optional. Passed through untouched — the server strips
    ///     control characters and caps the length deterministically, and
    ///     duplicating that here would be two implementations of one rule.
    /// - Throws: `PurpleVideoAPIError` for anything the API said, or a
    ///   `URLError` for a transport failure. The interesting refusals are
    ///   `.subscriptionRequired`, `.videoTooLarge`, `.videoTooLong`,
    ///   `.monthlyQuotaExceeded` and `.tooManyPendingUploads`.
    func authorizeUpload(
        declaredBytes: Int,
        durationSeconds: Int? = nil,
        title: String? = nil
    ) async throws -> PurpleVideoAuthorization {
        guard declaredBytes > 0 else {
            // The server would refuse this as `invalid_declared_bytes`; there
            // is no reason to spend a round trip finding that out.
            throw PurpleVideoAPIError.invalidDeclaredBytes(declaredBytes)
        }

        let url = PurpleVideoRoutes.authorize(base: purple.environment.api_base_url())
        let payload = try encode(AuthorizeUploadRequest(
            declaredBytes: declaredBytes, durationSeconds: durationSeconds, title: title
        ))
        let response = try await send(method: .post, url: url, payload: payload)
        return try wire(response) { try PurpleVideoWire.authorization($0) }
    }

    /// `GET /video/{id}` — where one video's encode has got to.
    ///
    /// A `stale: true` answer is **not** an error: the server could not reach
    /// the provider and is serving the last row it has. Keep polling.
    ///
    /// - Throws: `PurpleVideoAPIError` — notably `.videoNotFound` for a video
    ///   that does not exist *or* belongs to someone else, and `.videoDeleted`
    ///   for one that has been tombstoned.
    func videoStatus(videoId: PurpleVideoID) async throws -> PurpleVideoStatus {
        let url = try PurpleVideoRoutes.video(base: purple.environment.api_base_url(), id: videoId)
        let response = try await send(method: .get, url: url, payload: nil)
        return try wire(response) { try PurpleVideoWire.status($0) }
    }

    /// `DELETE /video/{id}` — remove a video, or release an authorization
    /// whose bytes never arrived.
    ///
    /// Idempotent: deleting twice answers 200 with `alreadyDeleted` set.
    /// Deleting does not refund stored bytes inside the rolling window.
    func deleteVideo(videoId: PurpleVideoID) async throws -> PurpleVideoDeletion {
        let url = try PurpleVideoRoutes.video(base: purple.environment.api_base_url(), id: videoId)
        let response = try await send(method: .delete, url: url, payload: nil)
        return try wire(response) { try PurpleVideoWire.deletion($0) }
    }

    // Deliberately absent: `refreshAuthorization(videoId:)`.
    //
    // Re-minting TUS credentials for an upload already in flight is the right
    // fix for an expiring signature — the spike proved that re-minting *before*
    // expiry resumes the same upload at the right offset, while after expiry
    // the session is destroyed and the bytes are gone. But the API has no route
    // for it: `POST /video` creates a *new* object with a *new* guid, so it
    // cannot refresh anything. A stub here would be dead code pretending
    // otherwise.
    //
    // The route to ask for is `POST /video/{id}/authorization`, answering
    // `{expiry, authorization_signature, tus_headers, upload_deadline}` for a
    // non-terminal, non-expired, owned row. What Phase 7 can honestly deliver
    // instead is the *shape*: `expiry` and `uploadDeadline` on the
    // authorization and on `PendingVideo`, and `tusHeaders` in exactly the
    // `[String: String]` form `TusUploadClient.updateHeaders(for:headers:)`
    // takes.

    // MARK: - Plumbing

    /// Signs and sends one request, and reduces the answer to what the wire
    /// layer needs.
    private func send(method: HTTPMethod, url: URL, payload: Data?) async throws -> PurpleVideoHTTPResponse {
        let (data, response) = try await make_nip98_authenticated_request(
            method: method,
            url: url,
            payload: payload,
            payload_type: payload == nil ? nil : .json,
            auth_keypair: purple.keypair
        )

        guard let http = response as? HTTPURLResponse else {
            throw PurpleVideoAPIError.malformedSuccessBody(detail: "not an HTTP response")
        }
        return PurpleVideoHTTPResponse(http: http, body: data)
    }

    /// Runs a wire decode, reporting the failures that mean something is broken.
    ///
    /// Normal refusals — an unsubscribed user, a spent allowance — are not
    /// reported: they are the system working, and reporting them turns Sentry
    /// into a usage log.
    private func wire<T>(
        _ response: PurpleVideoHTTPResponse,
        _ decode: (PurpleVideoHTTPResponse) throws -> T
    ) throws -> T {
        do {
            return try decode(response)
        } catch let error as PurpleVideoAPIError {
            report(error, response: response)
            throw error
        }
    }

    private func report(_ error: PurpleVideoAPIError, response: PurpleVideoHTTPResponse) {
        guard error.shouldReportToSentry else { return }
        DamusSentry.captureSentryError(error) { scope in
            scope.setTag(value: "purple_video_api", key: "error_source")
            scope.setTag(value: String(response.status), key: "http_status")
            scope.setContext(value: [
                "error_type": String(describing: error),
                "status_code": response.status,
                "content_type": response.contentType ?? "none",
                "body_snippet": response.bodySnippet ?? "none",
            ], key: "purple_video_api_error")
        }
    }

    private func encode(_ request: AuthorizeUploadRequest) throws -> Data {
        let encoder = JSONEncoder()
        // Stable bytes, so the NIP-98 payload hash is over something
        // reproducible when a request has to be inspected in a log.
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(request)
        } catch {
            throw PurpleVideoAPIError.malformedSuccessBody(detail: "could not encode the request: \(error)")
        }
    }
}

/// The `POST /video` request body.
///
/// `declared_bytes` is what the allowance is reserved against, so it is
/// required; the other two are hints the server uses to refuse early.
private struct AuthorizeUploadRequest: Encodable {
    let declaredBytes: Int
    let durationSeconds: Int?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case declaredBytes = "declared_bytes"
        case durationSeconds = "duration_seconds"
        case title
    }
}
