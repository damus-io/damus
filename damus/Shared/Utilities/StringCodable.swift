//
//  StringCodable.swift
//  damus
//
//  Created by William Casarin on 2023-04-21.
//

import Foundation

protocol StringCodable {
    init?(from string: String)
    func to_string() -> String
}
