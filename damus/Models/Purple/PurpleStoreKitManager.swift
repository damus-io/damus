//
//  PurpleStoreKitManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-02-09.
//

import Foundation
import StoreKit

extension DamusPurple {
    struct StoreKitManager {
        var delegate: DamusPurpleStoreKitManagerDelegate? = nil
        
        struct PurchasedProduct {
            let tx: StoreKit.Transaction
            let product: Product
        }
        
        init() {
            self.start()
        }
        
        func start() {
            Task {
                try await monitor_updates()
            }
        }
        
        func get_products() async throws -> [Product] {
            return try await Product.products(for: DamusPurpleType.allCases.map({ $0.rawValue }))
        }
        
        private func monitor_updates() async throws {
            for await update in StoreKit.Transaction.updates {
                switch update {
                    case .verified(let tx):
                        let products = try await self.get_products()
                        let prod = products.filter({ prod in tx.productID == prod.id }).first
                        
                        if let prod,
                           let expiration = tx.expirationDate,
                           Date.now < expiration
                        {
                            self.delegate?.product_was_purchased(product: PurchasedProduct(tx: tx, product: prod))
                        }
                    case .unverified:
                        continue
                }
            }
        }
        
        func purchase(product: Product) async throws -> Product.PurchaseResult {
            return try await product.purchase(options: [])
        }
    }
}

extension DamusPurple.StoreKitManager {
    enum DamusPurpleType: String, CaseIterable {
        case yearly = "purpleyearly"
        case monthly = "purple"
        
        func non_discounted_price(product: Product) -> String? {
            switch self {
                case .yearly:
                    return (product.price * 1.1984569224).formatted(product.priceFormatStyle)
                case .monthly:
                    return nil
            }
        }
        
        func label() -> String {
            switch self {
                case .yearly:
                    return NSLocalizedString("Annually", comment: "Annual renewal of purple subscription")
                case .monthly:
                    return NSLocalizedString("Monthly", comment: "Monthly renewal of purple subscription")
            }
        }
    }
}

protocol DamusPurpleStoreKitManagerDelegate {
    func product_was_purchased(product: DamusPurple.StoreKitManager.PurchasedProduct)
}
