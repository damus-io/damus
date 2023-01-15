//
//  Utility.swift
//  damus
//
//  Created by Swift on 1/14/23.
//

import SwiftUI

extension String {

    /// Conform plurality of word based on the count
    /// - Parameter count: Generic type count
    /// - Returns: String appended with 's' if necessary
    func conformPlurality<T>(count: T) -> String {
        var string = self
        if let value = count as? Int,
            value != 1 {
            string.append("s")
        } else if let stringValue = count as? String,
                  let value = Int(stringValue),
                    value != 1 {
            string.append("s")
        }
        return string
    }

    func conformPlurality<T>(count: T) -> LocalizedStringKey {
        LocalizedStringKey(self.conformPlurality(count: count))
    }
}
