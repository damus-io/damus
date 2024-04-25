//
//  DamusPurpleView.swift
//  damus
//
//  Created by William Casarin on 2023-03-21.
//

import SwiftUI
import StoreKit

// MARK: - Helper structures

enum AccountInfoState {
    case loading
    case loaded(account: DamusPurple.Account)
    case no_account
    case error(message: String)
}

// MARK: - Main view

struct DamusPurpleView: View, DamusPurpleStoreKitManagerDelegate {
    let damus_state: DamusState
    let keypair: Keypair
    
    @State var my_account_info_state: AccountInfoState = .loading
    @State var products: ProductState
    @State var purchased: PurchasedProduct? = nil
    @State var selection: DamusPurple.StoreKitManager.DamusPurpleType = .yearly
    @State var show_welcome_sheet: Bool = false
    @State var account_uuid: UUID? = nil
    @State var iap_error: String? = nil     // TODO: Display this error to the user in some way.
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
            PurpleBackdrop {
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
                // Assign this view as the delegate for the storekit manager to receive purchase updates
                damus_state.purple.storekit_manager.delegate = self
                // Fetch the account UUID to use for IAP purchases and to check if an IAP purchase is associated with the account
                self.account_uuid = try await damus_state.purple.get_maybe_cached_uuid_for_account()
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
                    Group {
                        DamusPurpleAccountView(damus_state: damus_state, account: account)
                        
                        ProductStateView(account: account)
                    }
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
                ProductStateView(account: nil)
            }
            .padding([.top], 20)
        }
    }
    
    func ProductStateView(account: DamusPurple.Account?) -> some View {
        Group {
            if damus_state.purple.enable_purple_iap_support {
                if account?.active == true && purchased == nil {
                    // Account active + no IAP purchases = Bought through Lightning.
                    // Instruct the user to manage billing on the website
                    ManageOnWebsiteNote
                }
                else {
                    // If account is no longer active or was purchased via IAP, then show IAP purchase/manage options
                    if let account_uuid {
                        DamusPurpleView.IAPProductStateView(products: products, purchased: purchased, account_uuid: account_uuid, subscribe: subscribe)
                        if let iap_error {
                            Text("There has been an unexpected error with the in-app purchase. Please try again later or contact support@damus.io. Error: \(iap_error)", comment: "In-app purchase error message for the user")
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    else {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                
            }
            else {
                ManageOnWebsiteNote
            }
        }
    }
    
    var ManageOnWebsiteNote: some View {
        Text("Visit the Damus website on a web browser to manage billing", comment: "Instruction on how to manage billing externally")
            .font(.caption)
            .foregroundColor(.white.opacity(0.6))
            .multilineTextAlignment(.center)
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
    
    func load_products() async {
        do {
            let products = try await self.damus_state.purple.storekit_manager.get_products()
            self.products = .loaded(products)

            print("loaded products", products)
        } catch {
            self.products = .failed
            print("Failed to fetch products: \(error.localizedDescription)")
        }
    }
    
    // For DamusPurple.StoreKitManager.Delegate conformance. This gets called by the StoreKitManager when a new product was purchased
    func product_was_purchased(product: DamusPurple.StoreKitManager.PurchasedProduct) {
        self.purchased = product
    }
    
    func subscribe(_ product: Product) async throws {
        do {
            try await self.damus_state.purple.make_iap_purchase(product: product)
            show_welcome_sheet = true
        }
        catch(let error) {
            self.iap_error = error.localizedDescription
        }
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
