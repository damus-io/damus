//
//  PurpleVideoWire.swift
//  damus
//
//  The pure half of the Purple hosted-video client: bytes in, model or typed
//  error out.
//
//  Everything that can be wrong about a response is decided here, with no
//  `URLSession`, no clock and no disk, because `make_nip98_authenticated_request`
//  hardwires `URLSession.shared` and this repo has no `URLProtocol` stub or
//  `URLSessionProtocol` seam to fake it with. Rather than register a protocol
//  class globally on the shared session — which would intercept relay
//  connections and image loads for every other test in the process — the
//  decode and the refusal mapping are lifted out where they can be tested
//  against the API's own fixture bytes. `PurpleVideoAPIClient` is then thin
//  enough to be covered by a real call.
//

import Foundation

/// A response, reduced to the three things the wire layer needs.
///
/// A struct rather than a tuple so the header lookup can be case-insensitive:
/// `HTTPURLResponse.allHeaderFields` preserves whatever casing the server sent,
/// and express does not promise `Content-Type` over `content-type`.
struct PurpleVideoHTTPResponse: Equatable, Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data

    init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    init(http: HTTPURLResponse, body: Data) {
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let key = key as? String else { continue }
            headers[key] = String(describing: value)
        }
        self.init(status: http.statusCode, headers: headers, body: body)
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var contentType: String? { header("Content-Type") }

    /// Whether the body is worth handing to a JSON decoder.
    ///
    /// The deployed express app answers some failures with `text/html`: a
    /// request body that is valid JSON but not an object is rejected by
    /// body-parser before any handler runs, and a misconfigured route knob
    /// throws per-request. Checking first is what keeps those from becoming a
    /// decode error rather than the refusal they are.
    var isJSON: Bool {
        guard let contentType else { return false }
        return contentType.lowercased().contains("json")
    }

    /// At most a couple of lines of the body, for diagnostics.
    ///
    /// Capped so an HTML error page never lands whole in a Sentry event.
    var bodySnippet: String? {
        guard !body.isEmpty, let text = String(data: body, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > 200 else { return trimmed }
        return String(trimmed.prefix(200)) + "…"
    }
}

/// Every refusal body the video routes can send, flattened into one shape.
///
/// One optional-heavy struct rather than six decode attempts, so
/// `PurpleVideoWire.refusal` is a flat `switch` on `code`. A 401 comes from the
/// NIP-98 middleware's `{"error": ...}` envelope rather than the video routes'
/// own, so `code` is optional.
private struct PurpleVideoErrorEnvelope: Decodable {
    let error: String?
    let code: String?
    let quota: PurpleVideoQuota?
    let pendingUploads: Int?
    let maxPendingUploads: Int?
    let videoId: PurpleVideoID?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case error
        case code
        case quota
        case pendingUploads = "pending_uploads"
        case maxPendingUploads = "max_pending_uploads"
        case videoId = "video_id"
        case deletedAt = "deleted_at"
    }
}

enum PurpleVideoWire {
    /// The one decoder these types are read with.
    ///
    /// No `keyDecodingStrategy` — see `PurpleVideoModels.swift` for why that
    /// would break every TUS upload — and `.secondsSince1970`, because the API
    /// speaks unix seconds and Foundation's default would read them as seconds
    /// since 2001.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    // MARK: - Successful shapes

    /// Decodes `POST /video`.
    ///
    /// Also checks that all four TUS header keys arrived. A missing one is a
    /// `malformedSuccessBody` here rather than a bare 401 with an empty body
    /// from the provider twenty minutes into an upload.
    static func authorization(_ response: PurpleVideoHTTPResponse) throws -> PurpleVideoAuthorization {
        let authorization: PurpleVideoAuthorization = try decode(response)
        let missing = PurpleVideoTusHeaderKey.required.filter { authorization.tusHeaders[$0] == nil }
        guard missing.isEmpty else {
            throw PurpleVideoAPIError.malformedSuccessBody(
                detail: "authorization is missing TUS headers: \(missing.sorted().joined(separator: ", "))"
            )
        }
        return authorization
    }

    /// Decodes `GET /video/{id}`.
    static func status(_ response: PurpleVideoHTTPResponse) throws -> PurpleVideoStatus {
        try decode(response)
    }

    /// Decodes `DELETE /video/{id}`.
    static func deletion(_ response: PurpleVideoHTTPResponse) throws -> PurpleVideoDeletion {
        try decode(response)
    }

    private static func decode<T: Decodable>(_ response: PurpleVideoHTTPResponse) throws -> T {
        guard (200...299).contains(response.status) else {
            throw refusal(response)
        }
        do {
            return try decoder.decode(T.self, from: response.body)
        } catch {
            throw PurpleVideoAPIError.malformedSuccessBody(detail: String(describing: error))
        }
    }

    // MARK: - Refusals

    /// Maps a non-2xx response onto the refusal it represents.
    ///
    /// Precedence, and the reason for it:
    ///
    /// 1. **401 first** — it is the only refusal with no `code`, because it
    ///    comes from the NIP-98 middleware rather than these routes.
    /// 2. **`code` beats status** — status is not discriminating. 403 carries
    ///    two different messages under one code, 500 carries two different
    ///    codes, and 404 means both "no such video" and "not yours".
    /// 3. **A 404 that is not the API's own body** is the routes not being
    ///    mounted, which is what a deployment with no video provider looks like
    ///    from the outside.
    /// 4. Anything else keeps the server's prose and reports itself.
    static func refusal(_ response: PurpleVideoHTTPResponse) -> PurpleVideoAPIError {
        let envelope = response.isJSON
            ? try? decoder.decode(PurpleVideoErrorEnvelope.self, from: response.body)
            : nil
        let detail = envelope?.error

        guard response.status != 401 else {
            return .unauthenticated(serverProvidedDetail: detail)
        }

        guard let rawCode = envelope?.code else {
            guard response.status != 404 else { return .routeNotAvailable }
            return .unrecognizedRefusal(status: response.status, code: nil, serverProvidedDetail: detail)
        }

        guard let code = PurpleVideoRefusalCode(rawValue: rawCode) else {
            return .unrecognizedRefusal(status: response.status, code: rawCode, serverProvidedDetail: detail)
        }

        switch code {
        case .subscriptionRequired:
            return .subscriptionRequired(serverProvidedDetail: detail)
        case .videoTooLarge:
            return .videoTooLarge(quota: envelope?.quota, serverProvidedDetail: detail)
        case .videoTooLong:
            return .videoTooLong(quota: envelope?.quota, serverProvidedDetail: detail)
        case .monthlyQuotaExceeded:
            return .monthlyQuotaExceeded(quota: envelope?.quota, serverProvidedDetail: detail)
        case .tooManyPendingUploads:
            return .tooManyPendingUploads(pending: envelope?.pendingUploads, max: envelope?.maxPendingUploads)
        case .videoNotFound:
            return .videoNotFound
        case .videoDeleted:
            return .videoDeleted(videoId: envelope?.videoId, deletedAt: envelope?.deletedAt)
        case .videoProviderError:
            return .providerUnreachable
        case .videoUnavailable:
            return .hostedVideoUnavailable
        case .invalidDeclaredBytes, .invalidDuration, .invalidTitle:
            return .invalidRequest(code: rawCode, serverProvidedDetail: detail)
        case .videoRowFailed, .internalError:
            return .serverError(code: rawCode, serverProvidedDetail: detail)
        }
    }
}
