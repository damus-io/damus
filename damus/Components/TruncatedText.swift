//
//  TruncatedText.swift
//  damus
//
//  Created by William Casarin on 2023-04-06.
//

import SwiftUI

struct TruncatedText: View {
    let text: CompatibleText
    let maxChars: Int = 280
    
    var body: some View {
        let truncatedAttributedString: AttributedString? = getTruncatedString()
        
        if let truncatedAttributedString {
            Text(truncatedAttributedString)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            text.text
                .fixedSize(horizontal: false, vertical: true)
        }
        
        if truncatedAttributedString != nil {
            Spacer()
            Button(NSLocalizedString("Show more", comment: "Button to show entire note.")) { }
                .allowsHitTesting(false)
        }
    }
    
    func getTruncatedString() -> AttributedString? {
        let nsAttributedString = NSAttributedString(text.attributed)
        if nsAttributedString.length < maxChars { return nil }
        
        let range = NSRange(location: 0, length: maxChars)
        let truncatedAttributedString = nsAttributedString.attributedSubstring(from: range)
        
        return AttributedString(truncatedAttributedString) + "..."
    }
}

struct TruncatedText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 100) {
            TruncatedText(text: CompatibleText(stringLiteral: "hello\nthere\none\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven"))
                .frame(width: 200, height: 200)
            
            TruncatedText(text: CompatibleText(stringLiteral: "hello\nthere\none\ntwo\nthree\nfour"))
                .frame(width: 200, height: 200)
        }
    }
}
