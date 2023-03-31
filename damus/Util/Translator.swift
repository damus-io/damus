//
//  Translator.swift
//  damus
//
//  Created by Terry Yiu on 2/4/23.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Translator {
    private let userSettingsStore: UserSettingsStore
    private let session = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(_ userSettingsStore: UserSettingsStore) {
        self.userSettingsStore = userSettingsStore
    }

    public func translate(_ text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String? {
        switch userSettingsStore.translation_service {
        case .libretranslate:
            return try await translateWithLibreTranslate(text, from: sourceLanguage, to: targetLanguage)
        case .deepl:
            return try await translateWithDeepL(text, from: sourceLanguage, to: targetLanguage)
        case .none:
            return text
        }
    }

    private func translateWithLibreTranslate(_ text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String? {
        let url = try makeURL(userSettingsStore.libretranslate_url, path: "/translate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct RequestBody: Encodable {
            let q: String
            let source: String
            let target: String
            let api_key: String?
        }
        let body = RequestBody(q: text, source: sourceLanguage, target: targetLanguage, api_key: userSettingsStore.libretranslate_api_key)
        request.httpBody = try encoder.encode(body)

        struct Response: Decodable {
            let translatedText: String
        }
        let response: Response = try await decodedData(for: request)
        return response.translatedText
    }

    private func translateWithDeepL(_ text: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String? {
        if userSettingsStore.deepl_api_key == "" {
            return nil
        }

        let url = try makeURL(userSettingsStore.deepl_plan.model.url, path: "/v2/translate")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(userSettingsStore.deepl_api_key)", forHTTPHeaderField: "Authorization")

        struct RequestBody: Encodable {
            let text: [String]
            let source_lang: String
            let target_lang: String
        }
        let body = RequestBody(text: [text], source_lang: sourceLanguage.uppercased(), target_lang: targetLanguage.uppercased())
        request.httpBody = try encoder.encode(body)

        struct Response: Decodable {
            let translations: [DeepLTranslations]
        }
        struct DeepLTranslations: Decodable {
            let detected_source_language: String
            let text: String
        }

        let response: Response = try await decodedData(for: request)
        return response.translations.map { $0.text }.joined(separator: " ")
    }

    private func makeURL(_ baseUrl: String, path: String) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw URLError(.badURL)
        }
        components.path = path
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private func decodedData<Output: Decodable>(for request: URLRequest) async throws -> Output {
        let data = try await session.data(for: request)
        let result = try decoder.decode(Output.self, from: data)
        return result
    }
}

private extension URLSession {
    func data(for request: URLRequest) async throws -> Data {
        var task: URLSessionDataTask?
        let onCancel = { task?.cancel() }
        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { continuation in
                    task = dataTask(with: request) { data, _, error in
                        guard let data = data else {
                            let error = error ?? URLError(.badServerResponse)
                            return continuation.resume(throwing: error)
                        }
                        continuation.resume(returning: data)
                    }
                    task?.resume()
                }
            },
            onCancel: { onCancel() }
        )
    }
}
