//
//  TenorAPIClient.swift
//  damus
//
//  Created by eric on 12/11/25.
//

import Foundation

enum TenorAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case missingAPIKey
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid URL", comment: "Error message for invalid Tenor URL")
        case .networkError(let error):
            return error.localizedDescription
        case .decodingError:
            return NSLocalizedString("Failed to parse GIF data", comment: "Error message for Tenor decoding failure")
        case .missingAPIKey:
            return NSLocalizedString("Tenor API key not configured", comment: "Error message for missing Tenor API key")
        case .invalidResponse:
            return NSLocalizedString("Invalid response from server", comment: "Error message for invalid Tenor response")
        }
    }
}

actor TenorAPIClient {
    private let baseURL = "https://tenor.googleapis.com/v2"
    private let decoder = JSONDecoder()

    private var apiKey: String? {
        let userKey = UserSettingsStore.shared?.tenor_api_key
        if let userKey, !userKey.isEmpty {
            return userKey
        }
        return Secrets.TENOR_API_KEY
    }

    func fetchFeatured(limit: Int = 30, pos: String? = nil) async throws -> TenorSearchResponse {
        guard let apiKey else {
            throw TenorAPIError.missingAPIKey
        }

        var components = URLComponents(string: "\(baseURL)/featured")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "media_filter", value: "gif,mediumgif,tinygif"),
            URLQueryItem(name: "contentfilter", value: "medium")
        ]

        if let pos {
            components?.queryItems?.append(URLQueryItem(name: "pos", value: pos))
        }

        guard let url = components?.url else {
            throw TenorAPIError.invalidURL
        }

        return try await performRequest(url: url)
    }

    func search(query: String, limit: Int = 30, pos: String? = nil) async throws -> TenorSearchResponse {
        guard let apiKey else {
            throw TenorAPIError.missingAPIKey
        }

        var components = URLComponents(string: "\(baseURL)/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "media_filter", value: "gif,mediumgif,tinygif"),
            URLQueryItem(name: "contentfilter", value: "medium")
        ]

        if let pos {
            components?.queryItems?.append(URLQueryItem(name: "pos", value: pos))
        }

        guard let url = components?.url else {
            throw TenorAPIError.invalidURL
        }

        return try await performRequest(url: url)
    }

    private func performRequest(url: URL) async throws -> TenorSearchResponse {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw TenorAPIError.invalidResponse
            }

            return try decoder.decode(TenorSearchResponse.self, from: data)
        } catch let error as TenorAPIError {
            throw error
        } catch let error as DecodingError {
            throw TenorAPIError.decodingError(error)
        } catch {
            throw TenorAPIError.networkError(error)
        }
    }
}
