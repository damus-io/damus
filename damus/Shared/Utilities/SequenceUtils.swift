//
//  SequenceUtils.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

extension Sequence {
    func just_one() -> Element? {
        var got_one = false
        var the_x: Element? = nil
        for x in self {
            guard !got_one else {
                return nil
            }
            the_x = x
            got_one = true
        }
        return the_x
    }
}
