//
//  LibreTranslateServer.swift
//  damus
//
//  Created by Terry Yiu on 1/21/23.
//

import Foundation

enum LibreTranslateServer: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }

    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var tag: String
        var displayName: String
        var url: String?
    }

    case argosopentech
    case terraprint
    case vern
    case custom

    var model: Model {
        switch self {
        case .argosopentech:
            return .init(tag: self.rawValue, displayName: "translate.argosopentech.com", url: "https://translate.argosopentech.com")
        case .terraprint:
            return .init(tag: self.rawValue, displayName: "translate.terraprint.co", url: "https://translate.terraprint.co")
        case .vern:
            return .init(tag: self.rawValue, displayName: "lt.vern.cc", url: "https://lt.vern.cc")
        case .custom:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("Custom", comment: "Dropdown option for selecting a custom translation server."), url: nil)
        }
    }

    static var allModels: [Model] {
        return Self.allCases.map { $0.model }
    }
}
