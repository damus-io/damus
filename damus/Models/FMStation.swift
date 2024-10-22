//
//  FMStation.swift
//  damus
//
//  Created by Swift on 10/22/24.
//

import Foundation

enum FMStation : String, CaseIterable, Identifiable, StringCodable, Equatable {
    var id: String { self.rawValue }

    func to_string() -> String {
        return rawValue
    }
    
    init?(from string: String) {
        guard let station = FMStation(rawValue: string) else {
            return nil
        }
        self = station
    }
    
    var radioStreamLink: String? {
        switch self {
        case .radioParadise:
            return "http://stream-uk1.radioparadise.com/aac-320"
        case .none:
            return nil
        }
    }
    
    var displayStreamLink: String {
        switch self {
        case .radioParadise:
            return "http://stream-uk1.radioparadise.com"
        case .none:
            return "none"
        }
    }
    
    case none
    case radioParadise
}
