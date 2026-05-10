//
//  DataExtensions.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-09-17.
//
import Foundation

extension Data {
    /// Returns the contents of the Data value as a byte array.
    var byteArray: [UInt8] {
        return [UInt8](self)
    }
}
