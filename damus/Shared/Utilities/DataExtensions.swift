//
//  DataExtensions.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-09-17.
//
import Foundation

extension Data {
    var byteArray: [UInt8] {
        var bytesToReturn: [UInt8] = []
        for i in self.bytes.byteOffsets {
            bytesToReturn.append(self[i])
        }
        return bytesToReturn
    }
}
