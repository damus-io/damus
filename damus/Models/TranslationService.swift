//
//  TranslationService.swift
//  damus
//
//  Created by Terry Yiu on 2/3/23.
//

import Foundation

enum TranslationService: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }

    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var tag: String
        var displayName: String
    }

    case none
    case libretranslate
    case deepl

    var model: Model {
        switch self {
        case .none:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("None", comment: "Dropdown option for selecting no translation service."))
        case .libretranslate:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("LibreTranslate (Open Source)", comment: "Dropdown option for selecting LibreTranslate as the translation service."))
        case .deepl:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("DeepL (Proprietary, Higher Accuracy)", comment: "Dropdown option for selecting DeepL as the translation service."))
        }
    }

    static var allModels: [Model] {
        return Self.allCases.map { $0.model }
    }
}
