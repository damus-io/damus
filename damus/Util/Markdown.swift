//
//  Markdown.swift
//  damus
//
//  Created by Lionello Lunesu on 2022-12-28.
//

import Foundation

public struct Markdown {
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
}
