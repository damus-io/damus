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
            
            Text("\(nwc.relay.id)")
            
            if let lud16 = nwc.lud16 {
                Text("\(lud16)")
            }
            
            BigButton("Disconnect Wallet") {
                self.model.disconnect()
            }
            
        }
        .navigationTitle("Wallet")
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
        return s.split(separator: ".").first.map({ x in String(x) }) ?? s
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
                    Text("Support Damus")
                        .font(.title.bold())
                        .foregroundColor(.white)
                }
                
                Text("Help build the future of decentralized communication on the web.")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.white)
                
                Text("An additional percentage of each zap will be sent to support Damus development ")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundColor(.white)
                
                let binding = donation_binding()
                
                HStack {
                    Slider(value: binding,
                           in: WalletView.min_donation...WalletView.max_donation,
                           label: {  })
                    Text("\(Int(binding.wrappedValue))%")
                        .font(.title.bold())
                        .foregroundColor(.white)
                }
                
                HStack{
                    Spacer()
                    
                    VStack {
                        HStack {
                            Text("\(Image("zap.fill")) \(format_msats_abbrev(Int64(model.settings.default_zap_amount) * 1000))")
                                .font(.title)
                                .foregroundColor(percent == 0 ? .gray : .yellow)
                                .frame(width: 100)
                        }
                        
                        Text("Zap")
                            .foregroundColor(.white)
                    }
                    Spacer()
                    
                    Text("+")
                        .font(.title)
                        .foregroundColor(.white)
                    Spacer()
                    
                    VStack {
                        HStack {
                            Text("\(Image("zap.fill")) \(tip_msats)")
                                .font(.title)
                                .foregroundColor(percent == 0 ? .gray : Color.yellow)
                                .frame(width: 100)
                        }
                        Text("Donation")
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                
                EventProfile(damus_state: damus_state, pubkey: damus_state.pubkey, profile: damus_state.profiles.lookup(id: damus_state.pubkey), size: .small)
                
                /*
                Slider(value: donation_binding(),
                       in: WalletView.min...WalletView.max,
                       step: 1,
                       minimumValueLabel: { Text("\(WalletView.min)") },
                       maximumValueLabel: { Text("\(WalletView.max)") },
                       label: { Text("label") }
                )
                 */
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
