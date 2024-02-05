//
//  Constants.swift
//  damus
//
//  Created by Sam DuBois on 12/18/22.
//

import Foundation

class Constants {
    //static let EXAMPLE_DEMOS: DamusState = .empty
    static let DAMUS_APP_GROUP_IDENTIFIER: String = "group.com.damus"
    static let DEVICE_TOKEN_RECEIVER_PRODUCTION_URL: URL = URL(string: "https://notify.damus.io:8000/user-info")!
    static let DEVICE_TOKEN_RECEIVER_TEST_URL: URL = URL(string: "http://localhost:8000/user-info")!
    static let MAIN_APP_BUNDLE_IDENTIFIER: String = "com.jb55.damus2"
    static let NOTIFICATION_EXTENSION_BUNDLE_IDENTIFIER: String = "com.jb55.damus2.DamusNotificationService"
    
    // MARK: Purple
    // API
    static let PURPLE_API_LOCAL_TEST_BASE_URL: URL = URL(string: "http://localhost:8989")!
    static let PURPLE_API_STAGING_BASE_URL: URL = URL(string: "https://api-staging.damus.io")!
    static let PURPLE_API_PRODUCTION_BASE_URL: URL = URL(string: "https://api.damus.io")!
    // Purple landing page
    static let PURPLE_LANDING_PAGE_LOCAL_TEST_URL: URL = URL(string: "http://localhost:3000/purple")!
    static let PURPLE_LANDING_PAGE_STAGING_URL: URL = URL(string: "https://staging.damus.io/purple")!
    static let PURPLE_LANDING_PAGE_PRODUCTION_URL: URL = URL(string: "https://damus.io/purple")!
    // Website
    static let DAMUS_WEBSITE_LOCAL_TEST_URL: URL = URL(string: "http://localhost:3000")!
    static let DAMUS_WEBSITE_STAGING_URL: URL = URL(string: "https://staging.damus.io")!
    static let DAMUS_WEBSITE_PRODUCTION_URL: URL = URL(string: "https://damus.io")!
}
