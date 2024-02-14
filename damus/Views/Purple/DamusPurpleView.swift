//
//  DamusPurpleView.swift
//  damus
//
//  Created by William Casarin on 2023-03-21.
//

import SwiftUI
import StoreKit

fileprivate let damus_products = ["purpleyearly","purple"]

// MARK: - Helper structures

enum AccountInfoState {
    case loading
    case loaded(account: DamusPurple.Account)
    case no_account
    case error(message: String)
}

func non_discounted_price(_ product: Product) -> String {
    return (product.price * 1.1984569224).formatted(product.priceFormatStyle)
}

enum DamusPurpleType: String {
    case yearly = "purpleyearly"
    case monthly = "purple"
}

// MARK: - Main view

struct DamusPurpleView: View {
    let damus_state: DamusState
    let keypair: Keypair
    
    @State var my_account_info_state: AccountInfoState = .loading
    @State var products: ProductState
    @State var purchased: PurchasedProduct? = nil
    @State var selection: DamusPurpleType = .yearly
    @State var show_welcome_sheet: Bool = false
    @State var show_manage_subscriptions = false
    @State private var shouldDismissView = false
    
    @Environment(\.dismiss) var dismiss
    
    init(damus_state: DamusState) {
        self._products = State(wrappedValue: .loading)
        self.damus_state = damus_state
        self.keypair = damus_state.keypair
    }
    
    // MARK: - Top level view
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .edgesIgnoringSafeArea(.all)

                Image("purple-blue-gradient-1")
                    .resizable()
                    .edgesIgnoringSafeArea(.all)

                ScrollView {
                    MainContent
                        .padding(.top, 75)
                }
            }
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(leading: BackNav())
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
        .onAppear {
            notify(.display_tabbar(false))
            Task {
                await self.load_account()
            }
        }
        .onDisappear {
            notify(.display_tabbar(true))
        }
        .onReceive(handle_notify(.purple_account_update), perform: { account in
            self.my_account_info_state = .loaded(account: account)
        })
        .task {
            await load_products()
        }
        .ignoresSafeArea(.all)
        .sheet(isPresented: $show_welcome_sheet, onDismiss: {
            shouldDismissView = true
        }, content: {
            DamusPurpleNewUserOnboardingView(damus_state: damus_state)
        })
        .manageSubscriptionsSheet(isPresented: $show_manage_subscriptions)
    }
    
    // MARK: - Complex subviews
    
    var MainContent: some View {
        VStack {
            DamusPurpleView.LogoView()
            
            switch my_account_info_state {
                case .loading:
                    ProgressView()
                        .progressViewStyle(.circular)
                case .loaded(let account):
                    DamusPurpleAccountView(damus_state: damus_state, account: account)
                case .no_account:
                    MarketingContent
                case .error(let message):
                    Text(message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
            }
            
            Spacer()
        }
    }
    
    var MarketingContent: some View {
        VStack {
            DamusPurpleView.MarketingContentView(purple: damus_state.purple)
            
            VStack(alignment: .center) {
                ProductStateView
            }
            .padding([.top], 20)
        }
    }
    
    var ProductStateView: some View {
        Group {
            if damus_state.purple.enable_purple_iap_support {
                DamusPurpleView.IAPProductStateView(products: products, purchased: purchased, subscribe: subscribe)
            }
        }
    }
    
    // MARK: - State management
    
    func load_account() async {
        do {
            if let account = try await damus_state.purple.fetch_account(pubkey: damus_state.keypair.pubkey) {
                self.my_account_info_state = .loaded(account: account)
                return
            }
            self.my_account_info_state = .no_account
            return
        }
        catch {
            self.my_account_info_state = .error(message: NSLocalizedString("There was an error loading your account. Please try again later. If problem persists, please contact us at support@damus.io", comment: "Error label when Purple account information fails to load"))
        }
    }
    
    func handle_transactions(products: [Product]) async {
        for await update in StoreKit.Transaction.updates {
            switch update {
                case .verified(let tx):
                    let prod = products.filter({ prod in tx.productID == prod.id }).first
                    
                    if let prod,
                       let expiration = tx.expirationDate,
                       Date.now < expiration
                    {
                        self.purchased = PurchasedProduct(tx: tx, product: prod)
                        break
                    }
                case .unverified:
                    continue
            }
        }
    }
    
    func load_products() async {
        do {
            let products = try await Product.products(for: damus_products)
            self.products = .loaded(products)
            await handle_transactions(products: products)

            print("loaded products", products)
        } catch {
            self.products = .failed
            print("Failed to fetch products: \(error.localizedDescription)")
        }
    }
    
    func subscribe(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
            case .success(.verified(let tx)):
                print("success \(tx.debugDescription)")
                show_welcome_sheet = true
            case .success(.unverified(let tx, let res)):
                print("success unverified \(tx.debugDescription) \(res.localizedDescription)")
                show_welcome_sheet = true
            case .pending:
                break
            case .userCancelled:
                break
            @unknown default:
                break
        }
        
        switch result {
            case .success:
                // TODO (will): why do this here?
                //self.damus_state.purple.starred_profiles_cache[keypair.pubkey] = nil
                Task {
                    await self.damus_state.purple.send_receipt()
                }
            default:
                break
        }
    }
    
    var product: Product? {
        return self.products.products?.filter({
            prod in prod.id == selection.rawValue
        }).first
    }
}

struct DamusPurpleView_Previews: PreviewProvider {
    static var previews: some View {
        /*
        DamusPurpleView(products: [
            DamusProduct(name: "Yearly", id: "purpleyearly", price: Decimal(69.99)),
            DamusProduct(name: "Monthly", id: "purple", price: Decimal(6.99)),
        ])
         */
        
        DamusPurpleView(damus_state: test_damus_state)
    }
}
