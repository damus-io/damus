//
//  Array.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-05-10.
//

import Foundation

extension Array {
    /// Splits the array into chunks of the specified size.
    /// - Parameter size: The maximum size of each chunk.
    /// - Returns: An array of arrays, where each contained array is a chunk of the original array with up to `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension Array where Element: Equatable {
    mutating func removeAll(equalTo item: Element) {
        self.removeAll(where: { $0 == item })
    }
}
