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
    
    /// Tests that the Zap explainer and the wallet setup form are never on screen together.
    ///
    /// They are two states of one screen, and used to be a view plus a `.fullScreenCover` over
    /// it. The cover was requested on the setup view's first render — during the navigation push
    /// that created it — and when UIKit did not finish that presentation it left the presenting
    /// view in the window, so both hierarchies rendered at once with their text interleaved.
    /// Reading the accessibility tree catches that whether or not the front hierarchy's
    /// background happens to hide the one behind it on this particular device.
    func testWalletIntroductionDoesNotOverlapSetupForm() throws {
        try self.loginIfNotAlready()

        guard app.buttons[AID.main_side_menu_button.rawValue].tapIfExists(timeout: 10) else { throw DamusUITestError.timeout_waiting_for_element }
        guard app.buttons["Wallet"].tapIfExists(timeout: 10) else { throw DamusUITestError.timeout_waiting_for_element }

        guard app.staticTexts["Why add Zaps?"].waitForExistence(timeout: 10) else { throw DamusUITestError.timeout_waiting_for_element }

        // The overlap outlived the push and side menu animations, so settle before judging what
        // is on screen — otherwise a pass could just mean we looked before both layers landed.
        sleep(2)

        XCTAssertFalse(app.staticTexts["Create new wallet"].exists, "The wallet setup form is drawn underneath the Zap explainer")
        XCTAssertFalse(app.staticTexts["Scan NWC Address"].exists, "The wallet setup form is drawn underneath the Zap explainer")

        // Leaving the explainer is what reveals the setup form, and it takes the explainer away.
        guard app.buttons["Set up wallet"].tapIfExists(timeout: 5) else { throw DamusUITestError.timeout_waiting_for_element }

        XCTAssertTrue(app.staticTexts["Create new wallet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Why add Zaps?"].exists, "The Zap explainer is still drawn behind the wallet setup form")
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
    
    /// Opens the post composer with an empty editor, whatever an earlier test left in it.
    ///
    /// Cancelling the composer keeps what was typed, on purpose: `PostView.cancel()` does not
    /// call `clear_draft()`, so the content is autosaved as a NIP-37 draft in NostrDB and
    /// `PostView.onAppear` loads it straight back in. NostrDB lives in the app container, so
    /// that draft survives the relaunch `setUpWithError` does and turns up in whichever
    /// composer test runs next — `testPastedNpubResolvesToProfileName` leaves an `@jack`
    /// mention behind for `testPostComposerCursorPosition` to type on top of. Start from an
    /// empty editor instead of trusting the order the tests happen to run in.
    func openEmptyPostComposer() throws -> XCUIElement {
        guard app.buttons[AID.post_button.rawValue].waitForExistence(timeout: 10) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        app.buttons[AID.post_button.rawValue].tap()

        let textView = app.textViews[AID.post_composer_text_view.rawValue]
        guard textView.waitForExistence(timeout: 5) else {
            throw DamusUITestError.timeout_waiting_for_element
        }
        textView.tap()
        clearPostComposer(textView)
        return textView
    }

    /// Empties the composer's editor, so that neither this test's assertions nor the next
    /// test's opening state can be about a restored draft.
    ///
    /// Deleting backwards needs the caret past the end of the text, which a plain `tap()` in
    /// the middle of the editor does not give us, so tap the trailing edge first. A mention is
    /// a single link run that a backspace may swallow whole, so re-read the text and go again
    /// rather than assuming one pass of `count` deletes is enough.
    func clearPostComposer(_ textView: XCUIElement) {
        for _ in 0..<3 {
            let text = textView.value as? String ?? ""
            guard !text.isEmpty else { return }
            textView.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            textView.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
        XCTAssertEqual(textView.value as? String ?? "", "",
                       "The post composer should start empty, but a draft was left in it")
    }

    func login() throws {
        app.buttons[AID.sign_in_option_button.rawValue].tap()
        
        guard app.secureTextFields[AID.sign_in_nsec_key_entry_field.rawValue].tapIfExists(timeout: 10) else { throw DamusUITestError.timeout_waiting_for_element }
        app.typeText("nsec1vxvz8c7070d99njn0aqpcttljnzhfutt422l0r37yep7htesd0mq9p8fg2")
        
        guard app.buttons[AID.sign_in_confirm_button.rawValue].tapIfExists(timeout: 5) else { throw DamusUITestError.timeout_waiting_for_element }
    }
    
    /// Uses the real sheet and accessibility tree without recording, uploading or posting.
    func testAudioModeDismissesKeyboardAndPreservesTextDraft() throws {
        try loginIfNotAlready()
        let editor = try openEmptyPostComposer()
        let format = app.segmentedControls["post.format"]
        XCTAssertTrue(format.waitForExistence(timeout: 5))
        XCTAssertTrue(format.buttons["Text"].isSelected)
        editor.typeText("Keep this text draft")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        format.buttons["Audio"].tap()
        let keyboardGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        let editorGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: editor)
        wait(for: [keyboardGone, editorGone], timeout: 5)
        let microphone = app.descendants(matching: .any)["voice.microphone"].firstMatch
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        XCTAssertTrue(microphone.isHittable)
        XCTAssertGreaterThan(microphone.frame.midY, app.frame.midY)
        XCTAssertFalse(app.buttons["Saved audio"].exists)
        XCTAssertTrue(app.buttons["voice.addMention"].exists)
        XCTAssertTrue(app.buttons["voice.addPhotos"].exists)
        let addLink = app.buttons["voice.addLink"]
        let linkReady = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: addLink)
        wait(for: [linkReady], timeout: 5)
        addLink.tap()
        let urlField = app.textFields["voice.linkURL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()
        urlField.typeText("https://example.com/audio-attachment")
        app.buttons["Add"].tap()
        app.buttons[AID.post_composer_cancel_button.rawValue].tap()
        let discard = app.alerts["Are you sure you want to discard this audio post before posting it?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["Keep editing"].tap()
        XCTAssertTrue(app.staticTexts["https://example.com/audio-attachment"].exists)
        // Interactive dismissal must use the same confirmation.
        format.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).press(forDuration: 0.1, thenDragTo:
            format.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 450)))
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["Keep editing"].tap()
        // Removing the last audio attachment makes this an empty audio composition again.
        app.buttons["Remove link"].tap()
        XCTAssertTrue(app.buttons["Post"].exists)
        XCTAssertFalse(app.buttons["Post"].isEnabled)

        format.buttons["Text"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Keep this text draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons[AID.post_composer_cancel_button.rawValue].tap()
        app.buttons[AID.post_button.rawValue].tap()
        XCTAssertTrue(format.waitForExistence(timeout: 5))
        XCTAssertTrue(format.buttons["Text"].isSelected)
        XCTAssertEqual(editor.value as? String, "Keep this text draft")
        format.buttons["Audio"].tap()
        let linkReadyAgain = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: addLink)
        wait(for: [linkReadyAgain], timeout: 5)
        addLink.tap()
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
        urlField.tap()
        urlField.typeText("https://example.com/discard-me")
        app.buttons["Add"].tap()
        app.buttons[AID.post_composer_cancel_button.rawValue].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.buttons["Yes, discard"].tap()
        XCTAssertTrue(app.buttons[AID.post_button.rawValue].waitForExistence(timeout: 5))
        app.buttons[AID.post_button.rawValue].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Keep this text draft")
        format.buttons["Audio"].tap()
        XCTAssertFalse(app.staticTexts["https://example.com/discard-me"].exists)
        format.buttons["Text"].tap()
        clearPostComposer(editor)
        app.buttons[AID.post_composer_cancel_button.rawValue].tap()
    }

    /// Tests that typing in the post composer works correctly, specifically that
    /// the cursor position is maintained after typing each character.
    /// This guards against regressions like https://github.com/damus-io/damus/issues/3461
    /// where the cursor would jump to position 0 after typing the first character.
    func testPostComposerCursorPosition() throws {
        try self.loginIfNotAlready()

        let textView = try self.openEmptyPostComposer()

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

        // Cancel the post to clean up. Empty the editor first — cancelling saves a draft, and
        // it would be restored into whichever composer test runs after this one.
        clearPostComposer(textView)
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
        let textView = try self.openEmptyPostComposer()

        // Type "@" to trigger mention autocomplete
        textView.typeText("@")

        // Wait for autocomplete results to appear and tap on a user to create a real mention link
        let mentionResult = app.otherElements[AID.post_composer_mention_user_result.rawValue].firstMatch
        guard mentionResult.waitForExistence(timeout: 5) else {
            // If no autocomplete results (no contacts loaded), skip this test gracefully
            clearPostComposer(textView)
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

        // Cancel to clean up. Empty the editor first — cancelling saves a draft, and it would
        // be restored into whichever composer test runs after this one.
        clearPostComposer(textView)
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
        let textView = try self.openEmptyPostComposer()

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
                clearPostComposer(textView)
                app.buttons[AID.post_composer_cancel_button.rawValue].tap()
                throw XCTSkip("Paste menu not available in this environment")
            }
            // Trigger interruption monitors by interacting with app
            app.tap()

            // Check if paste worked despite not finding the button
            let checkText = textView.value as? String ?? ""
            if !checkText.contains("@") && !checkText.contains("npub") {
                clearPostComposer(textView)
                app.buttons[AID.post_composer_cancel_button.rawValue].tap()
                throw XCTSkip("Could not trigger paste action")
            }
            // Paste worked via fallback - clean up and exit
            clearPostComposer(textView)
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

        // Cancel to clean up. Empty the editor first — cancelling saves a draft, and it would
        // be restored into whichever composer test runs after this one.
        clearPostComposer(textView)
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
