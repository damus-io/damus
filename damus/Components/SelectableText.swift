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
    
    @State private var selectedTextHeight: CGFloat = .zero
    @State private var selectedTextWidth: CGFloat = .zero
    
    let size: EventViewKind
    
    @Binding var tappedUniversalLink: URL?
    
    var body: some View {
        GeometryReader { geo in
            TextViewRepresentable(
                attributedString: attributedString,
                textColor: UIColor.label,
                font: eventviewsize_to_uifont(size),
                fixedWidth: selectedTextWidth,
                tappedUniversalLink: $tappedUniversalLink,
                height: $selectedTextHeight
            )
            .padding([.leading, .trailing], -1.0)
            .onAppear {
                self.selectedTextWidth = geo.size.width
            }
            .onChange(of: geo.size) { newSize in
                self.selectedTextWidth = newSize.width
            }
        }
        .frame(height: selectedTextHeight)
    }
}

fileprivate struct TextViewRepresentable: UIViewRepresentable {
    
    class Coordinator: NSObject, UITextViewDelegate {
        private let parent: TextViewRepresentable
        
        init(parent: TextViewRepresentable) {
            self.parent = parent
        }
        
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            guard let comps = URLComponents(url: URL, resolvingAgainstBaseURL: false) else {
                return true
            }
            
            if comps.host == "damus.io" {
                parent.tappedUniversalLink = URL
                return false
            } else {
                return true
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
     
    let attributedString: AttributedString
    let textColor: UIColor
    let font: UIFont
    let fixedWidth: CGFloat
    
    @Binding var tappedUniversalLink: URL?
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
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UITextView, context: UIViewRepresentableContext<Self>) {
        let mutableAttributedString = createNSAttributedString()
        uiView.attributedText = mutableAttributedString

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
