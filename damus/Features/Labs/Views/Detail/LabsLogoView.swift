//
//  LabsLogoView.swift
//  damus
//
//  Created by eric on 10/17/25.
//

import SwiftUI

struct LabsLogoView: View {
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
                HStack(spacing: 0) {
                    Text("Labs ", comment: "Feature name")
                        .font(.system(size: 60.0).weight(.bold))
                        .foregroundColor(.white)
                        .tracking(-2)
                    Image(systemName: "flask.fill")
                        .padding(.top, 25)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DamusColors.deepPurple, DamusColors.lighterPink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "testtube.2")
                        .padding(.top, 25)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DamusColors.lighterPink, DamusColors.deepPurple],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )
                        )
                }
            }
        }
        .padding(.bottom, 30)
    }
}


#Preview {
    PurpleBackdrop {
        LabsLogoView()
    }
}
