//
//  TextViewWrapper.swift
//  damus
//
//  Created by Swift on 2/24/23.
//

import SwiftUI

struct TextViewWrapper: UIViewRepresentable {
    @Binding var attributedText: NSMutableAttributedString
    let cursorIndex: Int?
    var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.showsVerticalScrollIndicator = false
        TextViewWrapper.setTextProperties(textView)
        return textView
    }
    
    static func setTextProperties(_ uiView: UITextView) {
        uiView.textColor = UIColor.label
        uiView.font = UIFont.preferredFont(forTextStyle: .body)
        let linkAttributes: [NSAttributedString.Key : Any] = [
            NSAttributedString.Key.foregroundColor: UIColor(Color.accentColor)]
        uiView.linkTextAttributes = linkAttributes
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
        TextViewWrapper.setTextProperties(uiView)
        setCursorPosition(textView: uiView)
    }

    private func setCursorPosition(textView: UITextView) {
        guard let index = cursorIndex, let newPosition = textView.position(from: textView.beginningOfDocument, offset: index) else {
            return
        }
        textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedText: $attributedText, getFocusWordForMention: getFocusWordForMention)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var attributedText: NSMutableAttributedString
        var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil

        init(attributedText: Binding<NSMutableAttributedString>, getFocusWordForMention: ((String?, NSRange?) -> Void)?) {
            _attributedText = attributedText
            self.getFocusWordForMention = getFocusWordForMention
        }

        func textViewDidChange(_ textView: UITextView) {
            attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            processFocusedWordForMention(textView: textView)
        }

        private func processFocusedWordForMention(textView: UITextView) {
            if let selectedRange = textView.selectedTextRange {
                var val: (String?, NSRange?)
                if let wordRange = textView.tokenizer.rangeEnclosingPosition(selectedRange.start, with: .word, inDirection: .init(rawValue: UITextLayoutDirection.left.rawValue)) {
                    if let startPosition = textView.position(from: wordRange.start, offset: -1),
                       let cursorPosition = textView.position(from: selectedRange.start, offset: 0) {
                        let word = textView.text(in: textView.textRange(from: startPosition, to: cursorPosition)!)
                        val = (word, convertToNSRange(startPosition, cursorPosition, textView))
                    }
                }
                getFocusWordForMention?(val.0, val.1)
            }
        }

        private func convertToNSRange( _ startPosition: UITextPosition, _ endPosition: UITextPosition, _ textView: UITextView) -> NSRange? {
            let startOffset = textView.offset(from: textView.beginningOfDocument, to: startPosition)
            let endOffset = textView.offset(from: textView.beginningOfDocument, to: endPosition)
            let length = endOffset - startOffset
            guard length >= 0, startOffset >= 0 else {
                return nil
            }
            return NSRange(location: startOffset, length: length)
        }
    }
}

