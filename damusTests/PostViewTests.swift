//
//  PostViewTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-08-19.
//
import Foundation
import XCTest
import SnapshotTesting
import SwiftUI
@testable import damus
import SwiftUI

final class PostViewTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testTextWrapperViewWillWrapText() {
        // Setup test variables to be passed into the TextViewWrapper
        let tagModel: TagModel = TagModel()
        var textHeight: CGFloat? = nil
        let textHeightBinding: Binding<CGFloat?> = Binding(get: {
            return textHeight
        }, set: { newValue in
            textHeight = newValue
        })
        
        // Setup the test view
        let textEditorView = TextViewWrapper(
            attributedText: .constant(NSMutableAttributedString(string: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.")),
            textHeight: textHeightBinding,
            cursorIndex: 9,
            updateCursorPosition: { _ in return }
        ).environmentObject(tagModel)
        let hostView = UIHostingController(rootView: textEditorView)
        
        // Run snapshot check
        assertSnapshot(matching: hostView, as: .image(on: .iPhoneSe(.portrait)))
    }
    
    /// Based on https://github.com/damus-io/damus/issues/1375
    /// Tests whether the editor properly handles mention links after they have been added, to avoid manual editing of attributed links
    func testMentionLinkEditorHandling() throws {
        var content: NSMutableAttributedString

        // Test normal insertion
        checkMentionLinkEditorHandling(content: NSMutableAttributedString(string: "Hello"), replacementText: "@", replacementRange: NSRange(location: 0, length: 0), shouldBeAbleToChangeAutomatically: true)
        checkMentionLinkEditorHandling(content: NSMutableAttributedString(string: "Hello "), replacementText: "@", replacementRange: NSRange(location: 6, length: 0), shouldBeAbleToChangeAutomatically: true)
        checkMentionLinkEditorHandling(content: NSMutableAttributedString(string: "Helo "), replacementText: "l", replacementRange: NSRange(location: 3, length: 0), shouldBeAbleToChangeAutomatically: true)
        
        // Test normal backspacing
        checkMentionLinkEditorHandling(content: NSMutableAttributedString(string: "Hello"), replacementText: "", replacementRange: NSRange(location: 5, length: 1), shouldBeAbleToChangeAutomatically: true)
        checkMentionLinkEditorHandling(content: NSMutableAttributedString(string: "Hello "), replacementText: "", replacementRange: NSRange(location: 6, length: 1), shouldBeAbleToChangeAutomatically: true)
        checkMentionLinkEditorHandling(content: NSMutableAttributedString(string: "Helo "), replacementText: "", replacementRange: NSRange(location: 3, length: 1), shouldBeAbleToChangeAutomatically: true)

        // Test normal insertion after mention link
        content = NSMutableAttributedString(string: "Hello @user ")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
        checkMentionLinkEditorHandling(content: content, replacementText: "a", replacementRange: NSRange(location: 12, length: 0), shouldBeAbleToChangeAutomatically: true)

        // Test insertion right at the end of a mention link, at the end of the text
        content = NSMutableAttributedString(string: "Hello @user")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
        checkMentionLinkEditorHandling(content: content, replacementText: ",", replacementRange: NSRange(location: 11, length: 0), shouldBeAbleToChangeAutomatically: false, expectedNewCursorIndex: 12, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello @user,")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 11, effectiveRange: nil))
        })

        // Test insertion right at the end of a mention link, in the middle of the text
        content = NSMutableAttributedString(string: "Hello @user how are you?")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
        checkMentionLinkEditorHandling(content: content, replacementText: ",", replacementRange: NSRange(location: 11, length: 0), shouldBeAbleToChangeAutomatically: false, expectedNewCursorIndex: 12, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello @user, how are you?")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 11, effectiveRange: nil))
        })

        // Test insertion in the middle of a mention link to check if the link is removed
        content = NSMutableAttributedString(string: "Hello @user how are you?")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
        checkMentionLinkEditorHandling(content: content, replacementText: "a", replacementRange: NSRange(location: 8, length: 0), shouldBeAbleToChangeAutomatically: false, expectedNewCursorIndex: 9, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello @uaser how are you?")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 8, effectiveRange: nil))
        })

        // Test insertion in the middle of a mention link to check if the link is removed, at the end of the text
        content = NSMutableAttributedString(string: "Hello @user")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
        checkMentionLinkEditorHandling(content: content, replacementText: "a", replacementRange: NSRange(location: 8, length: 0), shouldBeAbleToChangeAutomatically: false, expectedNewCursorIndex: 9, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello @uaser")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 8, effectiveRange: nil))
        })

        // Test backspacing right at the end of a mention link, at the end of the text
        content = NSMutableAttributedString(string: "Hello @user")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
        checkMentionLinkEditorHandling(content: content, replacementText: "", replacementRange: NSRange(location: 10, length: 1), shouldBeAbleToChangeAutomatically: false, expectedNewCursorIndex: 10, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello @use")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 6, effectiveRange: nil))
        })

        // Test adding text right at the start of a mention link, to check that the link is removed
        content = NSMutableAttributedString(string: "Hello @user")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
        checkMentionLinkEditorHandling(content: content, replacementText: "a", replacementRange: NSRange(location: 6, length: 0), shouldBeAbleToChangeAutomatically: false, expectedNewCursorIndex: 7, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello a@user")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 7, effectiveRange: nil))
        })

        // Test that removing one link does not affect the other
        content = NSMutableAttributedString(string: "Hello @user1 @user2")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 6))
        content.addAttribute(.link, value: "damus:5678", range: NSRange(location: 13, length: 6))
        checkMentionLinkEditorHandling(content: content, replacementText: "", replacementRange: NSRange(location: 18, length: 1), shouldBeAbleToChangeAutomatically: false, expectedNewCursorIndex: 18, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello @user1 @user")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 13, effectiveRange: nil))
            XCTAssertNotNil(newManuallyEditedContent.attribute(.link, at: 6, effectiveRange: nil))
        })

        // Test that replacing a whole range intersecting with two links removes both links
        content = NSMutableAttributedString(string: "Hello @user1 @user2")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 6))
        content.addAttribute(.link, value: "damus:5678", range: NSRange(location: 13, length: 6))
        checkMentionLinkEditorHandling(content: content, replacementText: "a", replacementRange: NSRange(location: 10, length: 4), shouldBeAbleToChangeAutomatically: false, expectedNewCursorIndex: 11, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello @useauser2")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 6, effectiveRange: nil))
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 11, effectiveRange: nil))
        })

        // Test that replacing a whole range including two links removes both links naturally
        content = NSMutableAttributedString(string: "Hello @user1 @user2, how are you?")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 6))
        content.addAttribute(.link, value: "damus:5678", range: NSRange(location: 13, length: 6))
        checkMentionLinkEditorHandling(content: content, replacementText: "", replacementRange: NSRange(location: 5, length: 28), shouldBeAbleToChangeAutomatically: true)
        
    }
}

func checkMentionLinkEditorHandling(
    content: NSMutableAttributedString,
    replacementText: String,
    replacementRange: NSRange,
    shouldBeAbleToChangeAutomatically: Bool,
    expectedNewCursorIndex: Int? = nil,
    handleNewContent: ((NSMutableAttributedString) -> Void)? = nil) {
        let bindingContent: Binding<NSMutableAttributedString> = Binding(get: {
            return content
        }, set: { newValue in
            handleNewContent?(newValue)
        })
        let coordinator: TextViewWrapper.Coordinator = TextViewWrapper.Coordinator(attributedText: bindingContent, getFocusWordForMention: nil, updateCursorPosition: { newCursorIndex in
            if let expectedNewCursorIndex {
                XCTAssertEqual(newCursorIndex, expectedNewCursorIndex)
            }
        })
        let textView = UITextView()
        textView.attributedText = content

        XCTAssertEqual(coordinator.textView(textView, shouldChangeTextIn: replacementRange, replacementText: replacementText), shouldBeAbleToChangeAutomatically, "Expected shouldChangeTextIn to return \(shouldBeAbleToChangeAutomatically), but was \(!shouldBeAbleToChangeAutomatically)")
}



