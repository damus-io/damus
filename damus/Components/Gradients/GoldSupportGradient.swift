//
//  GoldSupportGradient.swift
//  damus
//
//  Created by William Casarin on 2023-05-15.
//

import SwiftUI

fileprivate let gold_grad_c1 = hex_col(r: 226, g: 168, b: 0)
fileprivate let gold_grad_c2 = hex_col(r: 249, g: 243, b: 100)

fileprivate let gold_grad = [gold_grad_c2, gold_grad_c1]

let GoldGradient: LinearGradient =
    LinearGradient(colors: gold_grad, startPoint: .bottomLeading, endPoint: .topTrailing)

struct GoldGradientView: View {
    var body: some View {
        GoldGradient
            .edgesIgnoringSafeArea([.top,.bottom])
    }
}

struct GoldGradientView_Previews: PreviewProvider {
    static var previews: some View {
        GoldGradientView()
    }
}
