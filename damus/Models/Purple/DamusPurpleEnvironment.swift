//
//  DamusPurpleEnvironment.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-01-29.
//

import Foundation

enum DamusPurpleEnvironment: CaseIterable, Codable, Identifiable, StringCodable, Equatable, Hashable {
    static var allCases: [DamusPurpleEnvironment] = [.local_test(host: nil), .staging, .production]
    
    case local_test(host: String?)
    case staging
    case production

    func text_description() -> String {
        switch self {
            case .local_test:
                return NSLocalizedString("Test (local)", comment: "Label indicating a local test environment for Damus Purple functionality (Developer feature)")
            case .staging:
                return NSLocalizedString("Staging", comment: "Label indicating a staging test environment for Damus Purple functionality (Developer feature)")
            case .production:
                return NSLocalizedString("Production", comment: "Label indicating the production environment for Damus Purple")
        }
    }

    func api_base_url() -> URL {
        switch self {
            case .local_test(let host):
                URL(string: "http://\(host ?? "localhost"):8989") ?? Constants.PURPLE_API_LOCAL_TEST_BASE_URL
            case .staging:
                Constants.PURPLE_API_STAGING_BASE_URL
            case .production:
                Constants.PURPLE_API_PRODUCTION_BASE_URL
                
        }
    }

    func purple_landing_page_url() -> URL {
        switch self {
            case .local_test(let host):
                URL(string: "http://\(host ?? "localhost"):3000/purple") ?? Constants.PURPLE_LANDING_PAGE_LOCAL_TEST_URL
            case .staging:
                Constants.PURPLE_LANDING_PAGE_STAGING_URL
            case .production:
                Constants.PURPLE_LANDING_PAGE_PRODUCTION_URL
                
        }
    }

    func damus_website_url() -> URL {
        switch self {
            case .local_test(let host):
                URL(string: "http://\(host ?? "localhost"):3000") ?? Constants.DAMUS_WEBSITE_LOCAL_TEST_URL
            case .staging:
                Constants.DAMUS_WEBSITE_STAGING_URL
            case .production:
                Constants.DAMUS_WEBSITE_PRODUCTION_URL
                
        }
    }
    
    func custom_host() -> String? {
        switch self {
            case .local_test(let host):
                return host
            default:
                return nil
        }
    }

    init?(from string: String) {
        switch string {
            case "local_test":
                self = .local_test(host: nil)
            case "staging":
                self = .staging
            case "production":
                self = .production
            default:
                let components = string.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if components.count == 2 && components[0] == "local_test" {
                    self = .local_test(host: String(components[1]))
                } else {
                    return nil
                }
        }
    }

    func to_string() -> String {
        switch self {
            case .local_test(let host):
                if let host {
                    return "local_test:\(host)"
                }
                return "local_test"
            case .staging:
                return "staging"
            case .production:
                return "production"
        }
    }

    var id: String {
        switch self {
            case .local_test(let host):
                if let host {
                    return "local_test:\(host)"
                }
                else {
                    return "local_test"
                }
            case .staging:
                return "staging"
            case .production:
                return "production"
        }
    }
}
