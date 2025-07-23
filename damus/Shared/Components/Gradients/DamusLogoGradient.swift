//
//  DamusLogoGradient.swift
//  damus
//
//  Created by eric on 5/24/23.
//

import SwiftUI

fileprivate let damus_logo_grad_c1 = hex_col(r: 0x30, g: 0xb3, b: 0xf1)
fileprivate let damus_logo_grad_c2 = hex_col(r: 0xc5, g: 0x39, b: 0xf9)
fileprivate let damus_logo_grad = [damus_logo_grad_c1, damus_logo_grad_c2]

struct DamusLogoGradient: View {
    var body: some View {
        DamusLogoGradient.gradient
            .edgesIgnoringSafeArea([.top,.bottom])
    }
    
    static var gradient: LinearGradient {
         LinearGradient(colors: damus_logo_grad, startPoint: .leading, endPoint: .trailing)
    }
}

struct DamusLogoGradient_Previews: PreviewProvider {
    static var previews: some View {
        DamusLogoGradient()
    }
}
