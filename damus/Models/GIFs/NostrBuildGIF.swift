//
//  NostrBuildGIF.swift
//  damus
//
//  Created by eric on 8/14/24.
//

import Foundation

let pageSize: Int = 30

func makeGIFRequest(cursor: Int) async throws -> NostrBuildGIFResponse {
    var request = URLRequest(url: URL(string: String(format: "https://nostr.build/api/v2/gifs/get?cursor=%d&limit=%d&random=%d",
                                                          cursor,
                                                          pageSize,
                                                          0))!)

    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let response: NostrBuildGIFResponse = try await decodedData(for: request)
    return response
}

private func decodedData<Output: Decodable>(for request: URLRequest) async throws -> Output {
    let decoder = JSONDecoder()
    let session = URLSession.shared
    let (data, response) = try await session.data(for: request)
    
    if let httpResponse = response as? HTTPURLResponse {
        switch httpResponse.statusCode {
            case 200:
                let result = try decoder.decode(Output.self, from: data)
                return result
            default:
            Log.error("Error retrieving gif data from Nostr Build. HTTP status code: %d; Response: %s", for: .gif_request, httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown")
                throw NostrBuildError.http_response_error(status_code: httpResponse.statusCode, response: data)
        }
    }
    
    throw NostrBuildError.could_not_process_response
}

enum NostrBuildError: Error {
    case http_response_error(status_code: Int, response: Data)
    case could_not_process_response
}

struct NostrBuildGIFResponse: Codable {
    let status: String
    let message: String
    let cursor: Int
    let count: Int
    let gifs: [NostrBuildGif]
}

struct NostrBuildGif: Codable, Identifiable {
    var id: String { bh }
    var url: String
    /// This is the blurhash of the gif that can be used as an ID and placeholder
    let bh: String
}
