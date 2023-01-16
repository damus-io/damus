//
//  LNUrls.swift
//  damus
//
//  Created by William Casarin on 2023-01-17.
//

import Foundation

class LNUrls {
    var endpoints: [String: LNUrlPayRequest]
    
    init() {
        self.endpoints = [:]
    }
    
    func lookup(_ id: String) -> LNUrlPayRequest? {
        return self.endpoints[id]
    }
}
