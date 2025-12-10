//
//  WalletView.swift
//  damus
//
//  Created by William Casarin on 2023-05-05.
//

import SwiftUI

let WALLET_WARNING_THRESHOLD: UInt64 = 100000

struct WalletView: View {
    let damus_state: DamusState
    @State var show_settings: Bool = false
    @State var show_send_sheet: Bool = false
    @ObservedObject var model: WalletModel
    @ObservedObject var settings: UserSettingsStore
    @State private var showBalance: Bool = false
    @State private var walletRefreshTask: Task<Void, Never>? = nil

    init(damus_state: DamusState, model: WalletModel? = nil) {
        self.damus_state = damus_state
        self._model = ObservedObject(wrappedValue: model ?? damus_state.wallet)
        self._settings = ObservedObject(wrappedValue: damus_state.settings)
    }
    
    func MainWalletView(nwc: WalletConnectURL) -> some View {
        ScrollView {
            VStack(spacing: 35) {
                if let balance = model.balance, balance > WALLET_WARNING_THRESHOLD && !settings.dismiss_wallet_high_balance_warning {
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                            Text("Safety Reminder", comment: "Heading for a safety reminder that appears when the user has too many funds, recommending them to learn about safeguarding their funds.")
                                .font(.title3)
                                .bold()
                        }
                        .foregroundStyle(.damusWarningTertiary)
                        
                        Text("If your wallet balance is getting high, it's important to understand how to keep your funds secure. Please consider learning the best practices to ensure your assets remain safe. [Click here](https://damus.io/docs/wallet/high-balance-safety-reminder/) to learn more.", comment: "Text reminding the user has a high balance, recommending them to learn about self-custody")
                            .foregroundStyle(.damusWarningSecondary)
                            .accentColor(.damusWarningTertiary)
                            .opacity(0.8)
                        
                        Button(action: {
                            settings.dismiss_wallet_high_balance_warning = true
                        }, label: {
                            Text("Dismiss", comment: "Button label to dismiss the safety reminder that the user's wallet has a high balance")
                        })
                        .bold()
                        .foregroundStyle(.damusWarningTertiary)
                    }
                    .privacySensitive()
                    .padding()
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.damusWarningBorder, lineWidth: 1)
                    )
                }
                
                VStack(spacing: 5) {
                    
                    BalanceView(balance: model.balance, hide_balance: $settings.hide_wallet_balance)
                    
                    Button(action: {
                        show_send_sheet = true
                    }) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send", comment: "Button label to send bitcoin payment from wallet")
                                .font(.headline)
                        }
                        .padding(.horizontal, 10)
                    }
                    .buttonStyle(GradientButtonStyle())
                    .padding(.bottom, 20)

                    TransactionsView(damus_state: damus_state, transactions: model.transactions, hide_balance: $settings.hide_wallet_balance)
                }
            }
            .navigationTitle(NSLocalizedString("Wallet", comment: "Navigation title for Wallet view"))
            .navigationBarTitleDisplayMode(.inline)
            .padding()
            .padding(.bottom, 50)
        }
    }

    var body: some View {
        switch model.connect_state {
        case .new:
            ConnectWalletView(model: model, nav: damus_state.nav, userKeypair: self.damus_state.keypair)
        case .none:
            ConnectWalletView(model: model, nav: damus_state.nav, userKeypair: self.damus_state.keypair)
        case .existing(let nwc):
            MainWalletView(nwc: nwc)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(
                            action: { show_settings = true },
                            label: {
                                Image("settings")
                                    .foregroundColor(.gray)
                            }
                        )
                    }
                }
                .onAppear() {
                    self.refreshWalletInformation()
                }
                .refreshable {
                    self.refreshWalletInformation()
                }
                .sheet(isPresented: $show_settings, onDismiss: { self.show_settings = false }) {
                    ScrollView {
                        NWCSettings(damus_state: damus_state, nwc: nwc, model: model, settings: settings)
                            .padding(.top, 30)
                    }
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.large])
                }
                .sheet(isPresented: $show_send_sheet) {
                    SendPaymentView(damus_state: damus_state, model: model, nwc: nwc)
                        .presentationDragIndicator(.visible)
                        .presentationDetents([.large])
                }
        }
    }
    
    @MainActor
    func refreshWalletInformation() {
        walletRefreshTask?.cancel()
        walletRefreshTask = Task {
            do {
                try await self.model.refreshWalletInformation()
            }
            catch {
                guard let error = error as? ErrorView.UserPresentableErrorProtocol else {
                    Log.error("Error while refreshing wallet: %s", for: .nwc, error.localizedDescription)
                    return
                }
                present_sheet(.error(error.userPresentableError))
            }
        }
    }
}

struct WalletView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let state = test_damus_state
        let connectURL = WalletConnectURL(
            pubkey: test_pubkey,
            relay: .init("wss://relay.damus.io")!,
            keypair: state.keypair.to_full()!,
            lud16: "jb55@sendsats.com"
        )
        return WalletView(damus_state: state, model: WalletModel(state: .existing(connectURL), settings: state.settings))
    }
}
