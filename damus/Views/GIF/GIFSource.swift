//
//  GIFSource.swift
//  damus
//
//  Created by Swift on 5/16/23.
//

import Foundation

enum GIFSource: String, CaseIterable, Identifiable, StringCodable {

    init?(from string: String) {
        guard let gifSource = GIFSource(rawValue: string) else {
            return nil
        }
        self = gifSource
    }

    func to_string() -> String {
        return self.rawValue
    }

    var id: String { self.rawValue }

    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var tag: String
        var displayName: String
    }

    case none
    case giphy

    var model: Model {
        switch self {
        case .none:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("none_gif_source", value: "None", comment: "Dropdown option for selecting no gif source."))
        case .giphy:
            return .init(tag: self.rawValue, displayName: NSLocalizedString("https://giphy.com", comment: "Dropdown option for selecting Giphy as the gif source."))
        }
    }
}
