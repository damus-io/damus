//
//  PurpleVideoAPIError.swift
//  damus
//
//  Every way a Purple hosted-video call can fail, as one typed error.
//
//  The card's ask was "surface those as messages a human can act on, not a
//  generic upload failure", so the cases are the API's *refusals* rather than
//  HTTP status codes: one case per thing a person or an operator could
//  actually do about it.
//
//  Localisation policy, stated once: `NSLocalizedString` for the cases a
//  person can cause and for the ones that will reach a screen; plain literals
//  for the cases that mean this client or the server is broken — all of which
//  set `shouldReportToSentry`, and none of which a person can act on. That is
//  the same rule `TusUploadError` follows by having no localised copy at all:
//  every case there is a diagnostic.
//

import Foundation

/// The refusal codes the video routes can answer with.
///
/// The `code` is what the app branches on. The `error` prose beside it is
/// English written for a log, and is deliberately never parsed — see
/// `PurpleVideoAPIError.failureReason`.
enum PurpleVideoRefusalCode: String, Equatable, Sendable {
    case subscriptionRequired = "subscription_required"
    case invalidDeclaredBytes = "invalid_declared_bytes"
    case invalidDuration = "invalid_duration"
    case invalidTitle = "invalid_title"
    case videoTooLarge = "video_too_large"
    case videoTooLong = "video_too_long"
    case monthlyQuotaExceeded = "monthly_quota_exceeded"
    case tooManyPendingUploads = "too_many_pending_uploads"
    case videoNotFound = "video_not_found"
    case videoDeleted = "video_deleted"
    case videoProviderError = "video_provider_error"
    case videoRowFailed = "video_row_failed"
    case videoUnavailable = "video_unavailable"
    case internalError = "internal_error"
}

/// The only error type `PurpleVideoWire` and `PurpleVideoAPIClient` throw for
/// anything they can classify.
///
/// Swift 5 has no typed throws, so "only this escapes" is enforced by
/// `PurpleVideoErrorMappingTests.testOnlyPurpleVideoAPIErrorEverEscapes`
/// rather than by the compiler. Transport failures are the deliberate
/// exception: a `URLError` from `URLSession` already carries copy a person can
/// act on ("The Internet connection appears to be offline"), and re-wrapping
/// it would only hide that.
///
/// `Equatable` so the tests can be table-driven over the fixture bodies, which
/// is why the decode failure carries a flattened `String` rather than the
/// underlying `DecodingError`.
enum PurpleVideoAPIError: Error, LocalizedError, Equatable {

    // MARK: Refusals a person caused, and can resolve

    /// 403. Covers both "no Purple account" and "subscription lapsed" — the
    /// server answers both with this one code and distinguishes them only in
    /// English prose, which is preserved in `failureReason` and deliberately
    /// not branched on.
    case subscriptionRequired(serverProvidedDetail: String?)
    /// 422. The per-video byte limit. The limit itself appears only inside the
    /// server's English sentence, so the localised copy carries no number.
    case videoTooLarge(quota: PurpleVideoQuota?, serverProvidedDetail: String?)
    /// 422. The per-video duration limit. Same prose caveat as `videoTooLarge`.
    case videoTooLong(quota: PurpleVideoQuota?, serverProvidedDetail: String?)
    /// 402. The rolling monthly allowance.
    case monthlyQuotaExceeded(quota: PurpleVideoQuota?, serverProvidedDetail: String?)
    /// 429. Too many authorizations are still waiting for their bytes.
    case tooManyPendingUploads(pending: Int?, max: Int?)
    /// 404. Also what a video belonging to someone else answers — a guid is the
    /// public playback URL, so 403 would disclose for nothing.
    case videoNotFound
    /// 410. The video was deleted; the row is a tombstone.
    case videoDeleted(videoId: PurpleVideoID?, deletedAt: Date?)

    // MARK: The service is unwell, and it is not the caller's fault

    /// 502. The server could not reach the video provider. Retryable.
    case providerUnreachable
    /// 503. Hosted video is not configured on this deployment.
    case hostedVideoUnavailable
    /// A 404 that is not the API's `video_not_found` body — the route is not
    /// mounted, which is what a deployment with no video provider looks like
    /// from outside.
    case routeNotAvailable

    // MARK: This client or the server is broken

    /// 400 `invalid_*`. Means this client built a bad request.
    case invalidRequest(code: String, serverProvidedDetail: String?)
    /// 401. The NIP-98 event was missing, malformed, or did not match the
    /// request. In practice that is a signed-URL mismatch, which is why
    /// `PurpleVideoRoutes` builds the URL once and pure.
    case unauthenticated(serverProvidedDetail: String?)
    /// 500 `video_row_failed` or `internal_error`.
    case serverError(code: String, serverProvidedDetail: String?)
    /// A refusal shape this build does not recognise.
    case unrecognizedRefusal(status: Int, code: String?, serverProvidedDetail: String?)
    /// A 2xx whose body did not decode, or decoded without something required.
    case malformedSuccessBody(detail: String)
    /// A video id that cannot be safely put in a URL path. Never reaches the
    /// network.
    case invalidVideoID(PurpleVideoID)
    /// A declared size the server would refuse anyway. Caught locally to save
    /// a round trip.
    case invalidDeclaredBytes(Int)

    // MARK: - Reporting

    /// Whether this is worth a Sentry event.
    ///
    /// Normal refusals are not: a subscriber hitting their monthly allowance is
    /// the system working, and reporting it turns Sentry into a usage log.
    /// Everything else means something is wrong with this client, the server,
    /// or the deployment.
    var shouldReportToSentry: Bool {
        switch self {
        case .subscriptionRequired, .videoTooLarge, .videoTooLong,
             .monthlyQuotaExceeded, .tooManyPendingUploads, .videoNotFound,
             .videoDeleted:
            return false
        case .providerUnreachable, .hostedVideoUnavailable, .routeNotAvailable,
             .invalidRequest, .unauthenticated, .serverError,
             .unrecognizedRefusal, .malformedSuccessBody, .invalidVideoID,
             .invalidDeclaredBytes:
            return true
        }
    }

    // MARK: - Copy

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired:
            return NSLocalizedString("A Damus Purple subscription is required to upload videos.", comment: "Error shown when a non-subscriber tries to upload a video to Damus Purple hosting")
        case .videoTooLarge:
            return NSLocalizedString("This video is too large to upload to Damus Purple.", comment: "Error shown when a video exceeds the Damus Purple per-video size limit")
        case .videoTooLong:
            return NSLocalizedString("This video is too long to upload to Damus Purple.", comment: "Error shown when a video exceeds the Damus Purple per-video duration limit")
        case .monthlyQuotaExceeded:
            return NSLocalizedString("This video would go over your monthly Damus Purple video allowance.", comment: "Error shown when a video would exceed the subscriber's rolling monthly hosted-video allowance")
        case .tooManyPendingUploads(let pending, let max):
            guard let pending, let max else {
                return NSLocalizedString("Too many video uploads are still finishing. Finish or cancel one before starting another.", comment: "Error shown when the subscriber has too many hosted-video uploads waiting for their bytes")
            }
            let format = NSLocalizedString("You have %1$d of %2$d video uploads still finishing. Finish or cancel one before starting another.", comment: "Error shown when the subscriber has too many hosted-video uploads waiting for their bytes. %1$d is how many are waiting, %2$d is the maximum allowed.")
            return String(format: format, pending, max)
        case .videoNotFound:
            return NSLocalizedString("That video is no longer available.", comment: "Error shown when a hosted video does not exist, or belongs to someone else")
        case .videoDeleted:
            return NSLocalizedString("That video was deleted.", comment: "Error shown when a hosted video has been deleted")
        case .providerUnreachable:
            return NSLocalizedString("Could not reach the video service. Please try again.", comment: "Error shown when the Damus Purple API cannot reach its video provider")
        case .hostedVideoUnavailable:
            return NSLocalizedString("Video hosting is not available on this server.", comment: "Error shown when hosted video is not configured on the Damus Purple deployment being used")
        case .routeNotAvailable:
            return NSLocalizedString("Video hosting is not available on this server.", comment: "Error shown when the Damus Purple deployment does not serve the hosted-video routes at all")
        case .unrecognizedRefusal(_, _, let detail):
            // The server's own prose is the best copy available for a refusal
            // this build has never seen.
            return detail ?? NSLocalizedString("Damus Purple could not upload this video.", comment: "Generic error shown when the Damus Purple video API refuses a request for a reason this app version does not recognise")
        case .malformedSuccessBody:
            return NSLocalizedString("Damus Purple sent a response this app could not read.", comment: "Error shown when the Damus Purple video API returns a success response the app cannot decode")
        case .invalidRequest(let code, let detail):
            return "Damus Purple rejected the request (\(code)). \(detail ?? "")"
                .trimmingCharacters(in: .whitespaces)
        case .unauthenticated(let detail):
            return "Damus Purple rejected the authentication for this request. \(detail ?? "")"
                .trimmingCharacters(in: .whitespaces)
        case .serverError(let code, let detail):
            return "Damus Purple failed to handle the request (\(code)). \(detail ?? "")"
                .trimmingCharacters(in: .whitespaces)
        case .invalidVideoID(let id):
            return "Not a usable video id: \(id)"
        case .invalidDeclaredBytes(let bytes):
            return "Not a usable upload size: \(bytes) bytes"
        }
    }

    /// The server's own English sentence, where it sent one.
    ///
    /// Kept because it is the only place the `422` limits appear on the wire
    /// (`"...than the 1000 byte per-video limit"`) and the only thing that
    /// distinguishes "Account not found" from "Account expired". Both belong in
    /// diagnostics and in a details line — **never** in a regex, and never as
    /// the thing a CTA branches on.
    var failureReason: String? {
        switch self {
        case .subscriptionRequired(let detail),
             .videoTooLarge(_, let detail),
             .videoTooLong(_, let detail),
             .monthlyQuotaExceeded(_, let detail),
             .invalidRequest(_, let detail),
             .unauthenticated(let detail),
             .serverError(_, let detail),
             .unrecognizedRefusal(_, _, let detail):
            return detail
        case .malformedSuccessBody(let detail):
            return detail
        case .tooManyPendingUploads, .videoNotFound, .videoDeleted,
             .providerUnreachable, .hostedVideoUnavailable, .routeNotAvailable,
             .invalidVideoID, .invalidDeclaredBytes:
            return nil
        }
    }

    /// The allowance the server reported alongside a refusal, when it sent one.
    ///
    /// In **stored** bytes; see `PurpleVideoQuota`.
    var quota: PurpleVideoQuota? {
        switch self {
        case .videoTooLarge(let quota, _), .videoTooLong(let quota, _),
             .monthlyQuotaExceeded(let quota, _):
            return quota
        default:
            return nil
        }
    }
}
