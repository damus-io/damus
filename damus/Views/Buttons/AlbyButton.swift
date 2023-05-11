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
                
                Text("Attach Alby Wallet", comment:  "Button to attach an Alby Wallet, a service that provides a Lightning wallet for zapping sats. Alby is the name of the service and should not be translated.")
            }
            .offset(x: -25)
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .center)
            .foregroundColor(DamusColors.black)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(AlbyGradient, strokeBorder: colorScheme == .light ? DamusColors.black : DamusColors.white, lineWidth: 2)
            }
            .padding(EdgeInsets(top: 10, leading: 50, bottom: 25, trailing: 50))
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
