//
//  BalanceView.swift
//  damus
//
//  Created by eric on 1/23/25.
//

import SwiftUI

struct BalanceView: View {
    var balance: Int64?

    @Binding var hide_balance: Bool

    var body: some View {
        VStack(spacing: 5) {
            Text("Current balance", comment: "Label for displaying current wallet balance")
                .foregroundStyle(DamusColors.neutral6)
            if let balance {
                self.numericalBalanceView(text: NumberFormatter.localizedString(from: NSNumber(integerLiteral: Int(balance)), number: .decimal))
            }
            else {
                // Make sure we do not show any numeric value to the user when still loading (or when failed to load)
                // This is important because if we show a numeric value like "zero" when things are not loaded properly, we risk scaring the user into thinking that they have lost funds.
                self.numericalBalanceView(text: "??")
                    .redacted(reason: .placeholder)
                    .shimmer(true)
            }
        }
    }
    
    func numericalBalanceView(text: String) -> some View {
        Group {
            if hide_balance {
                Text(verbatim: "*****")
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
                    .font(.veryVeryLargeTitle)
                    .fontWeight(.heavy)
                    .foregroundStyle(PinkGradient)

            } else {
                HStack {
                    Text(verbatim: text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .font(.veryVeryLargeTitle)
                        .fontWeight(.heavy)
                        .foregroundStyle(PinkGradient)

                    HStack(alignment: .top) {
                        Text("SATS", comment: "Abbreviation for Satoshis, smallest bitcoin unit")
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundStyle(PinkGradient)
                    }
                }
            }
        }
        .privacySensitive()
        .padding(.bottom)
        .onTapGesture {
            hide_balance.toggle()
        }
    }
}

struct BalanceView_Previews: PreviewProvider {
    @State private static var hide_balance: Bool = false
    static var previews: some View {
        BalanceView(balance: 100000000, hide_balance: $hide_balance)
        BalanceView(balance: nil, hide_balance: $hide_balance)
    }
}

