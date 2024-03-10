//
//  AlbyButton.swift
//  damus
//
//  Created by William Casarin on 2023-05-09.
//

import SwiftUI

struct AlbyButton: View {
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
                Image("alby")
                
                Text("Connect to Alby Wallet", comment:  "Button to attach an Alby Wallet, a service that provides a Lightning wallet for zapping sats. Alby is the name of the service and should not be translated.")
                    .padding()
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            .foregroundColor(DamusColors.black)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AlbyGradient, strokeBorder: colorScheme == .light ? DamusColors.black.opacity(0.2) : DamusColors.white, lineWidth: 1)
            }
        }
    }
}

struct AlbyButton_Previews: PreviewProvider {
    static var previews: some View {
        AlbyButton(action: {
            print("alby button")
        })
    }
}
