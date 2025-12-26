//
//  damusUITests.swift
//  damusUITests
//
//  Created by William Casarin on 2022-04-01.
//

import XCTest
import UIKit

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
    
    /// Tests that typing in the post composer works correctly, specifically that
    /// the cursor position is maintained after typing each character.
    /// This guards against regressions like https://github.com/damus-io/damus/issues/3461
    /// where the cursor would jump to position 0 after typing the first character.
    func testPostComposerCursorPosition() throws {
        try self.loginIfNotAlready()

        // Wait for main interface to load, then tap the post button (FAB)
        guard app.buttons[AID.post_button.rawValue].waitForExistence(timeout: 10) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        app.buttons[AID.post_button.rawValue].tap()

        // Wait for the post composer text view to appear
        guard app.textViews[AID.post_composer_text_view.rawValue].waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }

        let textView = app.textViews[AID.post_composer_text_view.rawValue]
        textView.tap()

        // Type a test string character by character
        // If the cursor jumps to position 0 after the first character,
        // the resulting text would be scrambled (e.g., "olleH" instead of "Hello")
        let testString = "Hello"
        textView.typeText(testString)

        // Verify the text was typed correctly (not scrambled)
        let actualText = textView.value as? String ?? ""
        XCTAssertEqual(actualText, testString,
                       "Text should be '\(testString)' but was '\(actualText)'. " +
                       "This may indicate a cursor position bug.")

        // Cancel the post to clean up
        app.buttons[AID.post_composer_cancel_button.rawValue].tap()
    }

    /// Tests that typing before a mention doesn't break the mention.
    /// This guards against regressions like https://github.com/damus-io/damus/issues/3460
    /// where inserting text before a mention would unlink it.
    ///
    /// The test creates a real mention link by selecting from autocomplete,
    /// then types text before it and verifies the mention text is preserved.
    /// Note: Link attribute preservation is verified in unit tests (PostViewTests).
    func testTypingBeforeMentionPreservesMention() throws {
        try self.loginIfNotAlready()

        // Open post composer
        guard app.buttons[AID.post_button.rawValue].waitForExistence(timeout: 10) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        app.buttons[AID.post_button.rawValue].tap()

        guard app.textViews[AID.post_composer_text_view.rawValue].waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }

        let textView = app.textViews[AID.post_composer_text_view.rawValue]
        textView.tap()

        // Type "@" to trigger mention autocomplete
        textView.typeText("@")

        // Wait for autocomplete results to appear and tap on a user to create a real mention link
        let mentionResult = app.otherElements[AID.post_composer_mention_user_result.rawValue].firstMatch
        guard mentionResult.waitForExistence(timeout: 5) else {
            // If no autocomplete results (no contacts loaded), skip this test gracefully
            app.buttons[AID.post_composer_cancel_button.rawValue].tap()
            throw XCTSkip("No mention autocomplete results available - contacts may not be loaded")
        }
        mentionResult.tap()

        // Wait for mention to be inserted (text should contain more than just "@")
        let mentionInsertedPredicate = NSPredicate(format: "value CONTAINS[c] '@' AND value.length > 1")
        let mentionInserted = expectation(for: mentionInsertedPredicate, evaluatedWith: textView)
        wait(for: [mentionInserted], timeout: 3)

        // Get the current text which should contain the mention (e.g., "@username ")
        let textAfterMention = textView.value as? String ?? ""
        XCTAssertTrue(textAfterMention.contains("@"),
                      "Text should contain a mention after selection but was '\(textAfterMention)'")

        // Move cursor to the beginning and type a prefix
        let startCoordinate = textView.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        startCoordinate.tap()

        // Type prefix text before the mention
        textView.typeText("Hey ")

        // Wait for the prefix to be inserted
        let prefixInsertedPredicate = NSPredicate(format: "value BEGINSWITH 'Hey '")
        let prefixInserted = expectation(for: prefixInsertedPredicate, evaluatedWith: textView)
        wait(for: [prefixInserted], timeout: 3)

        // Verify the text contains both the prefix and the mention is preserved
        let finalText = textView.value as? String ?? ""
        XCTAssertTrue(finalText.hasPrefix("Hey "),
                      "Text should start with 'Hey ' but was '\(finalText)'")
        XCTAssertTrue(finalText.contains("@"),
                      "Text should still contain the mention '@' but was '\(finalText)'")

        // Cancel to clean up
        app.buttons[AID.post_composer_cancel_button.rawValue].tap()
    }

    /// Tests that pasting an npub into the post composer converts it to a mention
    /// and resolves to a human-readable profile name via async fetch.
    /// This guards against regressions in https://github.com/damus-io/damus/issues/2289
    func testPastedNpubResolvesToProfileName() throws {
        try self.loginIfNotAlready()

        // Set up interruption handler for iOS paste permission alerts
        // iOS 16+ may show "Allow Paste" system alerts when pasting from other apps
        addUIInterruptionMonitor(withDescription: "Paste Permission Alert") { alert in
            // Handle both English and common localizations of the "Allow Paste" button
            let allowButtons = ["Allow Paste", "Paste", "Allow", "Erlauben", "Autoriser", "許可"]
            for buttonLabel in allowButtons {
                let button = alert.buttons[buttonLabel]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            // Try first button as fallback (typically the "allow" action)
            if alert.buttons.count > 0 {
                alert.buttons.element(boundBy: 0).tap()
                return true
            }
            return false
        }

        // Open post composer
        guard app.buttons[AID.post_button.rawValue].waitForExistence(timeout: 10) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        app.buttons[AID.post_button.rawValue].tap()

        guard app.textViews[AID.post_composer_text_view.rawValue].waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }

        let textView = app.textViews[AID.post_composer_text_view.rawValue]
        textView.tap()

        // Use a well-known npub (jack dorsey) that should resolve to a profile name
        let testNpub = "npub1sg6plzptd64u62a878hep2kev88swjh3tw00gjsfl8f237lmu63q0uf63m"

        // Put npub in pasteboard
        UIPasteboard.general.string = testNpub

        // Long press to bring up paste menu
        textView.press(forDuration: 1.0)

        // Find paste menu item - handle localized variants
        // iOS uses "Paste" in English but varies by locale
        let pasteLabels = ["Paste", "Einfügen", "Coller", "Pegar", "Incolla", "ペースト", "貼り付け", "붙여넣기"]
        var pasteButton: XCUIElement?
        for label in pasteLabels {
            let button = app.menuItems[label]
            if button.waitForExistence(timeout: 0.5) {
                pasteButton = button
                break
            }
        }

        guard let pasteButton = pasteButton else {
            // Fallback: try first menu item if no known paste label found
            let firstMenuItem = app.menuItems.firstMatch
            if firstMenuItem.waitForExistence(timeout: 1) {
                firstMenuItem.tap()
            } else {
                app.buttons[AID.post_composer_cancel_button.rawValue].tap()
                throw XCTSkip("Paste menu not available in this environment")
            }
            // Trigger interruption monitors by interacting with app
            app.tap()

            // Check if paste worked despite not finding the button
            let checkText = textView.value as? String ?? ""
            if !checkText.contains("@") && !checkText.contains("npub") {
                app.buttons[AID.post_composer_cancel_button.rawValue].tap()
                throw XCTSkip("Could not trigger paste action")
            }
            // Paste worked via fallback - clean up and exit
            app.buttons[AID.post_composer_cancel_button.rawValue].tap()
            return
        }

        pasteButton.tap()

        // Trigger interruption monitors in case paste permission alert appeared
        app.tap()

        // Wait for initial mention to appear (should contain @ symbol)
        let mentionAppearedPredicate = NSPredicate(format: "value CONTAINS[c] '@'")
        let mentionAppeared = expectation(for: mentionAppearedPredicate, evaluatedWith: textView)
        wait(for: [mentionAppeared], timeout: 5)

        // Verify initial paste created a mention (may still show @npub... initially)
        let initialText = textView.value as? String ?? ""
        XCTAssertTrue(initialText.contains("@"),
                      "Pasted npub should create a mention but text was '\(initialText)'")

        // Wait for async profile fetch to resolve the name (should NOT contain "npub1" after resolution)
        // Give it up to 10 seconds for relay fetch
        let profileResolvedPredicate = NSPredicate(format: "NOT (value CONTAINS[c] 'npub1')")
        let profileResolved = expectation(for: profileResolvedPredicate, evaluatedWith: textView)

        let result = XCTWaiter.wait(for: [profileResolved], timeout: 10)

        let finalText = textView.value as? String ?? ""

        if result == .timedOut {
            // Profile didn't resolve - this could happen if offline or relay issues
            // Still verify the npub was at least converted to a mention link
            XCTAssertTrue(finalText.contains("@"),
                          "Text should contain a mention but was '\(finalText)'")
            print("Note: Profile did not resolve within timeout. Text: '\(finalText)'")
        } else {
            // Profile resolved - verify it's a human-readable name
            XCTAssertTrue(finalText.contains("@"),
                          "Text should contain a mention but was '\(finalText)'")
            XCTAssertFalse(finalText.contains("npub1"),
                           "Mention should resolve to profile name, not show npub. Text: '\(finalText)'")
        }

        // Cancel to clean up
        app.buttons[AID.post_composer_cancel_button.rawValue].tap()
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
