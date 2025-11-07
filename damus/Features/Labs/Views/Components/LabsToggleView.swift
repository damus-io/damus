//
//  LabsToggleView.swift
//  damus
//
//  Created by eric on 11/6/25.
//

import SwiftUI

struct LabsToggleView: View {
    let toggleName: String
    let systemImage: String
    @Binding var isOn: Bool
    @Binding var showInfo: Bool
    
    var body: some View {
        HStack {
            HStack {
                Toggle(toggleName, systemImage: systemImage, isOn: $isOn)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .font(.title2)
                    .foregroundColor(.white)
                    .fontWeight(.bold)
            }
            .padding(15)
            .background(DamusColors.black)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isOn ? DamusColors.purple : DamusColors.neutral6, lineWidth: 2)
            )
            
            Image("info")
                .foregroundColor(DamusColors.purple)
                .onTapGesture {
                    showInfo.toggle()
                }
        }
    }
}
