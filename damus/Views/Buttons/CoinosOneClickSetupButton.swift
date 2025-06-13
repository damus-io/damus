//
//  CoinosButton.swift
//  damus
//
//  Created by eric on 1/7/25.
//

import SwiftUI

struct CoinosOneClickSetupButton: View {
    let action: () -> ()
    
    @Environment(\.colorScheme) var colorScheme
    
    init(action: @escaping () -> ()) {
        self.action = action
    }
    
    var body: some View {
        Button(action: {
            action()
        }) {
            HStack {
                Image("coinos")
                    .resizable()
                    .frame(width: 35, height: 35)
                
                Text("Coinos one-click setup", comment:  "Button to attach a Coinos Wallet via a one-click setup. Coinos is a service that provides a Lightning wallet for zapping sats, and its name should not be translated.")
                    .padding()
                    .bold()
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            .foregroundColor(DamusColors.black)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(GrayGradient, strokeBorder: colorScheme == .light ? DamusColors.black.opacity(0.2) : DamusColors.white.opacity(0.2), lineWidth: 1)
            }
        }
    }
}

struct CoinosButton_Previews: PreviewProvider {
    static var previews: some View {
        CoinosOneClickSetupButton(action: {
            print("mutiny button")
        })
    }
}
