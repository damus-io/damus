//
//  Constants.swift
//  damus
//
//  Created by Sam DuBois on 12/18/22.
//

import Foundation

/// General app-wide constants
///
/// ## Implementation notes:
/// - Force unwrapping in this class is generally ok, because the contents are static, and so we can easily provide guarantees that they will not crash the app.
class Constants {
    //static let EXAMPLE_DEMOS: DamusState = .empty
    static let DAMUS_APP_GROUP_IDENTIFIER: String = "group.com.damus"
    static let MAIN_APP_BUNDLE_IDENTIFIER: String = "com.jb55.damus2"
    static let NOTIFICATION_EXTENSION_BUNDLE_IDENTIFIER: String = "com.jb55.damus2.DamusNotificationService"
    
    // MARK: Push notification server
    static let PUSH_NOTIFICATION_SERVER_PRODUCTION_BASE_URL: URL = URL(string: "https://notify.damus.io")!
    static let PUSH_NOTIFICATION_SERVER_STAGING_BASE_URL: URL = URL(string: "https://notify-staging.damus.io")!
    static let PUSH_NOTIFICATION_SERVER_TEST_BASE_URL: URL = URL(string: "http://localhost:8000")!
    
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
    
    // MARK: Damus Company Info
    static let SUPPORT_PUBKEY: Pubkey = Pubkey(hex: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681")!
    
    // MARK: General constants
    static let GIF_IMAGE_TYPE: String = "com.compuserve.gif"
}
