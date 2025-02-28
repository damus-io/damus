//
//  BalanceView.swift
//  damus
//
//  Created by eric on 1/23/25.
//

import SwiftUI

struct BalanceView: View {
    
    var balance: Int64
    
    var body: some View {
        VStack(spacing: 5) {
            Text("Current balance")
                .foregroundStyle(DamusColors.neutral6)
            HStack {
                Text("\(balance)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .font(.system(size: 70))
                    .fontWeight(.heavy)
                    .foregroundStyle(PinkGradient)
                HStack(alignment: .top) {
                    Text("SATS")
                        .font(.system(size: 12))
                        .fontWeight(.heavy)
                        .foregroundStyle(PinkGradient)
                }
            }
            .padding(.bottom)
        }
    }
}

struct BalanceView_Previews: PreviewProvider {
    static var previews: some View {
        BalanceView(balance: 100000000)
    }
}

