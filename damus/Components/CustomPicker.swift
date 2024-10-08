//
//  CustomPicker.swift
//  damus
//
//  Created by Eric Holguin on 1/22/23.
//

import SwiftUI

let RECTANGLE_GRADIENT = LinearGradient(gradient: Gradient(colors: [
    DamusColors.purple,
    DamusColors.blue
]), startPoint: .leading, endPoint: .trailing)

struct CustomPicker<SelectionValue: Hashable>: View {
    
    let tabs: [(String, SelectionValue)]
    @Environment(\.colorScheme) var colorScheme

    @Namespace var picker
    @Binding var selection: SelectionValue

    public var body: some View {
        HStack {
            ForEach(tabs, id: \.1) { (text, tag) in
                Button {
                    withAnimation(.spring()) {
                        selection = tag
                    }
                } label: {
                    Text(text).padding(EdgeInsets(top: 15, leading: 0, bottom: 10, trailing: 0))
                        .font(.system(size: 14, weight: .heavy))
                        .tag(tag)
                }
                .background(
                    Group {
                        if tag == selection {
                            Rectangle().fill(RECTANGLE_GRADIENT).frame(height: 2.5)
                                .matchedGeometryEffect(id: "selector", in: picker)
                                .cornerRadius(2.5)
                        }
                    },
                    alignment: .bottom
                )
                .frame(maxWidth: .infinity)
                .accentColor(tag == selection ? textColor() : .gray)
            }
        }
    }
    
    func textColor() -> Color {
        colorScheme == .light ? DamusColors.black : DamusColors.white
    }
}
