//
//  Markdown.swift
//  damus
//
//  Created by Lionello Lunesu on 2022-12-28.
//

import Foundation

public struct Markdown {
    private let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Ensure the specified URL has a scheme by prepending "https://" if it's absent.
    static func withScheme(_ url: any StringProtocol) -> any StringProtocol {
        return url.contains("://") ? url : "https://" + url
    }

    /// Parse a string with markdown into an `AttributedString`, if possible, or else return it as regular text.
    public static func parse(content: String) -> AttributedString {
        let md_opts: AttributedString.MarkdownParsingOptions =
            .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)

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
