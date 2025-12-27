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
    @Binding var imagePastedFromPasteboard: PreUploadedMedia?
    @Binding var imageUploadConfirmPasteboard: Bool
    
    let cursorIndex: Int?
    var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil
    let updateCursorPosition: ((Int) -> Void)
    var onImageURLPasted: ((URL) -> Void)? = nil
    
    func makeUIView(context: Context) -> UITextView {
        let textView = CustomPostTextView(imagePastedFromPasteboard: $imagePastedFromPasteboard,
                                          imageUploadConfirm: $imageUploadConfirmPasteboard)
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
        // Save the current selection BEFORE making any changes
        // This is critical because setting attributedText causes UITextView to reset the cursor position
        let savedRange = uiView.selectedRange

        uiView.attributedText = attributedText

        TextViewWrapper.setTextProperties(uiView)

        // Restore cursor position with priority:
        // 1. If cursorIndex is explicitly set (e.g., from mention insertion), use it
        // 2. Otherwise, restore the saved range with tag diff adjustment
        // Clamp saved selection to current text bounds to avoid out-of-range resets after text mutations
        let adjustedLocation = max(0, min(savedRange.location + tagModel.diff, attributedText.length))
        let adjustedLength = max(0, min(savedRange.length, attributedText.length - adjustedLocation))
        let selectionRange = NSRange(location: adjustedLocation, length: adjustedLength)

        if let index = cursorIndex,
           let newPosition = uiView.position(from: uiView.beginningOfDocument, offset: index),
           let textRange = uiView.textRange(from: newPosition, to: newPosition) {
            uiView.selectedTextRange = textRange
            tagModel.diff = 0
            self.setIdealHeight(uiView: uiView)
            return
        }   // If the explicit cursor target is invalid, fall back to the saved range

        // Restore the saved range, adjusted for any tag model changes
        uiView.selectedRange = selectionRange
        tagModel.diff = 0
        self.setIdealHeight(uiView: uiView)
    }
    
    /// Based on our desired layout, calculate the ideal size of the text box, then set the height to the ideal size.
    ///
    /// Sets the text height that will fit all the text.
    /// This is needed because the UIKit auto-layout prefers to overflow the text to the right than to expand the text box vertically, even with low horizontal compression resistance.
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

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedText: $attributedText, getFocusWordForMention: getFocusWordForMention, updateCursorPosition: updateCursorPosition, initialTextSuffix: initialTextSuffix, onImageURLPasted: onImageURLPasted)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var attributedText: NSMutableAttributedString
        var getFocusWordForMention: ((String?, NSRange?) -> Void)? = nil
        let updateCursorPosition: ((Int) -> Void)
        let initialTextSuffix: String?
        var initialTextSuffixWasAdded: Bool = false
        var onImageURLPasted: ((URL) -> Void)? = nil
        static let ESCAPE_SEQUENCES = ["\n", "@", "  ", ", ", ". ", "! ", "? ", "; ", "#"]

        /// Regex pattern for detecting image URLs (matches common image extensions with optional query params).
        /// Excludes fragment identifiers (#) since content after # is not sent to the server.
        static let imageURLPattern = try! NSRegularExpression(
            pattern: #"^https?://[^\s#]+\.(jpg|jpeg|png|gif|webp|svg)(\?[^\s]*)?$"#,
            options: [.caseInsensitive]
        )

        init(attributedText: Binding<NSMutableAttributedString>,
             getFocusWordForMention: ((String?, NSRange?) -> Void)?,
             updateCursorPosition: @escaping ((Int) -> Void),
             initialTextSuffix: String?,
             onImageURLPasted: ((URL) -> Void)? = nil
        ) {
            _attributedText = attributedText
            self.getFocusWordForMention = getFocusWordForMention
            self.updateCursorPosition = updateCursorPosition
            self.initialTextSuffix = initialTextSuffix
            self.onImageURLPasted = onImageURLPasted
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
                      let range = textView.textRange(from: previousPosition, to: position),
                      let text = textView.text(in: range), !text.isEmpty else {
                    break
                }
                
                startPosition = previousPosition
                
                if let styling = textView.textStyling(at: previousPosition, in: .backward),
                   styling[NSAttributedString.Key.link] != nil {
                    break
                }
                
                var found_escape_sequence = false
                for escape_sequence in Self.ESCAPE_SEQUENCES {
                    if text.contains(escape_sequence) {
                        startPosition = textView.position(from: startPosition, offset: escape_sequence.count) ?? startPosition
                        found_escape_sequence = true
                        break
                    }
                }
                if found_escape_sequence { break }
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
            // Check if pasted text is an image URL and handle it specially
            if let onImageURLPasted = onImageURLPasted,
               !text.isEmpty,
               let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               Self.imageURLPattern.firstMatch(in: text.trimmingCharacters(in: .whitespacesAndNewlines), options: [], range: NSRange(location: 0, length: text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count)) != nil {
                onImageURLPasted(url)
                return false  // Don't insert the URL text, it will appear as a media preview
            }

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

class CustomPostTextView: UITextView {
    @Binding var imagePastedFromPasteboard: PreUploadedMedia?
    @Binding var imageUploadConfirm: Bool
    
    // Custom initializer
    init(imagePastedFromPasteboard: Binding<PreUploadedMedia?>, imageUploadConfirm: Binding<Bool>) {
        self._imagePastedFromPasteboard = imagePastedFromPasteboard
        self._imageUploadConfirm = imageUploadConfirm
        super.init(frame: .zero, textContainer: nil)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Override canPerformAction to enable image pasting
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(UIResponderStandardEditActions.paste(_:)),
           UIPasteboard.general.image != nil {
            return true // Show `Paste` option while long-pressing if there is an image present in the clipboard
        }
        return super.canPerformAction(action, withSender: sender) // Default behavior for other actions
    }

    // Override paste to handle image pasting
    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general

        if let data = pasteboard.data(forPasteboardType: Constants.GIF_IMAGE_TYPE),
           let url = saveGIFToTemporaryDirectory(data) {
            imagePastedFromPasteboard = PreUploadedMedia.unprocessed_image(url)
            imageUploadConfirm = true
        } else if let image = pasteboard.image {
            // handle .png, .jpeg files here
            imagePastedFromPasteboard = PreUploadedMedia.uiimage(image)
            // Show alert view in PostView for Confirming upload
            imageUploadConfirm = true
        } else {
            // fall back to default paste behavior if no image or gif file found
            super.paste(sender)
        }
    }

    private func saveGIFToTemporaryDirectory(_ data: Data) -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let gifURL = tempDirectory.appendingPathComponent("pasted_image.gif")
        do {
            try data.write(to: gifURL)
            return gifURL
        } catch {
            return nil
        }
    }
}
