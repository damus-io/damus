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
    static let SHOW_IAP_DEBUG_INFO = false
    
    struct IAPProductStateView: View {
        var products: ProductState
        var purchased: PurchasedProduct?
        let account_uuid: UUID
        let subscribe: (Product) async throws -> Void
        
        @State var show_manage_subscriptions = false
        @State var subscription_purchase_loading = false
        
        var body: some View {
            if subscription_purchase_loading {
                HStack(spacing: 10) {
                    Text("Purchasing", comment: "Loading label indicating the purchase action is in progress")
                        .foregroundStyle(.white)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            else {
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
        }
        
        func PurchasedView(_ purchased: PurchasedProduct) -> some View {
            return Group {
                if self.account_uuid == purchased.tx.appAccountToken {
                    // If the In-app purchase is registered to this account, show options to manage the subscription
                    PurchasedManageView(purchased)
                }
                else {
                    // If the In-app purchase is registered to a different account, we cannot manage the subscription
                    // This seems to be a limitation of StoreKit where we can only have one renewable subscription for a product at a time.
                    // Therefore, instruct the user about this limitation, or to contact us if they believe this is a mistake.
                    PurchasedUnmanageableView(purchased)
                }
            }
        }
        
        func PurchasedUnmanageableView(_ purchased: PurchasedProduct) -> some View {
            Text("This device's in-app purchase is registered to a different Nostr account. Unable to manage this Purple account. If you believe this was a mistake, please contact us via support@damus.io.", comment: "Notice label that user cannot manage their In-App purchases")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        
        func PurchasedManageView(_ purchased: PurchasedProduct) -> some View {
            VStack(spacing: 10) {
                if SHOW_IAP_DEBUG_INFO == true {
                    Text("Purchased!", comment: "User purchased a subscription")
                        .font(.title2)
                        .foregroundColor(.white)
                    price_description(product: purchased.product)
                        .foregroundColor(.white)
                        .opacity(0.65)
                        .frame(width: 200)
                    Text("Purchased on", comment: "Indicating when the user purchased the subscription")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text(format_date(date: purchased.tx.purchaseDate))
                        .foregroundColor(.white)
                        .opacity(0.65)
                    if let expiry = purchased.tx.expirationDate {
                        Text("Renews on", comment: "Indicating when the subscription will renew")
                            .font(.title2)
                            .foregroundColor(.white)
                        Text(format_date(date: expiry))
                            .foregroundColor(.white)
                            .opacity(0.65)
                    }
                }
                Button(action: {
                    show_manage_subscriptions = true
                }, label: {
                    Text("Manage", comment: "Manage the damus subscription")
                        .padding(.horizontal, 20)
                })
                .buttonStyle(GradientButtonStyle())
            }
            .manageSubscriptionsSheet(isPresented: $show_manage_subscriptions)
            .padding()
        }
        
        func ProductsView(_ products: [Product]) -> some View {
            VStack(spacing: 10) {
                Text("Save 20% off on an annual subscription", comment: "Savings for purchasing an annual subscription")
                    .font(.callout.bold())
                    .foregroundColor(.white)
                ForEach(products) { product in
                    Button(action: {
                        Task { @MainActor in
                            do {
                                subscription_purchase_loading = true
                                try await subscribe(product)
                                subscription_purchase_loading = false
                            } catch {
                                print(error.localizedDescription)
                            }
                        }
                    }, label: {
                        price_description(product: product)
                    })
                    .buttonStyle(GradientButtonStyle())
                }

                Text("By subscribing to Damus Purple, you are accepting our [privacy policy](https://damus.io/privacy-policy.txt) and Apple's Standard [EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)", comment: "Text explaining the terms and conditions of subscribing to Damus Purple. EULA stands for End User License Agreement.")
                .foregroundColor(.white.opacity(0.6))
                .font(.caption)
                .padding()

            }
            .padding()
        }
        
        func price_description(product: Product) -> some View {
            let purple_type = DamusPurple.StoreKitManager.DamusPurpleType(rawValue: product.id)
            return (
                HStack(spacing: 10) {
                    Text(purple_type?.label() ?? product.displayName)
                    Spacer()
                    if let non_discounted_price = purple_type?.non_discounted_price(product: product) {
                        Text(non_discounted_price)
                            .strikethrough()
                            .foregroundColor(DamusColors.white.opacity(0.5))
                    }
                    Text(product.displayPrice)
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
    PurpleBackdrop {
        DamusPurpleView.IAPProductStateView(products: .loaded([]), purchased: nil, account_uuid: UUID(), subscribe: {_ in })
    }
}
