//
//  LogoView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-02-09.
//

import SwiftUI

// MARK: - More helper views

extension DamusPurpleView {
    struct LogoView: View {
        var body: some View {
            HStack(spacing: 20) {
                Image("damus-dark-logo")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 15.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(LinearGradient(
                                colors: [DamusColors.lighterPink.opacity(0.8), .white.opacity(0), DamusColors.deepPurple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing), lineWidth: 1)
                    )
                    .shadow(radius: 5)
                
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("Purple", comment: "Subscription service name"))
                        .font(.system(size: 60.0).weight(.bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DamusColors.lighterPink, DamusColors.deepPurple],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .tracking(-2)
                }
            }
            .padding(.bottom, 30)
        }
    }
}

#Preview {
    DamusPurpleView.LogoView()
}
