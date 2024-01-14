//
//  DamusPurpleVerifyNpubView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-01-13.
//

import SwiftUI

struct DamusPurpleVerifyNpubView: View {
    let damus_state: DamusState
    let checkout_id: String
    @State var verified: Bool = false
    
    var body: some View {
        ZStack {
            Rectangle()
                .background(Color.black)
            
            VStack {
                DamusPurpleLogoView()
                
                VStack(alignment: .center, spacing: 30) {
                    Subtitle(NSLocalizedString("To continue your Purple subscription checkout, please verify your npub by clicking on the button below", comment: "Instruction on how to verify npub during Damus Purple checkout"))
                        .multilineTextAlignment(.center)
                    
                    if !verified {
                        Button(action: {
                            Task {
                                try await damus_state.purple.verify_npub_for_checkout(checkout_id: checkout_id)
                                verified = true
                            }
                        }, label: {
                            HStack {
                                Spacer()
                                Text(NSLocalizedString("Verify my npub", comment: "Button label to verify the user's npub for the purpose of Purple subscription checkout"))
                                Spacer()
                            }
                        })
                        .padding(.horizontal, 30)
                        .buttonStyle(GradientButtonStyle())
                    }
                    else {
                        Text(NSLocalizedString("Verified! Please head back to the checkout page to continue", comment: "Instructions after the user has verified their npub for Damus Purple purchase checkout"))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.green)
                    }
                    
                }
                .padding([.trailing, .leading], 30)
                .padding(.bottom, 20)
            }
        }
    }
        
    func Subtitle(_ txt: String) -> some View {
        Text(txt)
            .foregroundColor(.white.opacity(0.65))
    }
}

#Preview {
    DamusPurpleVerifyNpubView(damus_state: test_damus_state, checkout_id: "123")
}
