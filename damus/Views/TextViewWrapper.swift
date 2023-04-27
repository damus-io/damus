//
//  TextViewWrapper.swift
//  damus
//
//  Created by Swift on 2/24/23.
//

import SwiftUI

struct TextViewWrapper: UIViewRepresentable {
    @Binding var attributedText: NSMutableAttributedString
    @EnvironmentObject var postModel: PostModel
    
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
        var selectedRange = NSRange()
        if postModel.willLoadDraft {
            selectedRange = NSRange(location: uiView.selectedRange.location + attributedText.string.count,
                                    length: uiView.selectedRange.length)
            DispatchQueue.main.async {
                postModel.willLoadDraft = false
            }
        }
        else {
            if postModel.justMadeATagSelection {
                selectedRange = NSRange(location: uiView.selectedRange.location + postModel.latestTaggedUsername.count - postModel.tagSearchQueryLength + 1,
                                        length: uiView.selectedRange.length)
            } else {
                selectedRange = uiView.selectedRange
            }
            postModel.justMadeATagSelection = false
        }
        uiView.isScrollEnabled = false
        uiView.attributedText = attributedText
        uiView.selectedRange = selectedRange
        uiView.isScrollEnabled = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedText: $attributedText)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        @Binding var attributedText: NSMutableAttributedString

        init(attributedText: Binding<NSMutableAttributedString>) {
            _attributedText = attributedText
        }

        func textViewDidChange(_ textView: UITextView) {
            attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
        }
    }
}

