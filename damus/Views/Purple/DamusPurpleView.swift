//
//  DamusPurpleView.swift
//  damus
//
//  Created by William Casarin on 2023-03-21.
//

import SwiftUI
import StoreKit

fileprivate let damus_products = ["purpleyearly","purple"]

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

struct DamusPurpleView: View {
    let damus_state: DamusState
    let keypair: Keypair
    
    @State var products: ProductState
    @State var purchased: PurchasedProduct? = nil
    @State var selection: DamusPurpleType = .yearly
    @State var show_welcome_sheet: Bool = false
    @State var show_manage_subscriptions = false
    @State var show_settings_change_confirmation_dialog = false
    @State private var shouldDismissView = false
    
    @Environment(\.dismiss) var dismiss
    
    init(damus_state: DamusState) {
        self._products = State(wrappedValue: .loading)
        self.damus_state = damus_state
        self.keypair = damus_state.keypair
    }
    
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
        }
        .onDisappear {
            notify(.display_tabbar(true))
        }
        .task {
            await load_products()
        }
        .ignoresSafeArea(.all)
        .sheet(isPresented: $show_welcome_sheet, onDismiss: {
            update_user_settings_to_purple()
            shouldDismissView = true
        }, content: {
            DamusPurpleWelcomeView()
        })
        .confirmationDialog(
            NSLocalizedString("It seems that you already have a translation service configured. Would you like to switch to Damus Purple as your translator?", comment: "Confirmation dialog question asking users if they want their translation settings to be automatically switched to the Damus Purple translation service"),
            isPresented: $show_settings_change_confirmation_dialog,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Yes", comment: "User confirm Yes")) {
                set_translation_settings_to_purple()
            }.keyboardShortcut(.defaultAction)
            Button(NSLocalizedString("No", comment: "User confirm No"), role: .cancel) {}
        }
        .onChange(of: shouldDismissView) { shouldDismissView in
            if shouldDismissView && !show_settings_change_confirmation_dialog {
                dismiss()
            }
        }
        .onChange(of: show_settings_change_confirmation_dialog) { show_settings_change_confirmation_dialog in
            if shouldDismissView && !show_settings_change_confirmation_dialog {
                dismiss()
            }
        }
        .manageSubscriptionsSheet(isPresented: $show_manage_subscriptions)
    }
    
    func update_user_settings_to_purple() {
        if damus_state.settings.translation_service == .none {
            set_translation_settings_to_purple()
        }
        else {
            show_settings_change_confirmation_dialog = true
        }
    }
    
    func set_translation_settings_to_purple() {
        damus_state.settings.translation_service = .purple
        damus_state.settings.auto_translate = true
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
    
    func IconOnBox(_ name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20.0)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20.0))
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(LinearGradient(
                            colors: [DamusColors.pink, .white.opacity(0), .white.opacity(0.5), .white.opacity(0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing), lineWidth: 1)
                )
            
            Image(name)
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.white)
        }
    }
    
    func Icon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .frame(width: 50, height: 50)
            .foregroundColor(.white)
    }
    
    func Title(_ txt: String) -> some View {
        Text(txt)
            .font(.title3)
            .bold()
            .foregroundColor(.white)
            .padding(.bottom, 3)
    }
    
    func Subtitle(_ txt: String) -> some View {
        Text(txt)
            .foregroundColor(.white.opacity(0.65))
    }
    
    var ProductLoadError: some View {
        Text(NSLocalizedString("Subscription Error", comment: "Ah dang there was an error loading subscription information from the AppStore. Please try again later :("))
            .foregroundColor(.white)
    }
    
    var SaveText: Text {
        Text(NSLocalizedString("Save 14%", comment: "Percentage of purchase price the user will save"))
            .font(.callout)
            .italic()
            .foregroundColor(DamusColors.green)
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
                self.damus_state.purple.starred_profiles_cache[keypair.pubkey] = nil
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
            Text(format_date(UInt32(purchased.tx.purchaseDate.timeIntervalSince1970)))
                .foregroundColor(.white)
                .opacity(0.65)
            if let expiry = purchased.tx.expirationDate {
                Text(NSLocalizedString("Renews on", comment: "Indicating when the subscription will renew"))
                    .font(.title2)
                    .foregroundColor(.white)
                Text(format_date(UInt32(expiry.timeIntervalSince1970)))
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
    
    var ProductStateView: some View {
        Group {
            switch self.products {
                case .failed:
                    ProductLoadError
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
    
    var MainContent: some View {
        VStack {
            DamusPurpleLogoView()
            
            VStack(alignment: .leading, spacing: 30) {
                Subtitle(NSLocalizedString("Help us stay independent in our mission for Freedom tech with our Purple subscription, and look cool doing it!", comment: "Damus purple subscription pitch"))
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 20) {
                    IconOnBox("heart.fill")
                    
                    VStack(alignment: .leading) {
                        Title(NSLocalizedString("Help Build The Future", comment: "Title for funding future damus development"))
                        
                        Subtitle(NSLocalizedString("Support Damus development to help build the future of decentralized communication on the web.", comment: "Reason for supporting damus development"))
                    }
                }
                
                HStack(spacing: 20) {
                    IconOnBox("ai-3-stars.fill")
                    
                    VStack(alignment: .leading) {
                        Title(NSLocalizedString("Exclusive features", comment: "Features only available on subscription service"))
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
                        
                        Subtitle(NSLocalizedString("Be the first to access upcoming premium features: Automatic translations, longer note storage, and more", comment: "Description of new features to be expected"))
                            .padding(.top, 3)
                    }
                }
                
                HStack(spacing: 20) {
                    IconOnBox("badge")
                    
                    VStack(alignment: .leading) {
                        Title(NSLocalizedString("Supporter Badge", comment: "Title for supporter badge"))
                        
                        Subtitle(NSLocalizedString("Get a special badge on your profile to show everyone your contribution to Freedom tech", comment: "Supporter badge description"))
                    }
                }
                
                HStack {
                    Spacer()
                    Link(
                        NSLocalizedString("Learn more", comment: "Label for a link to the Damus Purple landing page"),
                        destination: damus_state.settings.purple_api_staging ? Constants.PURPLE_LANDING_PAGE_TEST_URL : Constants.PURPLE_LANDING_PAGE_PRODUCTION_URL
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

            
            Spacer()
        }
    }
}

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
