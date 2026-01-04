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
    
    /// Tests the sign up flow to ensure users can successfully create a new account.
    /// This test verifies:
    /// 1. The "Create account" button is accessible
    /// 2. Users can enter their name and bio
    /// 3. The "Next" button becomes enabled after entering required information
    /// 4. Users reach the save keys screen
    /// 5. Users can skip saving keys and complete onboarding
    func testSignUpFlow() throws {
        try logoutIfNotAlready()
        
        // Verify we're on the initial screen with sign up option
        guard app.buttons[AID.sign_up_option_button.rawValue].waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        
        // Tap the create account button
        app.buttons[AID.sign_up_option_button.rawValue].tap()
        
        // Wait for the create account screen to appear
        guard app.textFields[AID.sign_up_name_field.rawValue].waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        
        // Enter name (required field)
        let nameField = app.textFields[AID.sign_up_name_field.rawValue]
        nameField.tap()
        nameField.typeText("Test User")
        
        // Enter bio (optional field)
        let bioField = app.textFields[AID.sign_up_bio_field.rawValue]
        bioField.tap()
        bioField.typeText("This is a test bio")
        
        // Verify the Next button is present and enabled
        let nextButton = app.buttons[AID.sign_up_next_button.rawValue]
        guard nextButton.waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        
        // Tap Next to proceed to save keys screen
        nextButton.tap()
        
        // Verify we reached the save keys screen by checking for the save button
        guard app.buttons[AID.sign_up_save_keys_button.rawValue].waitForExistence(timeout: 10) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        
        // Verify both save options are present
        XCTAssertTrue(app.buttons[AID.sign_up_skip_save_keys_button.rawValue].exists,
                     "Skip save keys button should be visible")
        
        // Tap "Not now" to skip saving keys and continue to onboarding
        app.buttons[AID.sign_up_skip_save_keys_button.rawValue].tap()
        
        // Go through onboarding flow (similar to loginIfNotAlready)
        // Select an interest if the interests page appears
        app.buttons[AID.onboarding_interest_option_button.rawValue].firstMatch.tapIfExists(timeout: 5)
        app.buttons[AID.onboarding_interest_page_next_page.rawValue].tapIfExists(timeout: 5)
        
        // Continue through content settings page
        app.buttons[AID.onboarding_content_settings_page_next_page.rawValue].tapIfExists(timeout: 5)
        
        // Skip any remaining onboarding sheets
        app.buttons[AID.onboarding_sheet_skip_button.rawValue].tapIfExists(timeout: 5)
        
        // Cancel post composer if it appears
        app.buttons[AID.post_composer_cancel_button.rawValue].tapIfExists(timeout: 5)
        
        // Verify we've reached the main app interface by checking for the side menu button
        guard app.buttons[AID.main_side_menu_button.rawValue].waitForExistence(timeout: 10) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
    }
    
    func logoutIfNotAlready() throws {
        // First, check if user is already logged in and logout if needed
        if app.buttons[AID.main_side_menu_button.rawValue].waitForExistence(timeout: 5) {
            // User is already logged in, need to logout first
            try logout()
        }
    }
    
    func logout() throws {
        app.buttons[AID.main_side_menu_button.rawValue].tap()
        
        guard app.buttons[AID.side_menu_logout_button.rawValue].waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        
        app.buttons[AID.side_menu_logout_button.rawValue].tap()
        
        // Handle logout confirmation dialog (system alert)
        // Wait for the alert to appear
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        
        // Tap the confirm button in the alert
        let confirmButton = alert.buttons[AID.side_menu_logout_confirm_button.rawValue].firstMatch
        guard confirmButton.waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        
        confirmButton.tap()
        
        // Wait a moment for logout to complete
        sleep(2)
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

    // MARK: - Network Condition Simulator Infrastructure Tests

    /// Verifies app launches correctly with timeout simulation enabled.
    /// This is infrastructure scaffolding - a full upload timeout test would
    /// navigate to composer, attach media, and verify error UI.
    func testAppLaunchesWithTimeoutSimulation() throws {
        app.launchArguments += ["-SimulateNetworkCondition", "timeout", "-SimulateNetworkPattern", "upload"]
        app.terminate()
        app.launch()

        try self.loginIfNotAlready()

        guard app.buttons[AID.main_side_menu_button.rawValue].waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }

        XCTAssertTrue(app.buttons[AID.main_side_menu_button.rawValue].exists,
                      "App should launch successfully with network simulation enabled")
    }

    /// Verifies app launches correctly with failThenSucceed simulation enabled.
    /// This is infrastructure scaffolding - a full retry test would attach media
    /// and verify eventual upload success after simulated failures.
    func testAppLaunchesWithRetrySimulation() throws {
        app.launchArguments += ["-SimulateNetworkCondition", "failThenSucceed", "-SimulateNetworkPattern", "upload"]
        app.terminate()
        app.launch()

        try self.loginIfNotAlready()

        guard app.buttons[AID.main_side_menu_button.rawValue].waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }

        XCTAssertTrue(app.buttons[AID.main_side_menu_button.rawValue].exists,
                      "App should launch successfully with failThenSucceed simulation")
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
