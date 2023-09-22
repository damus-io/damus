//
//  GrayGradient.swift
//  damus
//
//  Created by klabo on 7/20/23.
//

import SwiftUI

let GrayGradient = LinearGradient(gradient:
                                    Gradient(colors: [Color(#colorLiteral(red: 0.9764705882, green: 0.9803921569, blue: 0.9803921569, alpha: 1))]),
                                  startPoint: .leading,
                                  endPoint: .trailing)

struct GrayGradientView: View {
    var body: some View {
        GrayGradient
            .edgesIgnoringSafeArea([.top, .bottom])
    }
}

struct GrayGradient_Previews: PreviewProvider {
    static var previews: some View {
        GrayGradientView()
    }
}
