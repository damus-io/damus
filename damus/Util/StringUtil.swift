//
//  StringUtil.swift
//  damus
//
//  Created by Terry Yiu on 6/4/23.
//

import Foundation

extension String {
    /// Returns a copy of the String truncated to maxLength and "..." ellipsis appended to the end,
    /// or if the String does not exceed maxLength, the String itself is returned without truncation or added ellipsis.
    func truncate(maxLength: Int) -> String {
        guard count > maxLength else {
            return self
        }

        return self[...self.index(self.startIndex, offsetBy: maxLength - 1)] + "..."
    }
}

extension AttributedString {
    /// Returns a copy of the AttributedString truncated to maxLength and "..." ellipsis appended to the end,
    /// or if the AttributedString does not exceed maxLength, nil is returned.
    func truncateOrNil(maxLength: Int) -> AttributedString? {
        let nsAttributedString = NSAttributedString(self)
        if nsAttributedString.length < maxLength { return nil }

        let range = NSRange(location: 0, length: maxLength)
        let truncatedAttributedString = nsAttributedString.attributedSubstring(from: range)

        return AttributedString(truncatedAttributedString) + "..."
    }
}
