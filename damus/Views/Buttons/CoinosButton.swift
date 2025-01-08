//
//  CoinosButton.swift
//  damus
//
//  Created by eric on 1/7/25.
//

import SwiftUI

struct CoinosButton: View {
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
                
                Text("Connect to Coinos", comment:  "Button to attach a Coinos Wallet, a service that provides a Lightning wallet for zapping sats. Coinos is the name of the service and should not be translated.")
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
        CoinosButton(action: {
            print("mutiny button")
        })
    }
}
