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

    static func parseMarkdown(content: String) -> AttributedString {
        // Similar to the parsing in NoteContentView
        let md_opts: AttributedString.MarkdownParsingOptions =
            .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)

        if let txt = try? AttributedString(markdown: content, options: md_opts) {
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
            guard let range = Range(match.range, in: input) else { continue }
            let url = input[range]
            output.replaceSubrange(range, with: "[\(url)](\(Markdown.withScheme(url)))")
        }
        // TODO: escape unintentional markdown
        return Markdown.parseMarkdown(content: output)
    }
}
