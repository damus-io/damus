//
//  DamusGradient.swift
//  damus
//
//  Created by William Casarin on 2023-05-09.
//

import SwiftUI

fileprivate let damus_grad_c1 = hex_col(r: 0x1c, g: 0x55, b: 0xff)
fileprivate let damus_grad_c2 = hex_col(r: 0x7f, g: 0x35, b: 0xab)
fileprivate let damus_grad_c3 = hex_col(r: 0xff, g: 0x0b, b: 0xd6)
fileprivate let damus_grad = [damus_grad_c1, damus_grad_c2, damus_grad_c3]

struct DamusGradient: View {
    var body: some View {
        DamusGradient.gradient
            .edgesIgnoringSafeArea([.top,.bottom])
    }
    
    static var gradient: LinearGradient {
         LinearGradient(colors: damus_grad, startPoint: .bottomLeading, endPoint: .topTrailing)
    }
}

struct DamusGradient_Previews: PreviewProvider {
    static var previews: some View {
        DamusGradient()
    }
}
