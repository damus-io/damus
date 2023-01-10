//
//  ContentParser.swift
//  damus
//
//  Created by Joel Klabo on 1/10/23.
//

import Foundation

public struct ContentParser {
    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    
    public static func parse(_ content: String?) -> AttributedString {
        guard let content else { return AttributedString(stringLiteral: "") }
        
        var attributedString = AttributedString(stringLiteral: content)
        
        let linkMatches = linkDetector.matches(in: content, range: NSRange(location: 0, length: content.count - 1))
        
        for linkMatch in linkMatches {
            guard let url = linkMatch.url else { continue }
            guard let range = attributedString.range(of: url.absoluteString) else { continue }
            attributedString[range].link = url
            attributedString[range].foregroundColor = .purple
        }
        
        return attributedString
    }
}
