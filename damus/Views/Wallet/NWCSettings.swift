//
//  NWCSettings.swift
//  damus
//
//  Created by eric on 1/24/25.
//

import SwiftUI

struct NWCSettings: View {
    
    let damus_state: DamusState
    let nwc: WalletConnectURL
    @ObservedObject var model: WalletModel
    @ObservedObject var settings: UserSettingsStore
    
    
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
            
            VStack(alignment: .leading) {
                
                Text("Account details", comment: "Prompt to ask user if they want to attach their Nostr Wallet Connect lightning wallet.")
                    .font(.system(size: 24))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.bottom)
                
                Text("Routing")
                    .font(.system(size: 18))
                
                Text(nwc.relay.absoluteString)
                    .font(.system(size: 18))
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                    .padding(.bottom)
                
                if let lud16 = nwc.lud16 {
                    Text("Account")
                        .font(.system(size: 18))
                    
                    Text(lud16)
                        .font(.system(size: 18))
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
            .padding(.horizontal, 20)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(DamusColors.neutral3, lineWidth: 2)
            )
            
            Button(action: {
                self.model.disconnect()
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
            damus_state.postbox.send(meta)
        }
    }
}

struct NWCSettings_Previews: PreviewProvider {
    static let tds = test_damus_state
    static var previews: some View {
        NWCSettings(damus_state: tds, nwc: test_wallet_connect_url, model: WalletModel(state: .existing(test_wallet_connect_url), settings: tds.settings), settings: tds.settings)
    }
}
