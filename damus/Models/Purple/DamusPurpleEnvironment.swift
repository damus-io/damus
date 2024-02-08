//
//  DamusPurpleEnvironment.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-01-29.
//

import Foundation

enum DamusPurpleEnvironment: String, CaseIterable, Codable, Identifiable, StringCodable, Equatable {
    case local_test
    case staging
    case production

    func text_description() -> String {
        switch self {
            case .local_test:
                return NSLocalizedString("Test (localhost)", comment: "Label indicating a localhost test environment for Damus Purple functionality (Developer feature)")
            case .staging:
                return NSLocalizedString("Staging", comment: "Label indicating a staging test environment for Damus Purple functionality (Developer feature)")
            case .production:
                return NSLocalizedString("Production", comment: "Label indicating the production environment for Damus Purple")
        }
    }

    func api_base_url() -> URL {
        switch self {
            case .local_test:
                Constants.PURPLE_API_LOCAL_TEST_BASE_URL
            case .staging:
                Constants.PURPLE_API_STAGING_BASE_URL
            case .production:
                Constants.PURPLE_API_PRODUCTION_BASE_URL
        }
    }

    func purple_landing_page_url() -> URL {
        switch self {
            case .local_test:
                Constants.PURPLE_LANDING_PAGE_LOCAL_TEST_URL
            case .staging:
                Constants.PURPLE_LANDING_PAGE_STAGING_URL
            case .production:
                Constants.PURPLE_LANDING_PAGE_PRODUCTION_URL
        }
    }

    func damus_website_url() -> URL {
        switch self {
            case .local_test:
                Constants.DAMUS_WEBSITE_LOCAL_TEST_URL
            case .staging:
                Constants.DAMUS_WEBSITE_STAGING_URL
            case .production:
                Constants.DAMUS_WEBSITE_PRODUCTION_URL
        }
    }

    init?(from string: String) {
        guard let initialized = Self.init(rawValue: string) else { return nil }
        self = initialized
    }

    func to_string() -> String {
        return self.rawValue
    }

    var id: String { self.rawValue }
}
