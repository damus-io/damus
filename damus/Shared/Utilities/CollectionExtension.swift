//
//  CollectionExtension.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-25.
//

import Foundation

extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
