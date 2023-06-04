//
//  Markdown.swift
//  damus
//
//  Created by Lionello Lunesu on 2022-12-28.
//

import Foundation
import SwiftUI

func count_leading_hashes(_ str: String) -> Int {
    var count = 0
    for c in str {
        if c == "#" {
            count += 1
        } else {
            break
        }
    }
    
    return count
}

func get_heading_title_size(count: Int) -> SwiftUI.Font {
    if count >= 3 {
        return Font.title3
    } else if count >= 2 {
        return Font.title2
    } else if count >= 1 {
        return Font.title
    }
    
    return Font.body
}

public struct Markdown {
    private var detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    
    /// Ensure the specified URL has a scheme by prepending "https://" if it's absent.
    static func withScheme(_ url: any StringProtocol) -> any StringProtocol {
        return url.contains("://") ? url : "https://" + url
    }

    /// Parse a string with markdown into an `AttributedString`, if possible, or else return it as regular text.
    public static func parse(content: String) -> AttributedString {
        let md_opts: AttributedString.MarkdownParsingOptions =
            .init(interpretedSyntax: .full)
        
        guard content.utf8.count > 0 else {
            return AttributedString(stringLiteral: "")
        }
        
        let leading_hashes = count_leading_hashes(content)
        if leading_hashes > 0 {
            if var str = try? AttributedString(markdown: content) {
                str.font = get_heading_title_size(count: leading_hashes)
                return str
            }
        }

        // TODO: escape unintentional markdown
        let escaped = content.replacingOccurrences(of: "\\_", with: "\\\\\\_")
        if let txt = try? AttributedString(markdown: escaped, options: md_opts) {
            return txt
        } else {
            return AttributedString(stringLiteral: content)
        }
    }

    /// Process the input text and add markdown for any embedded URLs.
    public func process(_ input: String) -> AttributedString {
        guard let detector else {
            return AttributedString(stringLiteral: input)
        }
        let matches = detector.matches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count))
        var output = input
        // Start with the last match, because replacing the first would invalidate all subsequent indices
        for match in matches.reversed() {
            guard let range = Range(match.range, in: input)
                , let url = match.url else { continue }
            let text = input[range]
            // Use the absoluteString from the matched URL, except when it defaults to http (since we default to https)
            let uri = url.scheme == "http" ? Markdown.withScheme(text) : url.absoluteString
            output.replaceSubrange(range, with: "[\(text)](\(uri))")
        }
        return Markdown.parse(content: output)
    }
}
