//
//  SelectableText.swift
//  damus
//
//  Created by Oleg Abalonski on 2/16/23.
//

import UIKit
import SwiftUI

struct SelectableText: View {
    
    let attributedString: AttributedString
    let textAlignment: NSTextAlignment
    
    @State private var selectedTextHeight: CGFloat = .zero
    @State private var selectedTextWidth: CGFloat = .zero
    
    let size: EventViewKind
    
    init(attributedString: AttributedString, textAlignment: NSTextAlignment? = nil, size: EventViewKind) {
        self.attributedString = attributedString
        self.textAlignment = textAlignment ?? NSTextAlignment.natural
        self.size = size
    }
    
    var body: some View {
        GeometryReader { geo in
            TextViewRepresentable(
                attributedString: attributedString,
                textColor: UIColor.label,
                font: eventviewsize_to_uifont(size),
                fixedWidth: selectedTextWidth,
                textAlignment: self.textAlignment,
                height: $selectedTextHeight
            )
            .padding([.leading, .trailing], -1.0)
            .onAppear {
                if geo.size.width == .zero {
                    self.selectedTextHeight = 1000.0
                } else {
                    self.selectedTextWidth = geo.size.width
                }
            }
            .onChange(of: geo.size) { newSize in
                self.selectedTextWidth = newSize.width
            }
        }
        .frame(height: selectedTextHeight)
    }
}

 fileprivate struct TextViewRepresentable: UIViewRepresentable {

    let attributedString: AttributedString
    let textColor: UIColor
    let font: UIFont
    let fixedWidth: CGFloat
    let textAlignment: NSTextAlignment

    @Binding var height: CGFloat

    func makeUIView(context: UIViewRepresentableContext<Self>) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.dataDetectorTypes = .all
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.textContainerInset.left = 1.0
        view.textContainerInset.right = 1.0
        view.textAlignment = textAlignment
        return view
    }

    func updateUIView(_ uiView: UITextView, context: UIViewRepresentableContext<Self>) {
        let mutableAttributedString = createNSAttributedString()
        uiView.attributedText = mutableAttributedString
        uiView.textAlignment = self.textAlignment

        let newHeight = mutableAttributedString.height(containerWidth: fixedWidth)

        DispatchQueue.main.async {
            height = newHeight
        }
    }

    func createNSAttributedString() -> NSMutableAttributedString {
        let mutableAttributedString = NSMutableAttributedString(attributedString)
        let myAttribute = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: textColor
        ]

        mutableAttributedString.addAttributes(
            myAttribute,
            range: NSRange.init(location: 0, length: mutableAttributedString.length)
        )

        return mutableAttributedString
    }
}

fileprivate extension NSAttributedString {

    func height(containerWidth: CGFloat) -> CGFloat {

        let rect = self.boundingRect(
            with: CGSize.init(width: containerWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        return ceil(rect.size.height)
    }
}
