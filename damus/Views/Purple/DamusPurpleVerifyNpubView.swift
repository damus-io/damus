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
    
    let subtitle_height: CGFloat = 100.0

    @Environment(\.openURL) var openURL

    init(damus_state: DamusState, checkout_id: String, verified: Bool = false) {
        self.damus_state = damus_state
        self.checkout_id = checkout_id
        self._verified = State(wrappedValue: verified)
    }

    var checkout_url: URL {
        let page_url = damus_state.purple.environment.purple_landing_page_url()
        return URL(string: "\(page_url)/checkout?id=\(checkout_id)")!
    }

    var body: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(Color.black)
                .background(Color.black)
            
            VStack {
                DamusPurpleView.LogoView()

                VStack(alignment: .center, spacing: 30) {

                    if !verified {
                        Subtitle(NSLocalizedString("To continue your Purple subscription checkout, please verify your npub by clicking on the button below", comment: "Instruction on how to verify npub during Damus Purple checkout"))

                            .frame(height: subtitle_height)
                            .multilineTextAlignment(.center)

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
                        Text(NSLocalizedString("Verified!", comment: "Instructions after the user has verified their npub for Damus Purple purchase checkout"))
                                .frame(height: subtitle_height)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.green)

                        Button(action: {
                            openURL(checkout_url)
                        }, label: {
                            HStack {
                                Spacer()
                                Text(NSLocalizedString("Continue", comment: "Prompt to user to continue"))
                                Spacer()
                            }
                        })
                        .padding(.horizontal, 30)
                        .buttonStyle(GradientButtonStyle())
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
    VStack(spacing: 0) {
        DamusPurpleVerifyNpubView(damus_state: test_damus_state, checkout_id: "123")

        DamusPurpleVerifyNpubView(damus_state: test_damus_state, checkout_id: "123", verified: true)
    }
}
