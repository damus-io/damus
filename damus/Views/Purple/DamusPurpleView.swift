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

struct PurchasedProduct {
    let tx: StoreKit.Transaction
    let product: Product
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
            DamusPurpleLogoView()
            
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
            VStack(alignment: .leading, spacing: 30) {
                PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("Help us stay independent in our mission for Freedom tech with our Purple subscription, and look cool doing it!", comment: "Damus purple subscription pitch"))
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 20) {
                    PurpleViewPrimitives.IconOnBoxView(name: "heart.fill")
                    
                    VStack(alignment: .leading) {
                        PurpleViewPrimitives.TitleView(text: NSLocalizedString("Help Build The Future", comment: "Title for funding future damus development"))
                        
                        PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("Support Damus development to help build the future of decentralized communication on the web.", comment: "Reason for supporting damus development"))
                    }
                }
                
                HStack(spacing: 20) {
                    PurpleViewPrimitives.IconOnBoxView(name: "ai-3-stars.fill")
                    
                    VStack(alignment: .leading) {
                        PurpleViewPrimitives.TitleView(text: NSLocalizedString("Exclusive features", comment: "Features only available on subscription service"))
                            .padding(.bottom, -3)
                        
                        HStack(spacing: 3) {
                            Image("calendar")
                                .resizable()
                                .frame(width: 15, height: 15)
                            
                            Text(NSLocalizedString("Coming soon", comment: "Feature is still in development and will be available soon"))
                                .font(.caption)
                                .bold()
                        }
                        .foregroundColor(DamusColors.pink)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(DamusColors.lightBackgroundPink)
                        .cornerRadius(30.0)
                        
                        PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("Be the first to access upcoming premium features: Automatic translations, longer note storage, and more", comment: "Description of new features to be expected"))
                            .padding(.top, 3)
                    }
                }
                
                HStack(spacing: 20) {
                    PurpleViewPrimitives.IconOnBoxView(name: "badge")
                    
                    VStack(alignment: .leading) {
                        PurpleViewPrimitives.TitleView(text: NSLocalizedString("Supporter Badge", comment: "Title for supporter badge"))
                        
                        PurpleViewPrimitives.SubtitleView(text: NSLocalizedString("Get a special badge on your profile to show everyone your contribution to Freedom tech", comment: "Supporter badge description"))
                    }
                }
                
                HStack {
                    Spacer()
                    Link(
                        damus_state.purple.enable_purple_iap_support ?
                            NSLocalizedString("Learn more about the features", comment: "Label for a link to the Damus website, to allow the user to learn more about the features of Purple")
                            :
                            NSLocalizedString("Coming soon! Visit our website to learn more", comment: "Label announcing Purple, and inviting the user to learn more on the website"),
                        destination: damus_state.purple.environment.damus_website_url()
                    )
                    .foregroundColor(DamusColors.pink)
                    .padding()
                    Spacer()
                }
                
            }
            .padding([.trailing, .leading], 30)
            .padding(.bottom, 20)
            
            VStack(alignment: .center) {
                ProductStateView
            }
            .padding([.top], 20)
        }
    }
    
    var ProductStateView: some View {
        Group {
            if damus_state.purple.enable_purple_iap_support {
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
            Button(action: {
                show_manage_subscriptions = true
            }, label: {
                Text(NSLocalizedString("Manage", comment: "Manage the damus subscription"))
            })
            .buttonStyle(GradientButtonStyle())
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
        if product.id == "purpleyearly" {
            return (
                AnyView(
                    HStack(spacing: 10) {
                        Text(NSLocalizedString("Annually", comment: "Annual renewal of purple subscription"))
                        Spacer()
                        Text(verbatim: non_discounted_price(product)).strikethrough().foregroundColor(DamusColors.white.opacity(0.5))
                        Text(verbatim: product.displayPrice).fontWeight(.bold)
                    }
                )
            )
        } else {
            return (
                AnyView(
                    HStack(spacing: 10) {
                        Text(NSLocalizedString("Monthly", comment: "Monthly renewal of purple subscription"))
                        Spacer()
                        Text(verbatim: product.displayPrice).fontWeight(.bold)
                    }
                )
            )
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

// MARK: - More helper views

struct DamusPurpleLogoView: View {
    var body: some View {
        HStack(spacing: 20) {
            Image("damus-dark-logo")
                .resizable()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 15.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(LinearGradient(
                            colors: [DamusColors.lighterPink.opacity(0.8), .white.opacity(0), DamusColors.deepPurple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(radius: 5)
            
            VStack(alignment: .leading) {
                Text(NSLocalizedString("Purple", comment: "Subscription service name"))
                    .font(.system(size: 60.0).weight(.bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DamusColors.lighterPink, DamusColors.deepPurple],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
                    .foregroundColor(.white)
                    .tracking(-2)
            }
        }
        .padding(.bottom, 30)
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
