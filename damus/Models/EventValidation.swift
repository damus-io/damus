//
//  EventValidation.swift
//  damus
//
//  Created by Jonathan on 2/22/23.
//

import Foundation

enum EventValidation: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var index: Int
        var tag: String
        var displayName : String
    }
    
    case none
    case subscribed
    case all
    
    var model: Model {
        switch self {
        case .none:
            return .init(index: -1, tag: "none", displayName: NSLocalizedString("None", comment: "None, not a single one"))
        case .subscribed:
            return .init(index: 1, tag: "subscribed", displayName: NSLocalizedString("People you follow", comment: "Only the notes from the people you follow"))
        case .all:
            return .init(index: 2, tag: "all", displayName: NSLocalizedString("All", comment: "Every single one"))
        }
    }
    
    static var allModels: [Model] {
        return Self.allCases.map { $0.model }
    }
}
