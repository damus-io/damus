//
//  DamusLightGradient.swift
//  damus
//
//  Created by eric on 9/8/23.
//

import SwiftUI

fileprivate let damus_grad_c1 = hex_col(r: 0xd3, g: 0x2d, b: 0xc3)
fileprivate let damus_grad_c2 = hex_col(r: 0x33, g: 0xc5, b: 0xbc)
fileprivate let damus_grad = [damus_grad_c1, damus_grad_c2]

struct DamusLightGradient: View {
    var body: some View {
        DamusLightGradient.gradient
            .opacity(0.5)
            .edgesIgnoringSafeArea([.top,.bottom])
    }

    static var gradient: LinearGradient {
         LinearGradient(colors: damus_grad, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct DamusLightGradient_Previews: PreviewProvider {
    static var previews: some View {
        DamusLightGradient()
    }
}
