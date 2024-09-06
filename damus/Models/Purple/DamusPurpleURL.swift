//
//  DamusPurpleURL.swift
//  damus
//
//  Created by Daniel D'Aquino on 2024-01-13.
//

import Foundation


struct DamusPurpleURL: Equatable {
    let is_staging: Bool
    let variant: Self.Variant

    enum Variant: Equatable {
        case verify_npub(checkout_id: String)
        case welcome(checkout_id: String)
        case landing
    }

    init(is_staging: Bool, variant: Self.Variant) {
        self.is_staging = is_staging
        self.variant = variant
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard components.scheme == "damus" else { return nil }
        let is_staging = components.find("staging") != nil
        switch components.path {
            case "purple:verify":
                guard let checkout_id = components.find("id") else { return nil }
                self = .init(is_staging: is_staging, variant: .verify_npub(checkout_id: checkout_id))
            case "purple:welcome":
                guard let checkout_id = components.find("id") else { return nil }
                self = .init(is_staging: is_staging, variant: .welcome(checkout_id: checkout_id))
            case "purple:landing":
                self = .init(is_staging: is_staging, variant: .landing)
            default:
                return nil
        }
    }

    func url_string() -> String {
        let staging = is_staging ? "&staging=true" : ""
        switch self.variant {
        case .verify_npub(let id):
            return "damus:purple:verify?id=\(id)\(staging)"
        case .welcome(let id):
            return "damus:purple:welcome?id=\(id)\(staging)"
        case .landing:
            let staging = is_staging ? "?staging=true" : ""
            return "damus:purple:landing\(staging)"
        }
    }

}

extension URLComponents {
    func find(_ name: String) -> String? {
        self.queryItems?.first(where: { qi in qi.name == name })?.value
    }
}
