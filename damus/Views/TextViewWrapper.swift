//
//  TextViewWrapper.swift
//  damus
//
//  Created by Swift on 2/24/23.
//

import SwiftUI

struct TextViewWrapper: UIViewRepresentable {
    @Binding var attributedText: NSMutableAttributedString
    @EnvironmentObject var tagModel: TagModel
    @Binding var textHeight: CGFloat?
    let initialTextSuffix: String?
    
    let cursorIndex: Int?
    var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil
    let updateCursorPosition: ((Int) -> Void)
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = UIColor(DamusColors.adaptableWhite)
        textView.delegate = context.coordinator
        
        // Disable scrolling (this view will expand vertically as needed to fit text)
        textView.isScrollEnabled = false
        // Set low content compression resistance to make this view wrap lines of text, and avoid text overflowing to the right
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Inline text suggestions interfere with mentions generation
        if #available(iOS 17.0, *) {
            textView.inlinePredictionType = .no
        }
        
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

        // Set the text height that will fit all the text
        // This is needed because the UIKit auto-layout prefers to overflow the text to the right than to expand the text box vertically, even with low horizontal compression resistance
        self.setIdealHeight(uiView: uiView)

        uiView.selectedRange = NSRange(location: range.location + tagModel.diff, length: range.length)
        tagModel.diff = 0
    }
    
    /// Based on our desired layout, calculate the ideal size of the text box, then set the height to the ideal size
    private func setIdealHeight(uiView: UITextView) {
        DispatchQueue.main.async {  // Queue on main thread, because modifying view state directly during re-render causes undefined behavior
            let idealSize = uiView.sizeThatFits(CGSize(
                width: uiView.frame.width,  // We want to stay within the horizontal bounds given to us
                height: .infinity           // We can expand vertically without any resistance
            ))
            if self.textHeight != idealSize.height {    // Only update height when it changes, to avoid infinite re-render calls
                self.textHeight = idealSize.height
            }
        }
    }

    private func setCursorPosition(textView: UITextView) {
        guard let index = cursorIndex, let newPosition = textView.position(from: textView.beginningOfDocument, offset: index) else {
            return
        }
        textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedText: $attributedText, getFocusWordForMention: getFocusWordForMention, updateCursorPosition: updateCursorPosition, initialTextSuffix: initialTextSuffix)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var attributedText: NSMutableAttributedString
        var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil
        let updateCursorPosition: ((Int) -> Void)
        let initialTextSuffix: String?
        var initialTextSuffixWasAdded: Bool = false

        init(attributedText: Binding<NSMutableAttributedString>,
             getFocusWordForMention: ((String?, NSRange?) -> Void)?,
             updateCursorPosition: @escaping ((Int) -> Void),
             initialTextSuffix: String?
        ) {
            _attributedText = attributedText
            self.getFocusWordForMention = getFocusWordForMention
            self.updateCursorPosition = updateCursorPosition
            self.initialTextSuffix = initialTextSuffix
        }

        func textViewDidChange(_ textView: UITextView) {
            if let initialTextSuffix, !self.initialTextSuffixWasAdded {
                self.initialTextSuffixWasAdded = true
                var mutable = NSMutableAttributedString(attributedString: textView.attributedText)
                let originalRange = textView.selectedRange
                addUnattributedText(initialTextSuffix, to: &mutable, inRange: originalRange)
                attributedText = mutable
                DispatchQueue.main.async {
                    self.updateCursorPosition(originalRange.location)
                }
            }
            else {
                attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            }
            processFocusedWordForMention(textView: textView)
        }

        private func processFocusedWordForMention(textView: UITextView) {
            var val: (String?, NSRange?) = (nil, nil)
            
            guard let selectedRange = textView.selectedTextRange else { return }
            
            let wordRange = rangeOfMention(in: textView, from: selectedRange.start)
            
            if let wordRange,
               let startPosition = textView.position(from: wordRange.start, offset: -1),
               let cursorPosition = textView.position(from: selectedRange.start, offset: 0)
            {
                let word = textView.text(in: textView.textRange(from: startPosition, to: cursorPosition)!)
                val = (word, convertToNSRange(startPosition, cursorPosition, textView))
            }
            
            getFocusWordForMention?(val.0, val.1)
        }
        
        func rangeOfMention(in textView: UITextView, from position: UITextPosition) -> UITextRange? {
            var startPosition = position

            while startPosition != textView.beginningOfDocument {
                guard let previousPosition = textView.position(from: startPosition, offset: -1),
                      let range = textView.textRange(from: previousPosition, to: startPosition),
                      let text = textView.text(in: range), !text.isEmpty,
                      let lastChar = text.last else {
                    break
                }

                if [" ", "\n", "@"].contains(lastChar) {
                    break
                }

                startPosition = previousPosition
            }

            return startPosition == position ? nil : textView.textRange(from: startPosition, to: position)
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

