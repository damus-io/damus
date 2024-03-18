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
    
    init(text: CompatibleText, maxChars: Int = 280) {
        self.text = text
        self.maxChars = maxChars
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
            Button(NSLocalizedString("Show more", comment: "Button to show entire note.")) { }
                .allowsHitTesting(false)
        }
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
