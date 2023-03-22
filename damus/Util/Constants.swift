//
//  Constants.swift
//  damus
//
//  Created by Sam DuBois on 12/18/22.
//

import Foundation

class Constants {
    static let PURPLE_API_PRODUCTION_BASE_URL: URL = URL(string: "https://purple.damus.io")!
    static let PURPLE_API_TEST_BASE_URL: URL = URL(string: "http://localhost:8989")!
    static let DEVICE_TOKEN_RECEIVER_PRODUCTION_URL: URL = URL(string: "https://notify.damus.io:8000/user-info")!
    static let DEVICE_TOKEN_RECEIVER_TEST_URL: URL = URL(string: "http://localhost:8000/user-info")!
    static let EXAMPLE_DEMOS: DamusState = .empty
}
