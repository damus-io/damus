//
//  CustomPicker.swift
//  damus
//
//  Created by Eric Holguin on 1/22/23.
//

import SwiftUI

let RECTANGLE_GRADIENT = LinearGradient(gradient: Gradient(colors: [
    Color("DamusPurple"),
    Color("DamusBlue")
]), startPoint: .leading, endPoint: .trailing)

struct CustomPicker<SelectionValue: Hashable, Content: View>: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    @Namespace var picker
    @Binding var selection: SelectionValue
    @ViewBuilder let content: Content
    
    public var body: some View {
        let contentMirror = Mirror(reflecting: content)
        let blocksCount = Mirror(reflecting: contentMirror.descendant("value")!).children.count
        HStack {
            ForEach(0..<blocksCount, id: \.self) { index in
                let tupleBlock = contentMirror.descendant("value", ".\(index)")
                let text = Mirror(reflecting: tupleBlock!).descendant("content") as! Text
                let tag = Mirror(reflecting: tupleBlock!).descendant("modifier", "value", "tagged") as! SelectionValue
                
                Button {
                    withAnimation(.spring()) {
                        selection = tag
                    }
                } label: {
                    text
                        .padding(EdgeInsets(top: 15, leading: 0, bottom: 10, trailing: 0))
                        .font(.system(size: 14, weight: .heavy))
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
        colorScheme == .light ? Color("DamusBlack") : Color("DamusWhite")
    }
}
