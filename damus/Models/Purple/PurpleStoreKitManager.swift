//
//  PurpleStoreKitManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-02-09.
//

import Foundation
import StoreKit

extension DamusPurple {
    class StoreKitManager { // Has to be a class to get around Swift-imposed limitations of mutations on concurrently executing code associated with the purchase update monitoring task.
        // The delegate is any object that wants to be notified of successful purchases. (e.g. A view that needs to update its UI)
        var delegate: DamusPurpleStoreKitManagerDelegate? = nil {
            didSet {
                // Whenever the delegate is set, send it all recorded transactions to make sure it's up to date.
                Task {
                    Log.info("Delegate changed. Try sending all recorded valid product transactions", for: .damus_purple)
                    guard let new_delegate = delegate else {
                        Log.info("Delegate is nil. Cannot send recorded product transactions", for: .damus_purple)
                        return
                    }
                    Log.info("Sending all %d recorded valid product transactions", for: .damus_purple, self.recorded_purchased_products.count)
                    
                    for purchased_product in self.recorded_purchased_products {
                        new_delegate.product_was_purchased(product: purchased_product)
                        Log.info("Sent StoreKit tx to delegate", for: .damus_purple)
                    }
                }
            }
        }
        // Keep track of all recorded purchases so that we can send them to the delegate when it's set (whenever it's set)
        var recorded_purchased_products: [PurchasedProduct] = []
        
        // Helper struct to keep track of a purchased product and its transaction
        struct PurchasedProduct {
            let tx: StoreKit.Transaction
            let product: Product
        }
        
        // Singleton instance of StoreKitManager. To avoid losing purchase updates, there should only be one instance of StoreKitManager on the app.
        static let standard = StoreKitManager()
        
        init() {
            Log.info("Initiliazing StoreKitManager", for: .damus_purple)
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
        
        // Use this function to manually and immediately record a purchased product update
        func record_purchased_product(_ purchased_product: PurchasedProduct) {
            self.recorded_purchased_products.append(purchased_product)
            self.delegate?.product_was_purchased(product: purchased_product)
        }
        
        // This function starts a task that monitors StoreKit updates and sends them to the delegate.
        // This function will run indefinitely (It should never return), so it is important to run this as a background task.
        private func monitor_updates() async throws {
            Log.info("Monitoring StoreKit updates", for: .damus_purple)
            // StoreKit.Transaction.updates is an async stream that emits updates whenever a purchase is verified.
            for await update in StoreKit.Transaction.updates {
                switch update {
                    case .verified(let tx):
                        let products = try await self.get_products()
                        let prod = products.filter({ prod in tx.productID == prod.id }).first
                        
                        if let prod,
                           let expiration = tx.expirationDate,
                           Date.now < expiration
                        {
                            Log.info("Received valid transaction update from StoreKit", for: .damus_purple)
                            let purchased_product = PurchasedProduct(tx: tx, product: prod)
                            self.recorded_purchased_products.append(purchased_product)
                            self.delegate?.product_was_purchased(product: purchased_product)
                            Log.info("Sent tx to delegate (if exists)", for: .damus_purple)
                        }
                    case .unverified:
                        continue
                }
            }
        }
        
        // Use this function to complete a StoreKit purchase
        // Specify the product and the app account token (UUID) to complete the purchase
        // The account token is used to associate with the user's account on the server.
        func purchase(product: Product, id: UUID) async throws -> Product.PurchaseResult {
            return try await product.purchase(options: [.appAccountToken(id)])
        }
    }
}

extension DamusPurple.StoreKitManager {
    // This helper struct is used to encapsulate StoreKit products, metadata, and supplement with additional information
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

// This protocol is used to describe the delegate of the StoreKitManager, which will receive updates.
protocol DamusPurpleStoreKitManagerDelegate {
    func product_was_purchased(product: DamusPurple.StoreKitManager.PurchasedProduct)
}
