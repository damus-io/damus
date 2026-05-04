//
//  PurpleGIFAPIClient.swift
//  damus
//

import Foundation

enum PurpleGIFAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case upstreamError(statusCode: Int, message: String?)
    case networkError(Error)
    case decodingError(Error, rawResponse: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid GIF service URL", comment: "Error message for invalid Purple GIF URL")
        case .invalidResponse:
            return NSLocalizedString("Invalid response from GIF service", comment: "Error message for invalid Purple GIF response")
        case .unauthorized:
            return NSLocalizedString("Purple subscription required to use GIF search", comment: "Error message shown when the user is not authorized to use Purple GIF endpoints")
        case .upstreamError(_, let message):
            return message ?? NSLocalizedString("GIF service is temporarily unavailable", comment: "Error message shown when the Purple GIF service fails")
        case .networkError(let error):
            return error.localizedDescription
        case .decodingError:
            return NSLocalizedString("Failed to parse GIF data", comment: "Error message for GIF decoding failure")
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
        do {
            let (data, response) = try await make_nip98_authenticated_request(
                method: .get,
                url: url,
                payload: nil,
                payload_type: nil,
                auth_keypair: purple.keypair
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PurpleGIFAPIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapHTTPError(statusCode: httpResponse.statusCode, data: data)
            }

            do {
                return try decoder.decode(GIFSearchResponse.self, from: data)
            } catch let decodingError as DecodingError {
                let rawResponse = String(data: data, encoding: .utf8)
                throw PurpleGIFAPIError.decodingError(decodingError, rawResponse: rawResponse)
            }
        } catch let error as PurpleGIFAPIError {
            throw error
        } catch {
            throw PurpleGIFAPIError.networkError(error)
        }
    }

    /// Maps HTTP failures from the Purple proxy into localized client errors.
    private func mapHTTPError(statusCode: Int, data: Data) -> PurpleGIFAPIError {
        if statusCode == 401 {
            return .unauthorized
        }

        let message = extractErrorMessage(from: data)
        return .upstreamError(statusCode: statusCode, message: message)
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
}
