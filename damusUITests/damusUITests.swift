//
//  damusUITests.swift
//  damusUITests
//
//  Created by William Casarin on 2022-04-01.
//

import XCTest

class damusUITests: XCTestCase {
    var app = XCUIApplication()
    typealias AID = AppAccessibilityIdentifiers

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        self.app = XCUIApplication()

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
        
        // Set app language to English
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launchArguments += ["-AppleLocale", "en_US"]
        
        // Force portrait orientation
        XCUIDevice.shared.orientation = .portrait
        
        // Optional: Reset the device's orientation before each test
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }
        
        app.launch()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Tests if banner edit button is clickable.
    /// Note: This is able to detect if the button is obscured by an invisible overlaying object.
    /// See https://github.com/damus-io/damus/issues/2636 for the kind of issue this guards against.
    func testEditBannerImage() throws {
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        try self.loginIfNotAlready()
        
        guard app.buttons[AID.main_side_menu_button.rawValue].tapIfExists(timeout: 5) else { throw DamusUITestError.timeout_waiting_for_element }
        guard app.buttons[AID.side_menu_profile_button.rawValue].tapIfExists(timeout: 5) else { throw DamusUITestError.timeout_waiting_for_element }
        guard app.buttons[AID.own_profile_edit_button.rawValue].tapIfExists(timeout: 5) else { throw DamusUITestError.timeout_waiting_for_element }
        
        guard app.buttons[AID.own_profile_banner_image_edit_button.rawValue].waitForExistence(timeout: 5) else { throw DamusUITestError.timeout_waiting_for_element }
        let bannerEditButtonCoordinates = app.buttons[AID.own_profile_banner_image_edit_button.rawValue].coordinate(withNormalizedOffset: CGVector.zero).withOffset(CGVector(dx: 15, dy: 15))
        bannerEditButtonCoordinates.tap()
        
        guard app.buttons[AID.own_profile_banner_image_edit_from_url.rawValue].waitForExistence(timeout: 5) else { throw DamusUITestError.timeout_waiting_for_element }
    }
    
    func loginIfNotAlready() throws {
        if app.buttons[AID.sign_in_option_button.rawValue].waitForExistence(timeout: 5) {
            try self.login()
        }

        app.buttons[AID.onboarding_interest_option_button.rawValue].firstMatch.tapIfExists(timeout: 5)
        app.buttons[AID.onboarding_interest_page_next_page.rawValue].tapIfExists(timeout: 5)
        app.buttons[AID.onboarding_content_settings_page_next_page.rawValue].tapIfExists(timeout: 5)
        app.buttons[AID.onboarding_sheet_skip_button.rawValue].tapIfExists(timeout: 5)
        app.buttons[AID.post_composer_cancel_button.rawValue].tapIfExists(timeout: 5)
    }
    
    func login() throws {
        app.buttons[AID.sign_in_option_button.rawValue].tap()
        
        guard app.secureTextFields[AID.sign_in_nsec_key_entry_field.rawValue].tapIfExists(timeout: 10) else { throw DamusUITestError.timeout_waiting_for_element }
        app.typeText("nsec1vxvz8c7070d99njn0aqpcttljnzhfutt422l0r37yep7htesd0mq9p8fg2")
        
        guard app.buttons[AID.sign_in_confirm_button.rawValue].tapIfExists(timeout: 5) else { throw DamusUITestError.timeout_waiting_for_element }
    }
    
    enum DamusUITestError: Error {
        case timeout_waiting_for_element
    }
}

extension XCUIElement {
    @discardableResult
    func tapIfExists(timeout: TimeInterval) -> Bool {
        if self.waitForExistence(timeout: timeout) {
            self.tap()
            return true
        }
        return false
    }
}
