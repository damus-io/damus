//
//  DataExtensions.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-09-17.
//
import Foundation

extension Data {
    var byteArray: [UInt8] {
        return [UInt8](self)
    }
}
