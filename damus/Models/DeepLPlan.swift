//
//  DeepLPlan.swift
//  damus
//
//  Created by Terry Yiu on 2/3/23.
//

import Foundation

enum DeepLPlan: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }

    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var tag: String
        var displayName: String
        var url: String
    }

    case free
    case pro

    var model: Model {
        switch self {
        case .free:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("Free", comment: "Dropdown option for selecting Free plan for DeepL translation service."), url: "https://api-free.deepl.com")
        case .pro:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("Pro", comment: "Dropdown option for selecting Pro plan for DeepL translation service."), url: "https://api.deepl.com")
        }
    }

    static var allModels: [Model] {
        return Self.allCases.map { $0.model }
    }
}
