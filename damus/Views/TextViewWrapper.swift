//
//  TextViewWrapper.swift
//  damus
//
//  Created by Swift on 2/24/23.
//

import SwiftUI

struct TextViewWrapper: UIViewRepresentable {
    @Binding var attributedText: NSMutableAttributedString
    @Binding var postTextViewCanScroll: Bool
    @EnvironmentObject var tagModel: TagModel
    
    let cursorIndex: Int?
    var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil
    let updateCursorPosition: ((Int) -> Void)
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isScrollEnabled = postTextViewCanScroll
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
        uiView.isScrollEnabled = postTextViewCanScroll
        uiView.attributedText = attributedText

        TextViewWrapper.setTextProperties(uiView)
        setCursorPosition(textView: uiView)
        let range = uiView.selectedRange

        uiView.selectedRange = NSRange(location: range.location + tagModel.diff, length: range.length)
        tagModel.diff = 0
    }

    private func setCursorPosition(textView: UITextView) {
        guard let index = cursorIndex, let newPosition = textView.position(from: textView.beginningOfDocument, offset: index) else {
            return
        }
        textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedText: $attributedText, getFocusWordForMention: getFocusWordForMention, updateCursorPosition: updateCursorPosition)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var attributedText: NSMutableAttributedString
        var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil
        let updateCursorPosition: ((Int) -> Void)

        init(attributedText: Binding<NSMutableAttributedString>, getFocusWordForMention: ((String?, NSRange?) -> Void)?, updateCursorPosition: @escaping ((Int) -> Void)) {
            _attributedText = attributedText
            self.getFocusWordForMention = getFocusWordForMention
            self.updateCursorPosition = updateCursorPosition
        }

        func textViewDidChange(_ textView: UITextView) {
            attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            processFocusedWordForMention(textView: textView)
        }

        private func processFocusedWordForMention(textView: UITextView) {
            var val: (String?, NSRange?) = (nil, nil)
            
            guard let selectedRange = textView.selectedTextRange else { return }
            
            let wordRange = textView.tokenizer.rangeEnclosingPosition(selectedRange.start, with: .word, inDirection: .init(rawValue: UITextLayoutDirection.left.rawValue))
            
            if let wordRange,
               let startPosition = textView.position(from: wordRange.start, offset: -1),
               let cursorPosition = textView.position(from: selectedRange.start, offset: 0)
            {
                let word = textView.text(in: textView.textRange(from: startPosition, to: cursorPosition)!)
                val = (word, convertToNSRange(startPosition, cursorPosition, textView))
            }
            
            getFocusWordForMention?(val.0, val.1)
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

        // This `UITextViewDelegate` method is automatically called by the editor when edits occur, to check whether a change should occur
        // We will use this method to manually handle edits concerning mention ("@") links, to avoid manual text edits to attributed mention links
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard let attributedString = textView.attributedText else {
                return true     // If we cannot get an attributed string, just fail gracefully and allow changes
            }
            var mutable = NSMutableAttributedString(attributedString: attributedString)
            
            let entireRange = NSRange(location: 0, length: attributedString.length)
            var shouldAllowChange = true
            var performEditActionManually = false

            attributedString.enumerateAttribute(.link, in: entireRange, options: []) { (value, linkRange, stop) in
                guard value != nil else {
                    return  // This range is not a link. Skip checking.
                }
                
                if range.contains(linkRange.upperBound) && range.contains(linkRange.lowerBound) {
                    // Edit range engulfs all of this link's range.
                    // This link will naturally disappear, so no work needs to be done in this range.
                    return
                }
                else if linkRange.intersection(range) != nil {
                    // If user tries to change an existing link directly, remove the link attribute
                    mutable.removeAttribute(.link, range: linkRange)
                    // Perform action manually to flush above changes to the view, and to prevent the character being added from having an attributed link property
                    performEditActionManually = true
                    return
                }
                else if range.location == linkRange.location + linkRange.length && range.length == 0 {
                    // If we are inserting a character at the right edge of a link, UITextInput tends to include the new character inside the link.
                    // Therefore, we need to manually append that character outside of the link
                    performEditActionManually = true
                    return
                }
            }
            
            if performEditActionManually {
                shouldAllowChange = false
                addUnattributedText(text, to: &mutable, inRange: range)
                attributedText = mutable
                
                // Move caret to the end of the newly changed text.
                updateCursorPosition(range.location + text.count)
            }

            return shouldAllowChange
        }

        func addUnattributedText(_ text: String, to attributedString: inout NSMutableAttributedString, inRange range: NSRange) {
            if range.length == 0 {
                attributedString.insert(NSAttributedString(string: text, attributes: nil), at: range.location)
            }
            else {
                attributedString.replaceCharacters(in: range, with: text)
            }
        }
        
    }
}

