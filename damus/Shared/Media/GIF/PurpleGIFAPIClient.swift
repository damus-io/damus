//
//  PurpleGIFAPIClient.swift
//  damus
//

import Foundation
import Sentry

/// Detailed context for GIF API errors, used for diagnostics and error reporting.
struct GIFAPIErrorContext {
    /// The full HTTP response body from the server
    let serverResponse: String?
    /// HTTP status code returned by the server
    let statusCode: Int?
    /// The URL that was requested
    let requestURL: String?
    /// The NIP-98 authentication event that was sent (without sensitive private key data)
    let nip98Event: String?
    /// The timestamp when the request was made
    let timestamp: Date
    /// Extracted error message from server response (from "error" or "message" JSON key)
    let extractedMessage: String?
    
    /// Returns a formatted string suitable for logging and user-facing technical info
    var debugDescription: String {
        var parts: [String] = []
        parts.append("timestamp=\(timestamp.ISO8601Format())")
        if let url = requestURL { parts.append("url=\(url)") }
        if let status = statusCode { parts.append("status=\(status)") }
        if let response = serverResponse { parts.append("server_response=\(response)") }
        if let event = nip98Event { parts.append("nip98_event=\(event)") }
        return parts.joined(separator: "; ")
    }
}

enum PurpleGIFAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse(context: GIFAPIErrorContext?)
    case unauthorized(context: GIFAPIErrorContext?)
    case upstreamError(statusCode: Int, message: String?, context: GIFAPIErrorContext?)
    case networkError(Error, context: GIFAPIErrorContext?)
    case decodingError(Error, rawResponse: String?, context: GIFAPIErrorContext?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid GIF service URL", comment: "Error message for invalid Purple GIF URL")
        case .invalidResponse:
            return NSLocalizedString("Invalid response from GIF service", comment: "Error message for invalid Purple GIF response")
        case .unauthorized:
            return NSLocalizedString("Purple subscription required to use GIF search", comment: "Error message shown when the user is not authorized to use Purple GIF endpoints")
        case .upstreamError(_, let message, _):
            return message ?? NSLocalizedString("GIF service is temporarily unavailable", comment: "Error message shown when the Purple GIF service fails")
        case .networkError(let error, _):
            return error.localizedDescription
        case .decodingError:
            return NSLocalizedString("Failed to parse GIF data", comment: "Error message for GIF decoding failure")
        }
    }
    
    /// Returns the error context for diagnostic purposes
    var context: GIFAPIErrorContext? {
        switch self {
        case .invalidURL:
            return nil
        case .invalidResponse(let context),
             .unauthorized(let context),
             .upstreamError(_, _, let context),
             .networkError(_, let context),
             .decodingError(_, _, let context):
            return context
        }
    }
}

actor PurpleGIFAPIClient {
    /// The Purple proxy used to access KLIPY GIF endpoints.
    let purple: DamusPurple
    private let decoder = JSONDecoder()

    /// Initializes a Purple-backed GIF API client.
    init(purple: DamusPurple) {
        self.purple = purple
    }

    /// Fetches featured GIFs from the Purple KLIPY proxy.
    func fetchFeatured(limit: Int = 30, pos: String? = nil) async throws -> GIFSearchResponse {
        var url = purple.environment.api_base_url()
        url.append(path: "/gifs/featured")
        url.append(queryItems: [
            .init(name: "limit", value: String(limit))
        ])

        if let pos, !pos.isEmpty {
            url.append(queryItems: [.init(name: "pos", value: pos)])
        }

        return try await performRequest(url: url)
    }

    /// Searches GIFs from the Purple KLIPY proxy.
    func search(query: String, page: Int = 1, perPage: Int = 30) async throws -> GIFSearchResponse {
        var url = purple.environment.api_base_url()
        url.append(path: "/gifs/search")
        url.append(queryItems: [
            .init(name: "q", value: query),
            .init(name: "page", value: String(page)),
            .init(name: "per_page", value: String(perPage))
        ])

        return try await performRequest(url: url)
    }

    /// Performs an authenticated request against the Purple GIF proxy.
    private func performRequest(url: URL) async throws -> GIFSearchResponse {
        let requestTimestamp = Date()
        
        // Create NIP-98 event once and reuse it for both the request and error context
        guard let nip98Event = create_nip98_auth_event(
            method: .get,
            url: url,
            payload: nil,
            auth_keypair: purple.keypair
        ) else {
            throw PurpleGIFAPIError.invalidURL
        }
        
        let nip98EventJSON: String?
        if let data = try? encode_json_data(nip98Event) {
            nip98EventJSON = String(data: data, encoding: .utf8)
        } else {
            nip98EventJSON = nil
        }
        
        do {
            // Use the pre-built event to ensure the actual auth event sent matches what we log
            let (data, response) = try await make_nip98_authenticated_request(
                method: .get,
                url: url,
                payload: nil,
                payload_type: nil,
                auth_note: nip98Event
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                let context = GIFAPIErrorContext(
                    serverResponse: String(data: data, encoding: .utf8),
                    statusCode: nil,
                    requestURL: url.absoluteString,
                    nip98Event: nip98EventJSON,
                    timestamp: requestTimestamp,
                    extractedMessage: extractErrorMessage(from: data)
                )
                let error = PurpleGIFAPIError.invalidResponse(context: context)
                reportErrorToSentry(error, context: context)
                throw error
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapHTTPError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    url: url,
                    nip98Event: nip98EventJSON,
                    timestamp: requestTimestamp
                )
            }

            do {
                return try decoder.decode(GIFSearchResponse.self, from: data)
            } catch let decodingError as DecodingError {
                let rawResponse = String(data: data, encoding: .utf8)
                let context = GIFAPIErrorContext(
                    serverResponse: rawResponse,
                    statusCode: httpResponse.statusCode,
                    requestURL: url.absoluteString,
                    nip98Event: nip98EventJSON,
                    timestamp: requestTimestamp,
                    extractedMessage: extractErrorMessage(from: data)
                )
                let error = PurpleGIFAPIError.decodingError(decodingError, rawResponse: rawResponse, context: context)
                reportErrorToSentry(error, context: context)
                throw error
            }
        } catch let error as PurpleGIFAPIError {
            // Error already has context and was already reported to Sentry
            throw error
        } catch {
            let context = GIFAPIErrorContext(
                serverResponse: nil,
                statusCode: nil,
                requestURL: url.absoluteString,
                nip98Event: nip98EventJSON,
                timestamp: requestTimestamp,
                extractedMessage: nil
            )
            let gifError = PurpleGIFAPIError.networkError(error, context: context)
            reportErrorToSentry(gifError, context: context)
            throw gifError
        }
    }

    /// Maps HTTP failures from the Purple proxy into localized client errors.
    private func mapHTTPError(statusCode: Int, data: Data, url: URL, nip98Event: String?, timestamp: Date) -> PurpleGIFAPIError {
        let serverResponse = String(data: data, encoding: .utf8)
        let message = extractErrorMessage(from: data)
        
        let context = GIFAPIErrorContext(
            serverResponse: serverResponse,
            statusCode: statusCode,
            requestURL: url.absoluteString,
            nip98Event: nip98Event,
            timestamp: timestamp,
            extractedMessage: message
        )
        
        let error: PurpleGIFAPIError
        if statusCode == 401 {
            error = .unauthorized(context: context)
        } else {
            error = .upstreamError(statusCode: statusCode, message: message, context: context)
        }
        
        reportErrorToSentry(error, context: context)
        return error
    }

    /// Extracts a human-readable error message from a JSON or text payload.
    private func extractErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? String, !error.isEmpty {
                return error
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
        }

        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return nil
        }

        return text
    }
    
    /// Reports GIF API errors to Sentry with basic diagnostic context.
    ///
    /// Only includes non-sensitive information: HTTP status code, server error message,
    /// and timestamp. No URLs, query parameters, or auth details are sent.
    private func reportErrorToSentry(_ error: PurpleGIFAPIError, context: GIFAPIErrorContext?) {
        DamusSentry.captureSentryError(error) { scope in
            scope.setContext(value: [
                "error_type": String(describing: error),
                "timestamp": context?.timestamp.ISO8601Format() ?? "unknown",
                "status_code": context?.statusCode ?? "none",
                "server_error_message": context?.extractedMessage ?? "none"
            ], key: "gif_api_error")
            
            // Add tags for easier filtering in Sentry
            if let statusCode = context?.statusCode {
                scope.setTag(value: String(statusCode), key: "http_status")
            }
            
            scope.setTag(value: "gif_api", key: "error_source")
        }
    }
}
