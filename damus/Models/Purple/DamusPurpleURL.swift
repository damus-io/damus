//
//  DamusPurpleURL.swift
//  damus
//
//  Created by Daniel Nogueira on 2024-01-13.
//

import Foundation

enum DamusPurpleURL {
    case verify_npub(checkout_id: String)
    case welcome(checkout_id: String)
    case landing

    static func from_url(url: URL) -> DamusPurpleURL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard components.scheme == "damus" else { return nil }
        switch components.path {
            case "purple:verify":
                guard let checkout_id = components.find("id") else { return nil }
                return .verify_npub(checkout_id: checkout_id)
            case "purple:welcome":
                guard let checkout_id = components.find("id") else { return nil }
                return .welcome(checkout_id: checkout_id)
            case "purple:landing":
                return .landing
            default:
                return nil
        }
    }
    
    func url_string() -> String {
        switch self {
            case .verify_npub(let id):
                return "damus:purple:verify?id=\(id)"
            case .welcome(let id):
                return "damus:purple:welcome?id=\(id)"
            case .landing:
                return "damus:purple:landing"
        }
    }
    
}

extension URLComponents {
    func find(_ name: String) -> String? {
        self.queryItems?.first(where: { qi in qi.name == name })?.value
    }
}
