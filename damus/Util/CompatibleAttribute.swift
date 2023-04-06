//
//  CompatibleAttribute.swift
//  damus
//
//  Created by William Casarin on 2023-04-06.
//

import Foundation
import SwiftUI

class CompatibleText: Equatable {
    var text: Text
    var attributed: AttributedString
    
    init() {
        self.text = Text("")
        self.attributed = AttributedString(stringLiteral: "")
    }
    
    init(stringLiteral: String) {
        self.text = Text(stringLiteral)
        self.attributed = AttributedString(stringLiteral: stringLiteral)
    }
    
    init(text: Text, attributed: AttributedString) {
        self.text = text
        self.attributed = attributed
    }
    
    init(attributed: AttributedString) {
        self.text = Text(attributed)
        self.attributed = attributed
    }
    
    static func == (lhs: CompatibleText, rhs: CompatibleText) -> Bool {
        return lhs.attributed == rhs.attributed
    }
    
    static func +(lhs: CompatibleText, rhs: CompatibleText) -> CompatibleText {
        let combinedText = lhs.text + rhs.text
        let combinedAttributes = lhs.attributed + rhs.attributed
        return CompatibleText(text: combinedText, attributed: combinedAttributes)
    }
}
