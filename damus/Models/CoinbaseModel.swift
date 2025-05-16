//
//  CoinbaseModel.swift
//  damus
//
//  Created by eric on 4/24/25.
//

import Foundation
import SwiftUI

class CoinbaseModel: ObservableObject {
    
    @Published var btcPrice: Double? = nil {
        didSet {
            if let btcPrice = btcPrice {
                cachePrice(btcPrice)
            }
        }
    }
    
    var cacheKey: String {
        "btc_price_\(currency.lowercased())"
    }
    
    var currency: String = Locale.current.currency?.identifier ?? "USD"
    
    let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    func satsToFiat(input: Int64) -> String {
        guard let btcPrice = btcPrice, input > 0 else {
            return ""
        }
        let fiat = (Double(input) / 100_000_000) * btcPrice
        let amount = numberFormatter.string(from: NSNumber(value: fiat)) ?? ""
        let symbol: String = numberFormatter.currencySymbol
        if symbol.isEmpty || symbol == currency {
            return amount + " " + currency
        }
        return symbol + amount + " " + currency
    }
    
    func fetchFromCoinbase() {
        let urlString = "https://api.coinbase.com/v2/prices/BTC-\(currency)/spot"
        guard let url = URL(string: urlString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(CoinbaseResponse.self, from: data)
                DispatchQueue.main.async {
                    self.btcPrice = decoded.data.amount
                }
            } catch {
                print("Failed to fetch BTC price from Coinbase: \(error)")
            }
        }
    }
    
    private func cachePrice(_ price: Double) {
        UserDefaults.standard.set(price, forKey: cacheKey)
    }
    
    func loadCachedPrice() {
        let cached = UserDefaults.standard.double(forKey: cacheKey)
        if cached > 0 {
            btcPrice = cached
        }
    }
}

struct CoinbaseResponse: Codable {
    let data: CoinbasePrice
}

struct CoinbasePrice: Codable {
    let amount: Double
}

