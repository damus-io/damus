//
//  TextViewWrapper.swift
//  damus
//
//  Created by Swift on 2/24/23.
//

import SwiftUI

struct TextViewWrapper: UIViewRepresentable {
    @Binding var attributedText: NSMutableAttributedString
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 18)
        //textView.textColor = UIColor.black
        let linkAttributes: [NSAttributedString.Key : Any] = [
            NSAttributedString.Key.foregroundColor: UIColor(Color.accentColor)]
        textView.linkTextAttributes = linkAttributes
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
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

