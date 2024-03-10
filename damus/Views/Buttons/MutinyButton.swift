//
//  MutinyButton.swift
//  damus
//
//  Created by eric on 3/9/24.
//

import SwiftUI

struct MutinyButton: View {
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
                Image("mutiny")
                    .resizable()
                    .frame(width: 45, height: 45)
                
                Text("Connect to Mutiny Wallet", comment:  "Button to attach an Mutiny Wallet, a service that provides a Lightning wallet for zapping sats. Mutiny is the name of the service and should not be translated.")
                    .padding()
            }
            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            .foregroundColor(DamusColors.white)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(MutinyGradient, strokeBorder: colorScheme == .light ? DamusColors.black.opacity(0.2) : DamusColors.white.opacity(0.2), lineWidth: 1)
            }
        }
    }
}

struct MutinyButton_Previews: PreviewProvider {
    static var previews: some View {
        MutinyButton(action: {
            print("mutiny button")
        })
    }
}
