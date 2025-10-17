//
//  TenorAPI.swift
//  damus
//
//  Tenor API client for GIF search
//

import Foundation

/// Client for Tenor GIF API
/// Note: This is optional and only used if users want to search beyond Nostr GIFs
@MainActor
class TenorAPI: ObservableObject {
    static let shared = TenorAPI()

    // Google's Tenor API key for testing
    // In production, this should be configured per-user or use damus's key
    private let apiKey = "AIzaSyAyimkuYQYF_FXVALexPuGQctUWRURdCYQ"
    private let baseURL = "https://tenor.googleapis.com/v2"

    private init() {}

    /// Search for GIFs on Tenor
    func search(query: String, limit: Int = 20) async throws -> [TenorGIF] {
        guard !query.isEmpty else { return [] }

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        let urlString = "\(baseURL)/search?q=\(encodedQuery)&key=\(apiKey)&client_key=damus&limit=\(limit)&media_filter=gif"

        guard let url = URL(string: urlString) else {
            throw TenorError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TenorResponse.self, from: data)

        return response.results
    }

    /// Get trending/featured GIFs
    func featured(limit: Int = 20) async throws -> [TenorGIF] {
        let urlString = "\(baseURL)/featured?key=\(apiKey)&client_key=damus&limit=\(limit)&media_filter=gif"

        guard let url = URL(string: urlString) else {
            throw TenorError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TenorResponse.self, from: data)

        return response.results
    }

    enum TenorError: Error {
        case invalidURL
        case networkError
        case decodingError
    }
}
