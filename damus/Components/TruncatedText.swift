//
//  TruncatedText.swift
//  damus
//
//  Created by William Casarin on 2023-04-06.
//

import SwiftUI

struct TruncatedText: View {
    let text: CompatibleText
    let maxChars: Int
    let show_show_more_button: Bool
    
    init(text: CompatibleText, maxChars: Int = 280, show_show_more_button: Bool) {
        self.text = text
        self.maxChars = maxChars
        self.show_show_more_button = show_show_more_button
    }
    
    var body: some View {
        let truncatedAttributedString: AttributedString? = text.attributed.truncateOrNil(maxLength: maxChars)
        
        if let truncatedAttributedString {
            Text(truncatedAttributedString)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            text.text
                .fixedSize(horizontal: false, vertical: true)
        }
        
        if truncatedAttributedString != nil {
            Spacer()
            if self.show_show_more_button {
                Button(NSLocalizedString("Show more", comment: "Button to show entire note.")) { }
                    .allowsHitTesting(false)
            }
        }
    }
}

struct TruncatedText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 100) {
            TruncatedText(text: CompatibleText(stringLiteral: "hello\nthere\none\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven"), show_show_more_button: true)
                .frame(width: 200, height: 200)
            
            TruncatedText(text: CompatibleText(stringLiteral: "hello\nthere\none\ntwo\nthree\nfour"), show_show_more_button: true)
                .frame(width: 200, height: 200)
        }
    }
}
