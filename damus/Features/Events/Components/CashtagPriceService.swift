//
//  CashtagPriceService.swift
//  damus
//
//  Fetches ticker prices from Ciphering (ciphering.io) with a small
//  in-memory cache so a busy timeline doesn't hammer the API.
//

import Foundation

/// Price snapshot for a single ticker as returned by Ciphering.
struct CashtagPrice: Decodable, Equatable {
    /// Ticker, e.g. "BTC".
    let symbol: String
    /// Current price in USD.
    let price: Double
    /// 24h change as a percentage, e.g. -2.35 for -2.35%.
    let change24h: Double
    /// Hourly closes for the last 24h, oldest first. Optional so the card
    /// still renders if the API omits it.
    let sparkline: [Double]?
    /// ISO-8601 timestamp of when the price was sampled.
    let updatedAt: String?
}

/// Loads and caches `CashtagPrice` values. Safe to call from any context;
/// all network work runs off the main thread.
actor CashtagPriceService {
    static let shared = CashtagPriceService()

    /// Base URL for the Ciphering price endpoint.
    /// Final URL: `{base}/{SYMBOL}` → e.g. `https://ciphering.io/api/price/BTC`
    static let baseURL = URL(string: "https://ciphering.io/api/price")!

    /// How long a cached price stays fresh.
    private let ttl: TimeInterval = 60

    private struct Entry {
        let price: CashtagPrice
        let fetchedAt: Date
    }

    private var cache: [String: Entry] = [:]
    private var inflight: [String: Task<CashtagPrice, Error>] = [:]

    /// Returns a price for `symbol`, from cache if fresh, otherwise fetched.
    /// Concurrent callers for the same symbol share a single request.
    func price(for symbol: String) async throws -> CashtagPrice {
        let key = symbol.uppercased()

        if let entry = cache[key], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.price
        }

        if let task = inflight[key] {
            return try await task.value
        }

        let task = Task<CashtagPrice, Error> {
            let url = Self.baseURL.appendingPathComponent(key)
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: req)

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(CashtagPrice.self, from: data)
        }

        inflight[key] = task
        defer { inflight[key] = nil }

        let price = try await task.value
        cache[key] = Entry(price: price, fetchedAt: Date())
        return price
    }
}
