//
//  Created by Jericho Hasselbush on 9/9/23.
//


// Test fix for https://github.com/damus-io/damus/issues/1525
// Only change in damus source is in UserSearch.swift
// UserSearch.appendUserTag

import XCTest
@testable import damus

final class UserSearchAppendTests: XCTestCase {
    func testCursorShouldBeAtEndOfEmoji() throws {
        let simpleTag = NSMutableAttributedString("@JB55")
        let emojiTag = NSMutableAttributedString("@BTCapsule 🏴🧡")
        let post = NSMutableAttributedString("A Post")

        var cursorIndex: Int = 0
        appendUserTag(withTag: simpleTag, post: post, word_range: .init(location: 0, length: 0), newCursorIndex: &cursorIndex, spy: simulatedCursor )
        XCTAssertEqual(cursorIndex, simpleTag.length + 1) // +1 for past end of tag
        cursorIndex = 0
        appendUserTag(withTag: emojiTag, post: post, word_range: .init(location: 0, length: 0), newCursorIndex: &cursorIndex, spy: simulatedCursor)
        XCTAssertEqual(cursorIndex, emojiTag.length + 1) // +1 for past end of tag
    }
}

typealias CursorSpy = (Int, NSMutableAttributedString) -> Void

var simulatedCursor: CursorSpy = { cursorIndex, tag in
    let tagWithSimulatedCursor = NSMutableAttributedString(attributedString: tag)
    if tagWithSimulatedCursor.length < cursorIndex {
        tagWithSimulatedCursor.append(.init(string: "|"))
    } else {
        tagWithSimulatedCursor.insert(.init(string: "|"), at: cursorIndex)
    }
    print(tagWithSimulatedCursor.string)
}

func appendUserTag(withTag tag: NSMutableAttributedString,
                   post: NSMutableAttributedString,
                   word_range: NSRange,
                   newCursorIndex: inout Int,
                   spy: CursorSpy = { _, _ in }) {
    let appended = append_user_tag(tag: tag, post: post, word_range: word_range)

    // faulty call
//     newCursorIndex = word_range.location + appended.tag.string.count

    // good call
    newCursorIndex = word_range.location + appended.tag.length

    spy(newCursorIndex, tag)
}
