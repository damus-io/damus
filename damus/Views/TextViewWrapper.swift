//
//  TextViewWrapper.swift
//  damus
//
//  Created by Swift on 2/24/23.
//

import SwiftUI

// Defines how much extra bottom spacing will be applied after the text.
// This will avoid jitters when applying new lines, by ensuring it has enough space until the height is updated on the next view update cycle
let TEXT_BOX_BOTTOM_MARGIN_OFFSET: CGFloat = 30.0

struct TextViewWrapper: UIViewRepresentable {
    @Binding var attributedText: NSMutableAttributedString
    @EnvironmentObject var tagModel: TagModel
    @Binding var textHeight: CGFloat?
    
    let cursorIndex: Int?
    var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil
    let updateCursorPosition: ((Int) -> Void)
    let onCaretRectChange: ((UITextView) -> Void)
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        
        // Scroll has to be enabled. When this is disabled, the text input will overflow horizontally, even when its frame's width is limited.
        textView.isScrollEnabled = true
        // However, a scrolling text box inside of its parent scrollview does not provide a very good experience. We should have the textbox expand vertically
        // To simulate that the text box can expand vertically, we will listen to text changes and dynamically change the text box height in response.
        // Add an observer so that we can adapt the height of the text input whenever the text changes.
        textView.addObserver(context.coordinator, forKeyPath: "contentSize", options: .new, context: nil)
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
        Coordinator(attributedText: $attributedText, getFocusWordForMention: getFocusWordForMention, updateCursorPosition: updateCursorPosition, onCaretRectChange: onCaretRectChange, textHeight: $textHeight)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var attributedText: NSMutableAttributedString
        var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil
        let updateCursorPosition: ((Int) -> Void)
        let onCaretRectChange: ((UITextView) -> Void)
        @Binding var textHeight: CGFloat?

        init(attributedText: Binding<NSMutableAttributedString>,
             getFocusWordForMention: ((String?, NSRange?) -> Void)?,
             updateCursorPosition: @escaping ((Int) -> Void),
             onCaretRectChange: @escaping ((UITextView) -> Void),
             textHeight: Binding<CGFloat?>
        ) {
            _attributedText = attributedText
            self.getFocusWordForMention = getFocusWordForMention
            self.updateCursorPosition = updateCursorPosition
            self.onCaretRectChange = onCaretRectChange
            _textHeight = textHeight
        }

        func textViewDidChange(_ textView: UITextView) {
            attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            processFocusedWordForMention(textView: textView)
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            textView.scrollRangeToVisible(textView.selectedRange)
            onCaretRectChange(textView)
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
        
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "contentSize", let textView = object as? UITextView {
                DispatchQueue.main.async {
                    // Update text view height when text content size changes to fit all text content
                    // This is necessary to avoid having a scrolling text box combined with its parent scrolling view
                    self.updateTextViewHeight(textView: textView)
                }
            }
        }
        
        func updateTextViewHeight(textView: UITextView) {
            self.textHeight = textView.contentSize.height + TEXT_BOX_BOTTOM_MARGIN_OFFSET
        }
        
    }
}

