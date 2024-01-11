//
//  Constants.swift
//  damus
//
//  Created by Sam DuBois on 12/18/22.
//

import Foundation

class Constants {
    //static let EXAMPLE_DEMOS: DamusState = .empty
    static let VSTACK_LIMIT: Int = 30
    static let VSTACK_LIMIT_THRESHOLD: CGFloat = 900.0
    static let VSTACK_LIMIT_EV_THRESHOLD: CGFloat = 1.2

    static let DAMUS_APP_GROUP_IDENTIFIER: String = "group.com.damus"
    static let DEVICE_TOKEN_RECEIVER_PRODUCTION_URL: URL = URL(string: "https://notify.damus.io:8000/user-info")!
    static let DEVICE_TOKEN_RECEIVER_TEST_URL: URL = URL(string: "http://localhost:8000/user-info")!
    static let MAIN_APP_BUNDLE_IDENTIFIER: String = "com.jb55.damus2"
    static let NOTIFICATION_EXTENSION_BUNDLE_IDENTIFIER: String = "com.jb55.damus2.DamusNotificationService"
    static let PURPLE_API_PRODUCTION_BASE_URL: URL = URL(string: "https://purple.damus.io")!
    static let PURPLE_API_TEST_BASE_URL: URL = URL(string: "http://127.0.0.1:8989")!
}
