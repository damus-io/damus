//
//  WalletView.swift
//  damus
//
//  Created by William Casarin on 2023-05-05.
//

import SwiftUI

struct WalletView: View {
    let damus_state: DamusState
    @ObservedObject var model: WalletModel
    @ObservedObject var settings: UserSettingsStore
    
    init(damus_state: DamusState, model: WalletModel? = nil) {
        self.damus_state = damus_state
        self._model = ObservedObject(wrappedValue: model ?? damus_state.wallet)
        self._settings = ObservedObject(wrappedValue: damus_state.settings)
    }
    
    func MainWalletView(nwc: WalletConnectURL) -> some View {
        VStack {
            SupportDamus
            
            Spacer()
            
            Text(verbatim: nwc.relay.id)
            
            if let lud16 = nwc.lud16 {
                Text(verbatim: lud16)
            }
            
            BigButton(NSLocalizedString("Disconnect Wallet", comment: "Text for button to disconnect from Nostr Wallet Connect lightning wallet.")) {
                self.model.disconnect()
            }
            
        }
        .navigationTitle(NSLocalizedString("Wallet", comment: "Navigation title for Wallet view"))
        .navigationBarTitleDisplayMode(.large)
        .padding()
    }
    
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
                           in: WalletView.min_donation...WalletView.max_donation,
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
                
                EventProfile(damus_state: damus_state, pubkey: damus_state.pubkey, profile: damus_state.profiles.lookup(id: damus_state.pubkey), size: .small)
            }
            .padding(25)
        }
        .frame(height: 370)
    }
    
    var body: some View {
        switch model.connect_state {
        case .new:
            ConnectWalletView(model: model)
        case .none:
            ConnectWalletView(model: model)
        case .existing(let nwc):
            MainWalletView(nwc: nwc)
                .onAppear() {
                    model.inital_percent = settings.donation_percent
                }
                .onChange(of: settings.donation_percent) { p in
                    guard let profile = damus_state.profiles.lookup(id: damus_state.pubkey) else {
                        return
                    }
                    
                    profile.damus_donation = p
                    
                    notify(.profile_updated, ProfileUpdate(pubkey: damus_state.pubkey, profile: profile))
                }
                .onDisappear {
                    guard let keypair = damus_state.keypair.to_full(),
                          let profile = damus_state.profiles.lookup(id: damus_state.pubkey),
                          model.inital_percent != profile.damus_donation
                    else {
                        return
                    }
                    
                    profile.damus_donation = settings.donation_percent
                    let meta = make_metadata_event(keypair: keypair, metadata: profile)
                    let tsprofile = TimestampedProfile(profile: profile, timestamp: meta.created_at, event: meta)
                    damus_state.profiles.add(id: damus_state.pubkey, profile: tsprofile)
                    damus_state.postbox.send(meta)
                }
        }
    }
}

let test_wallet_connect_url = WalletConnectURL(pubkey: "pk", relay: .init("wss://relay.damus.io")!, keypair: test_damus_state().keypair.to_full()!, lud16: "jb55@sendsats.com")

struct WalletView_Previews: PreviewProvider {
    static let tds = test_damus_state()
    static var previews: some View {
        WalletView(damus_state: tds, model: WalletModel(state: .existing(test_wallet_connect_url), settings: tds.settings))
    }
}
