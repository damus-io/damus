//
//  AttrStringTestExtensions.swift
//  damusTests
//
//  Created by William Casarin on 2023-07-17.
//

import Foundation
import XCTest

extension NSAttributedString {
    func testAttributes(conditions: [([Key: Any]) -> Void]) throws {
        var count = 0

        self.enumerateAttributes(in: .init(0..<self.length)) { attrs, range, stop in
            if count > conditions.count {
                XCTAssert(false, "too many attributes \(count) attrs > \(conditions.count) conditions")
            }

            conditions[count](attrs)

            count += 1
        }

        XCTAssertEqual(count, conditions.count)
    }
}
