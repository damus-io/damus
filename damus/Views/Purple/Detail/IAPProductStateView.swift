//
//  PurchasedProductView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-02-09.
//

import SwiftUI
import StoreKit

// MARK: - IAPProductStateView

extension DamusPurpleView {
    typealias PurchasedProduct = DamusPurple.StoreKitManager.PurchasedProduct
    
    struct IAPProductStateView: View {
        let products: ProductState
        let purchased: PurchasedProduct?
        let subscribe: (Product) async throws -> Void
        
        var body: some View {
            switch self.products {
                case .failed:
                    PurpleViewPrimitives.ProductLoadErrorView()
                case .loaded(let products):
                    if let purchased {
                        PurchasedView(purchased)
                    } else {
                        ProductsView(products)
                    }
                case .loading:
                    ProgressView()
                        .progressViewStyle(.circular)
            }
        }
        
        func PurchasedView(_ purchased: PurchasedProduct) -> some View {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Purchased!", comment: "User purchased a subscription"))
                    .font(.title2)
                    .foregroundColor(.white)
                price_description(product: purchased.product)
                    .foregroundColor(.white)
                    .opacity(0.65)
                    .frame(width: 200)
                Text(NSLocalizedString("Purchased on", comment: "Indicating when the user purchased the subscription"))
                    .font(.title2)
                    .foregroundColor(.white)
                Text(format_date(date: purchased.tx.purchaseDate))
                    .foregroundColor(.white)
                    .opacity(0.65)
                if let expiry = purchased.tx.expirationDate {
                    Text(NSLocalizedString("Renews on", comment: "Indicating when the subscription will renew"))
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(format_date(date: expiry))
                        .foregroundColor(.white)
                        .opacity(0.65)
                }
            }
        }
        
        func ProductsView(_ products: [Product]) -> some View {
            VStack(spacing: 10) {
                Text(NSLocalizedString("Save 20% off on an annual subscription", comment: "Savings for purchasing an annual subscription"))
                    .font(.callout.bold())
                    .foregroundColor(.white)
                ForEach(products) { product in
                    Button(action: {
                        Task { @MainActor in
                            do {
                                try await subscribe(product)
                            } catch {
                                print(error.localizedDescription)
                            }
                        }
                    }, label: {
                        price_description(product: product)
                    })
                    .buttonStyle(GradientButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        
        func price_description(product: Product) -> some View {
            let purple_type = DamusPurple.StoreKitManager.DamusPurpleType(rawValue: product.id)
            return (
                HStack(spacing: 10) {
                    Text(purple_type?.label() ?? product.displayName)
                    Spacer()
                    if let non_discounted_price = purple_type?.non_discounted_price(product: product) {
                        Text(verbatim: non_discounted_price)
                            .strikethrough()
                            .foregroundColor(DamusColors.white.opacity(0.5))
                    }
                    Text(verbatim: product.displayPrice)
                        .fontWeight(.bold)
                }
            )
        }
    }
}

// MARK: - Helper structures

extension DamusPurpleView {
    enum ProductState {
        case loading
        case loaded([Product])
        case failed
        
        var products: [Product]? {
            switch self {
                case .loading:
                    return nil
                case .loaded(let ps):
                    return ps
                case .failed:
                    return nil
            }
        }
    }
}

#Preview {
    DamusPurpleView.IAPProductStateView(products: .loaded([]), purchased: nil, subscribe: {_ in })
}
