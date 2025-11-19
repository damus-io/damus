//
//  NWCSettings.swift
//  damus
//
//  Created by eric on 1/24/25.
//

import SwiftUI
import Combine

struct NWCSettings: View {
    
    let damus_state: DamusState
    let nwc: WalletConnectURL
    @ObservedObject var model: WalletModel
    @ObservedObject var settings: UserSettingsStore
    
    @Environment(\.dismiss) var dismiss
    
    // Budget sync state tracking
    @State private var isCoinosWallet: Bool = false
    @State private var maxWeeklyBudget: UInt64? = nil
    @State private var budgetSyncState: BudgetSyncState = .undefined
    
    // Min/max budget values for slider
    private let minBudget: UInt64 = 100
    private let maxBudget: UInt64 = 10_000_000
    
    // Slider min/max values for logarithmic scale (0-1 range)
    private let sliderMin: Double = 0.0
    private let sliderMax: Double = 1.0
    
    func donation_binding() -> Binding<Double> {
        return Binding(get: {
            return Double(model.settings.donation_percent)
        }, set: { v in
            model.settings.donation_percent = Int(v)
        })
    }
    
    static let min_donation: Double = 0.0
    static let max_donation: Double = 100.0
    
    var percent: Double {
        Double(model.settings.donation_percent) / 100.0
    }
    
    var tip_msats: String {
        let msats = Int64(percent * Double(model.settings.default_zap_amount * 1000))
        let s = format_msats_abbrev(msats)
        // TODO: fix formatting and remove this hack
        let parts = s.split(separator: ".")
        if parts.count == 1 {
            return s
        }
        if let end = parts[safe: 1] {
            if end.allSatisfy({ c in c.isNumber }) {
                return String(parts[0])
            } else {
                return s
            }
        }
        return s
    }
    
    var SupportDamus: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(DamusGradient.gradient.opacity(0.5))
            
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image("logo-nobg")
                        .resizable()
                        .frame(width: 50, height: 50)
                    Text("Support Damus", comment: "Text calling for the user to support Damus through zaps")
                        .font(.title.bold())
                        .foregroundColor(.white)
                }
                
                Text("Help build the future of decentralized communication on the web.", comment: "Text indicating the goal of developing Damus which the user can help with.")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.white)
                
                Text("An additional percentage of each zap will be sent to support Damus development", comment: "Text indicating that they can contribute zaps to support Damus development.")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.white)
                
                let binding = donation_binding()
                
                HStack {
                    Slider(value: binding,
                           in: NWCSettings.min_donation...NWCSettings.max_donation,
                           label: {  })
                    Text("\(Int(binding.wrappedValue))%", comment: "Percentage of additional zap that should be sent to support Damus development.")
                        .font(.title.bold())
                        .foregroundColor(.white)
                        .frame(width: 80)
                }
                
                HStack{
                    Spacer()
                    
                    VStack {
                        HStack {
                            Text("\(Image("zap.fill")) \(format_msats_abbrev(Int64(model.settings.default_zap_amount) * 1000))")
                                .font(.title)
                                .foregroundColor(percent == 0 ? .gray : .yellow)
                                .frame(width: 120)
                        }
                        
                        Text("Zap", comment: "Text underneath the number of sats indicating that it's the amount used for zaps.")
                            .foregroundColor(.white)
                    }
                    Spacer()
                    
                    Text(verbatim: "+")
                        .font(.title)
                        .foregroundColor(.white)
                    Spacer()
                    
                    VStack {
                        HStack {
                            Text("\(Image("zap.fill")) \(tip_msats)")
                                .font(.title)
                                .foregroundColor(percent == 0 ? .gray : Color.yellow)
                                .frame(width: 120)
                        }
                        
                        Text(verbatim: percent == 0 ? "🩶" : "💜")
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                
                EventProfile(damus_state: damus_state, pubkey: damus_state.pubkey, size: .small)
            }
            .padding(25)
        }
        .frame(height: 370)
    }
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 20) {
            
            SupportDamus
                .padding(.bottom)
            
            AccountDetailsView(nwc: nwc, damus_state: damus_state)
            
            Toggle(NSLocalizedString("Disable high balance warning", comment: "Setting to disable high balance warnings on the user's wallet"), isOn: $settings.dismiss_wallet_high_balance_warning)
                .toggleStyle(.switch)

            Toggle(NSLocalizedString("Hide balance", comment: "Setting to hide wallet balance."), isOn: $settings.hide_wallet_balance)
                .toggleStyle(.switch)
                
            if isCoinosWallet, let maxWeeklyBudget {
                VStack(alignment: .leading) {
                    Text("Max weekly budget", comment: "Label for setting the maximum weekly budget for Coinos wallet")
                        .font(.headline)
                        .padding(.bottom, 2)
                    Text("The maximum amount of funds that are allowed to be sent out from this wallet each week.", comment: "Description explaining the purpose of the 'Max weekly budget' setting for Coinos one-click setup wallets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Slider(
                                // Use a logarithmic scale for this slider to give more control to different kinds of users:
                                //
                                // - Users with higher budget tolerance can select very high amounts (e.g. Easy to go up to 5M or 10M sats)
                                // - Conservative users can still have fine-grained control over lower amounts (e.g. Easy to switch between 500 and 1.5K sats)
                                value: Binding(
                                    get: {
                                        // Convert from budget value to slider position (0-1)
                                        budgetToSliderPosition(budget: maxWeeklyBudget)
                                    },
                                    set: { 
                                        // Convert from slider position to budget value
                                        let newValue = sliderPositionToBudget(position: $0)
                                        if self.maxWeeklyBudget != newValue {
                                            self.maxWeeklyBudget = newValue
                                        }
                                    }
                                ),
                                in: sliderMin...sliderMax,
                                onEditingChanged: { editing in
                                    if !editing {
                                        updateMaxWeeklyBudget()
                                    }
                                }
                            )
                            
                            Text(verbatim: format_msats(Int64(maxWeeklyBudget) * 1000))
                                .foregroundColor(.gray)
                                .frame(width: 150, alignment: .trailing)
                        }
                        
                        // Budget sync status
                        HStack {
                            switch budgetSyncState {
                            case .undefined:
                                EmptyView()
                            case .success:
                                HStack {
                                    Image("check-circle.fill")
                                        .foregroundStyle(.damusGreen)
                                    Text("Successfully updated", comment: "Label indicating success in updating budget")
                                }
                            case .syncing:
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Updating", comment: "Label indicating budget update is in progress")
                                }
                            case .failure(let error):
                                Text(error)
                                    .foregroundStyle(.damusDangerPrimary)
                            }
                        }
                        .padding(.top, 5)
                    }
                }
                .padding(.vertical, 8)
            }

            Button(action: {
                self.model.disconnect()
                dismiss()
            }) {
                HStack {
                    Text("Disconnect Wallet", comment: "Text for button to disconnect from Nostr Wallet Connect lightning wallet.")
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
        }
        .padding()
        .onAppear() {
            model.initial_percent = model.settings.donation_percent
            checkIfCoinosWallet()
            if isCoinosWallet {
                fetchCurrentBudget()
            }
        }
        .onChange(of: model.settings.donation_percent) { p in
            let profile_txn = damus_state.profiles.lookup(id: damus_state.pubkey)
            guard let profile = profile_txn?.unsafeUnownedValue else {
                return
            }
            
            let prof = Profile(name: profile.name, display_name: profile.display_name, about: profile.about, picture: profile.picture, banner: profile.banner, website: profile.website, lud06: profile.lud06, lud16: profile.lud16, nip05: profile.nip05, damus_donation: p, reactions: profile.reactions)

            notify(.profile_updated(.manual(pubkey: self.damus_state.pubkey, profile: prof)))
        }
        .onDisappear {
            let profile_txn = damus_state.profiles.lookup(id: damus_state.pubkey)
            
            guard let keypair = damus_state.keypair.to_full(),
                  let profile = profile_txn?.unsafeUnownedValue,
                  model.initial_percent != profile.damus_donation
            else {
                return
            }
            
            let prof = Profile(name: profile.name, display_name: profile.display_name, about: profile.about, picture: profile.picture, banner: profile.banner, website: profile.website, lud06: profile.lud06, lud16: profile.lud16, nip05: profile.nip05, damus_donation: model.settings.donation_percent, reactions: profile.reactions)

            guard let meta = make_metadata_event(keypair: keypair, metadata: prof) else {
                return
            }
            Task { await damus_state.nostrNetwork.postbox.send(meta) }
        }
    }
    
    // Check if the current wallet is a Coinos one-click wallet
    private func checkIfCoinosWallet() {
        // Check condition 1: Relay is coinos.io
        let isRelayCoinos = nwc.relay.absoluteString == "wss://relay.coinos.io"
        
        // Check condition 2: LUD16 matches expected format
        guard let keypair = damus_state.keypair.to_full() else {
            isCoinosWallet = false
            return
        }
        
        let client = CoinosDeterministicAccountClient(userKeypair: keypair)
        let expectedLud16 = client.expectedLud16
        
        isCoinosWallet = isRelayCoinos && nwc.lud16 == expectedLud16
    }
    
    /// Fetches the current max weekly budget from Coinos
    private func fetchCurrentBudget() {
        guard let keypair = damus_state.keypair.to_full() else { return }
        
        let client = CoinosDeterministicAccountClient(userKeypair: keypair)
        
        Task {
            do {
                if let config = try await client.getNWCAppConnectionConfig(),
                   let maxAmount = config.max_amount {
                    DispatchQueue.main.async {
                        self.maxWeeklyBudget = maxAmount
                    }
                }
            } catch {
                self.budgetSyncState = .failure(error: error.localizedDescription)
            }
        }
    }
    
    /// Updates the max weekly budget on Coinos
    private func updateMaxWeeklyBudget() {
        guard let maxWeeklyBudget else { return }
        guard let keypair = damus_state.keypair.to_full() else { return }
        
        budgetSyncState = .syncing
        
        let client = CoinosDeterministicAccountClient(userKeypair: keypair)
        
        Task {
            do {
                // First ensure we're logged in
                try await client.loginIfNeeded()
                
                // Update the connection with the new budget
                _ = try await client.updateNWCConnection(maxAmount: maxWeeklyBudget)
            
                DispatchQueue.main.async {
                    self.budgetSyncState = .success
                    
                    // Reset success state after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if case .success = self.budgetSyncState {
                            self.budgetSyncState = .undefined
                        }
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.budgetSyncState = .failure(error: error.localizedDescription)
                }
            }
        }
    }
    
    struct AccountDetailsView: View {
        let nwc: WalletConnect.ConnectURL
        let damus_state: DamusState?
        
        var body: some View {
            VStack(alignment: .leading) {
                
                Text("Account details", comment: "Prompt to ask user if they want to attach their Nostr Wallet Connect lightning wallet.")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                
                Text("Routing", comment: "Label indicating the routing address for Nostr Wallet Connect payments. In other words, the relay used by the NWC wallet provider")
                    .font(.headline)
                
                if let damus_state {
                    RelayView(state: damus_state, relay: nwc.relay, showActionButtons: .constant(false), recommended: false, disableNavLink: true)
                        .padding(.bottom)
                }
                else {
                    Text(nwc.relay.absoluteString)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                        .padding(.bottom)
                }
                
                if let lud16 = nwc.lud16 {
                    Text("Account", comment: "Label for the user account information with the Nostr Wallet Connect wallet provider.")
                        .font(.headline)
                    
                    Text(lud16)
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
            .padding(.horizontal, 20)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(DamusColors.neutral3, lineWidth: 2)
            )
        }
    }
    
    
    // MARK: - Logarithmic scale conversions
    
    /// Converts from budget value to a slider position (0-1 range)
    func budgetToSliderPosition(budget: UInt64) -> Double {
        // Ensure budget is within bounds
        let clampedBudget = max(minBudget, min(maxBudget, budget))
        
        // Calculate the log scale position
        let minLog = log10(Double(minBudget))
        let maxLog = log10(Double(maxBudget))
        let budgetLog = log10(Double(clampedBudget))
        
        // Convert to 0-1 range
        return (budgetLog - minLog) / (maxLog - minLog)
    }
    
    // Convert from slider position (0-1) to budget value
    func sliderPositionToBudget(position: Double) -> UInt64 {
        // Ensure position is within bounds
        let clampedPosition = max(sliderMin, min(sliderMax, position))
        
        // Calculate the log scale value
        let minLog = log10(Double(minBudget))
        let maxLog = log10(Double(maxBudget))
        let valueLog = minLog + clampedPosition * (maxLog - minLog)
        
        // Convert to budget value and round to nearest 100 to make the number look "cleaner"
        let exactValue = pow(10, valueLog)
        let roundedValue = round(exactValue / 100) * 100
        
        return UInt64(roundedValue)
    }
}

struct NWCSettings_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        let state = test_damus_state
        let connectURL = WalletConnectURL(
            pubkey: test_pubkey,
            relay: .init("wss://relay.damus.io")!,
            keypair: state.keypair.to_full()!,
            lud16: "jb55@sendsats.com"
        )
        return NWCSettings(damus_state: state, nwc: connectURL, model: WalletModel(state: .existing(connectURL), settings: state.settings), settings: state.settings)
    }
}

extension NWCSettings {
    enum BudgetSyncState: Equatable {
        /// State is unknown
        case undefined
        /// Budget is successfully updated
        case success
        /// Budget is being updated
        case syncing
        /// There was a failure during update
        case failure(error: String)
    }
}
