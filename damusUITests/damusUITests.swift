//
//  damusUITests.swift
//  damusUITests
//
//  Created by William Casarin on 2022-04-01.
//

import XCTest

class damusUITests: XCTestCase {
    
    var app: XCUIApplication!

    override func setUpWithError() throws {
        
        app = XCUIApplication()
        app.launchArguments.append("--disable-notifications")
        app.launch()

        continueAfterFailure = false
    }
    
    // Tests creating an account
    // Posting a message
    // Logging out
    
    func testCreateAccoutPostLogout() throws {
        let createAccountButton = app.buttons["Create Account"]
        wait(query: createAccountButton)
        createAccountButton.tap()
                
        let acceptButton = app.buttons["Accept"]
        wait(query: acceptButton)
        acceptButton.tap()
        
        let createButton = app.buttons["Create"]
        wait(query: createButton)
        createButton.tap()
        
        let savePubKeyView = app.buttons["save_pub_key_button"]
        wait(query: savePubKeyView)
        savePubKeyView.tap()
        
        let savePrivKeyView = app.buttons["save_priv_key_button"]
        wait(query: savePrivKeyView)
        savePrivKeyView.tap()
        
        let letsGoButton = app.buttons["Let's go!"]
        wait(query: letsGoButton)
        letsGoButton.tap()
        
        let floatingPostButton = app.buttons["post_button"]
        wait(query: floatingPostButton)
        floatingPostButton.tap()
        
        let postTextView = app.textViews["post_text_view"]
        wait(query: postTextView)
        postTextView.typeText("Hi from UI Tests!")
        
        let postButton = app.buttons["Post"]
        wait(query: postButton)
        postButton.tap()
        
        let profileDrawerButton = app.buttons["profile_drawer_button"]
        wait(query: profileDrawerButton)
        profileDrawerButton.tap()
        
        let signOutButton = app.buttons["Sign out"]
        wait(query: signOutButton)
        signOutButton.tap()
        
        let alert = app.alerts.firstMatch
        let logoutButton = alert.buttons["Logout"]
        wait(query: logoutButton)
        
        logoutButton.tap()
        
        wait(query: createAccountButton)
    }
    
    func wait(query: XCUIElement) {
        
        let predicate = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        wait(for: [expectation], timeout: 5)
    }
}
