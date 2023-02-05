//
//  File.swift
//  damus
//
//  Created by devandsev on 2/4/23.
//

import SwiftUI

struct SelectableRowView <Content: View>: View {
    
    @Binding var isSelected: Bool
    var shouldChangeSelection: () -> Bool
    var content: () -> Content
    
    @available(iOS, deprecated: 16, message: "In iOS 15 List rows selection works only in editing mode; with iOS 16 selection doesn't require Edit button at all. Consider using standard selection mechanism when deployment target is iOS 16")
    init(isSelected: Binding<Bool>, shouldChangeSelection: @escaping () -> Bool = { true }, @ViewBuilder content: @escaping () -> Content) {
        _isSelected = isSelected
        self.shouldChangeSelection = shouldChangeSelection
        self.content = content
    }
    
    var body: some View {
        HStack {
            content()
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if shouldChangeSelection() {
                isSelected.toggle()
            }
        }
    }
}
