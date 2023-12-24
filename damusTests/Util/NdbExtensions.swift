//
//  NdbExtensions.swift
//  damusTests
//
//  Created by Charlie Fish on 12/23/23.
//

import Foundation
@testable import damus

extension Ndb {
    static var test: Ndb {
        var tempDir: String!
        do {
            let fileManager = FileManager.default
            let temp = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: temp, withIntermediateDirectories: true, attributes: nil)
            tempDir = temp.absoluteString
        } catch {
            tempDir = "."
        }

        print("opening \(tempDir!)")
        return Ndb(path: tempDir)!
    }
}
