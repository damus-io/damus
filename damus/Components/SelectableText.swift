//
//  SelectableText.swift
//  damus
//
//  Created by Oleg Abalonski on 2/16/23.
//

import UIKit
import SwiftUI

struct SelectableText: View {
    let damus_state: DamusState
    let event: NostrEvent?
    let attributedString: AttributedString
    let textAlignment: NSTextAlignment
    @State private var showHighlightPost = false
    @State private var selectedText = ""
    @State private var selectedTextHeight: CGFloat = .zero
    @State private var selectedTextWidth: CGFloat = .zero

    let size: EventViewKind

    init(damus_state: DamusState, event: NostrEvent?, attributedString: AttributedString, textAlignment: NSTextAlignment? = nil, size: EventViewKind) {
        self.damus_state = damus_state
        self.event = event
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
                enableHighlighting: self.enableHighlighting(),
                showHighlightPost: $showHighlightPost,
                selectedText: $selectedText,
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
        .sheet(isPresented: $showHighlightPost) {
            if let event {
                HighlightPostView(damus_state: damus_state, event: event, selectedText: $selectedText)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.height(selectedTextHeight + 150), .medium, .large])
            }
        }
        .frame(height: selectedTextHeight)
    }
    
    func enableHighlighting() -> Bool {
        self.event != nil
    }
}

fileprivate class TextView: UITextView {
    @Binding var showHighlightPost: Bool
    @Binding var selectedText: String

    init(frame: CGRect, textContainer: NSTextContainer?, showHighlightPost: Binding<Bool>, selectedText: Binding<String>) {
        self._showHighlightPost = showHighlightPost
        self._selectedText = selectedText
        super.init(frame: frame, textContainer: textContainer)
    }

    required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(highlightText(_:)) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc public func highlightText(_ sender: Any?) {
        guard let selectedRange = self.selectedTextRange else { return }
        selectedText = self.text(in: selectedRange) ?? ""
        showHighlightPost.toggle()
    }

}

 fileprivate struct TextViewRepresentable: UIViewRepresentable {

    let attributedString: AttributedString
    let textColor: UIColor
    let font: UIFont
    let fixedWidth: CGFloat
    let textAlignment: NSTextAlignment
    let enableHighlighting: Bool
    @Binding var showHighlightPost: Bool
    @Binding var selectedText: String
    @Binding var height: CGFloat

    func makeUIView(context: UIViewRepresentableContext<Self>) -> TextView {
        let view = TextView(frame: .zero, textContainer: nil, showHighlightPost: $showHighlightPost, selectedText: $selectedText)
        view.isEditable = false
        view.dataDetectorTypes = .all
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.textContainerInset.left = 1.0
        view.textContainerInset.right = 1.0
        view.textAlignment = textAlignment

        let menuController = UIMenuController.shared
        let highlightItem = UIMenuItem(title: "Highlight", action: #selector(view.highlightText(_:)))
        menuController.menuItems = self.enableHighlighting ? [highlightItem] : []

        return view
    }

    func updateUIView(_ uiView: TextView, context: UIViewRepresentableContext<Self>) {
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
