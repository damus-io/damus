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
    
    /*
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
            initialTextSuffix: nil,
            cursorIndex: 9,
            updateCursorPosition: { _ in return }
        ).environmentObject(tagModel)
        let hostView = UIHostingController(rootView: textEditorView)
        
        // Run snapshot check
        assertSnapshot(matching: hostView, as: .image(on: .iPhoneSe(.portrait)))
    }
     */

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
    
    func testMentionLinkEditorHandling_noWhitespaceAfterLink1_addsWhitespace() {
        var content: NSMutableAttributedString

        content = NSMutableAttributedString(string: "Hello @user ")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
        checkMentionLinkEditorHandling(content: content, replacementText: "up", replacementRange: NSRange(location: 11, length: 1), shouldBeAbleToChangeAutomatically: true, expectedNewCursorIndex: 13, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello @user up")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 11, effectiveRange: nil))
        })
    }
    
    func testMentionLinkEditorHandling_noWhitespaceAfterLink2_addsWhitespace() {
        var content: NSMutableAttributedString

        content = NSMutableAttributedString(string: "Hello @user test")
        content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
        checkMentionLinkEditorHandling(content: content, replacementText: "up", replacementRange: NSRange(location: 11, length: 1), shouldBeAbleToChangeAutomatically: true, expectedNewCursorIndex: 13, handleNewContent: { newManuallyEditedContent in
            XCTAssertEqual(newManuallyEditedContent.string, "Hello @user uptest")
            XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 11, effectiveRange: nil))
        })
    }
    
    func testMentionLinkEditorHandling_nonAlphanumericAfterLink_noWhitespaceAdded() {
        let nonAlphaNumerics = [" ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", ":", ";", "<", "=", ">", "?", "@", "[", "\\", "]", "^", "_", "`", "{", "|", "}", "~"]
        
        nonAlphaNumerics.forEach { testAddingStringAfterLink(str: $0)}
    }

    func testQuoteRepost() async {
        let post = await build_post(state: test_damus_state, post: .init(), action: .quoting(test_note), uploadedMedias: [], pubkeys: [])

        XCTAssertEqual(post.tags, [["q", test_note.id.hex(), "", jack_keypair.pubkey.hex()], ["p", jack_keypair.pubkey.hex()]])
    }

    func testBuildPostRecognizesStringsAsNpubs() async throws {
        // given
        let expectedLink = "nostr:\(test_pubkey.npub)"
        let content = NSMutableAttributedString(string: "@test", attributes: [
            NSAttributedString.Key.link: "damus:\(expectedLink)"
        ])

        // when
        let post = await build_post(
            state: test_damus_state,
            post: content,
            action: .posting(.user(test_pubkey)),
            uploadedMedias: [],
            pubkeys: []
        )

        // then
        XCTAssertEqual(post.content, expectedLink)
    }

    func testBuildPostRecognizesUrlsAsNpubs() async throws {
        // given
        guard let npubUrl = URL(string: "damus:nostr:\(test_pubkey.npub)") else {
            return XCTFail("Could not create URL")
        }
        let content = NSMutableAttributedString(string: "@test", attributes: [
            NSAttributedString.Key.link: npubUrl
        ])

        // when
        let post = await build_post(
            state: test_damus_state,
            post: content,
            action: .posting(.user(test_pubkey)),
            uploadedMedias: [],
            pubkeys: []
        )

        // then
        XCTAssertEqual(post.content, "nostr:\(test_pubkey.npub)")
    }

    // MARK: - Image URL Detection Tests

    /// Tests that the image URL regex detects common image extensions
    func testImageURLRegexDetectsCommonExtensions() {
        let testCases = [
            ("https://example.com/image.jpg", true),
            ("https://example.com/image.jpeg", true),
            ("https://example.com/image.png", true),
            ("https://example.com/image.gif", true),
            ("https://example.com/image.webp", true),
            ("https://example.com/image.svg", true),
            ("http://example.com/image.jpg", true),  // http also works
            ("https://example.com/image.JPG", true), // case insensitive
            ("https://example.com/image.PNG", true),
        ]

        let pattern = try! NSRegularExpression(
            pattern: #"https?://[^\s#]+\.(jpg|jpeg|png|gif|webp|svg)(\?[^\s]*)?"#,
            options: [.caseInsensitive]
        )

        for (url, shouldMatch) in testCases {
            let range = NSRange(location: 0, length: url.utf16.count)
            let matches = pattern.matches(in: url, options: [], range: range)
            XCTAssertEqual(!matches.isEmpty, shouldMatch, "URL '\(url)' should \(shouldMatch ? "" : "not ")match")
        }
    }

    /// Tests that image URLs with query parameters are detected
    func testImageURLRegexWithQueryParams() {
        let testCases = [
            "https://example.com/image.jpg?size=large",
            "https://example.com/image.png?width=100&height=100",
            "https://cdn.example.com/path/to/image.gif?v=123",
        ]

        let pattern = try! NSRegularExpression(
            pattern: #"https?://[^\s#]+\.(jpg|jpeg|png|gif|webp|svg)(\?[^\s]*)?"#,
            options: [.caseInsensitive]
        )

        for url in testCases {
            let range = NSRange(location: 0, length: url.utf16.count)
            let matches = pattern.matches(in: url, options: [], range: range)
            XCTAssertFalse(matches.isEmpty, "URL with query params '\(url)' should match")
        }
    }

    /// Tests that non-image URLs are not detected
    func testImageURLRegexDoesNotMatchNonImages() {
        let testCases = [
            "https://example.com/page.html",
            "https://example.com/document.pdf",
            "https://example.com/video.mp4",
            "https://example.com/archive.zip",
            "https://example.com/",
            "not a url at all",
            "image.jpg",  // no protocol
        ]

        let pattern = try! NSRegularExpression(
            pattern: #"https?://[^\s#]+\.(jpg|jpeg|png|gif|webp|svg)(\?[^\s]*)?"#,
            options: [.caseInsensitive]
        )

        for text in testCases {
            let range = NSRange(location: 0, length: text.utf16.count)
            let matches = pattern.matches(in: text, options: [], range: range)
            XCTAssertTrue(matches.isEmpty, "Non-image text '\(text)' should not match")
        }
    }

    /// Tests that URLs with fragment identifiers are not matched
    /// Fragment identifiers (#) are not sent to the server, so URLs like
    /// https://example.com/page#image.png won't actually return an image
    func testImageURLRegexDoesNotMatchFragmentURLs() {
        let testCases = [
            "https://en.wikipedia.org/wiki/Siberia#/media/File:Russia_vegetation.png",
            "https://example.com/page#image.jpg",
            "https://example.com/article#photo.png",
        ]

        let pattern = try! NSRegularExpression(
            pattern: #"https?://[^\s#]+\.(jpg|jpeg|png|gif|webp|svg)(\?[^\s]*)?"#,
            options: [.caseInsensitive]
        )

        for url in testCases {
            let range = NSRange(location: 0, length: url.utf16.count)
            let matches = pattern.matches(in: url, options: [], range: range)
            XCTAssertTrue(matches.isEmpty, "Fragment URL '\(url)' should not match")
        }
    }

    /// Tests that multiple image URLs in text are all detected
    func testImageURLRegexDetectsMultipleURLs() {
        let text = "Check out https://example.com/one.jpg and https://example.com/two.png "

        let pattern = try! NSRegularExpression(
            pattern: #"https?://[^\s#]+\.(jpg|jpeg|png|gif|webp|svg)(\?[^\s]*)?"#,
            options: [.caseInsensitive]
        )

        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = pattern.matches(in: text, options: [], range: range)

        XCTAssertEqual(matches.count, 2, "Should detect 2 image URLs")
    }

    /// Tests isSupportedImage function
    func testIsSupportedImage() {
        let supportedURLs = [
            URL(string: "https://example.com/image.jpg")!,
            URL(string: "https://example.com/image.jpeg")!,
            URL(string: "https://example.com/image.png")!,
            URL(string: "https://example.com/image.gif")!,
            URL(string: "https://example.com/image.webp")!,
            URL(string: "https://example.com/image.svg")!,
        ]

        let unsupportedURLs = [
            URL(string: "https://example.com/video.mp4")!,
            URL(string: "https://example.com/document.pdf")!,
            URL(string: "https://example.com/page.html")!,
        ]

        for url in supportedURLs {
            XCTAssertTrue(isSupportedImage(url: url), "\(url) should be supported")
        }

        for url in unsupportedURLs {
            XCTAssertFalse(isSupportedImage(url: url), "\(url) should not be supported")
        }
    }

    // MARK: - Image URL Extraction Behavior

    func testDetectAndExtractImageURLs_RemovesURLAndAddsMedia() {
        var view = PostView(action: .posting(.none), damus_state: test_damus_state)
        view.post = NSMutableAttributedString(string: "hello https://example.com/a.jpg ")
        view.uploadedMedias = []

        view.detectAndExtractImageURLs()

        XCTAssertFalse(view.post.string.contains("https://example.com/a.jpg"))
        XCTAssertEqual(view.uploadedMedias.count, 1)
        XCTAssertEqual(view.uploadedMedias.first?.uploadedURL.absoluteString, "https://example.com/a.jpg")
    }

    func testDetectAndExtractImageURLs_DoesNotAddDuplicateMediaButRemovesText() {
        let url = URL(string: "https://example.com/a.jpg")!
        var view = PostView(action: .posting(.none), damus_state: test_damus_state)
        view.post = NSMutableAttributedString(string: "https://example.com/a.jpg ")
        view.uploadedMedias = [UploadedMedia(localURL: url, uploadedURL: url, metadata: nil)]

        view.detectAndExtractImageURLs()

        XCTAssertFalse(view.post.string.contains("https://example.com/a.jpg"))
        XCTAssertEqual(view.uploadedMedias.count, 1)
    }

    func testDetectAndExtractImageURLs_MultipleURLsMaintainOrder() {
        let url1 = "https://example.com/one.jpg"
        let url2 = "https://example.com/two.png"
        var view = PostView(action: .posting(.none), damus_state: test_damus_state)
        view.post = NSMutableAttributedString(string: "x \(url1) y \(url2) ")
        view.uploadedMedias = []

        view.detectAndExtractImageURLs()

        XCTAssertFalse(view.post.string.contains(url1))
        XCTAssertFalse(view.post.string.contains(url2))
        XCTAssertEqual(view.uploadedMedias.map { $0.uploadedURL.absoluteString }, [url1, url2])
    }

    func testDetectAndExtractImageURLs_IgnoresWhenNoTrailingWhitespace() {
        var view = PostView(action: .posting(.none), damus_state: test_damus_state)
        view.post = NSMutableAttributedString(string: "https://example.com/a.jpg")
        view.uploadedMedias = []

        view.detectAndExtractImageURLs()

        XCTAssertEqual(view.post.string, "https://example.com/a.jpg")
        XCTAssertTrue(view.uploadedMedias.isEmpty)
    }

    func testDetectAndExtractImageURLs_RemovesTrailingWhitespace() {
        var view = PostView(action: .posting(.none), damus_state: test_damus_state)
        view.post = NSMutableAttributedString(string: "https://example.com/a.jpg  \n")
        view.uploadedMedias = []

        view.detectAndExtractImageURLs()

        // Only one trailing whitespace/newline is removed along with the URL
        XCTAssertEqual(view.post.string, " \n")
        XCTAssertEqual(view.uploadedMedias.count, 1)
    }

    func testAddImageURLAsMedia_AddsNewURL() {
        var view = PostView(action: .posting(.none), damus_state: test_damus_state)
        view.uploadedMedias = []

        let url = URL(string: "https://example.com/image.jpg")!
        view.addImageURLAsMedia(url)

        XCTAssertEqual(view.uploadedMedias.count, 1)
        XCTAssertEqual(view.uploadedMedias.first?.uploadedURL, url)
    }

    func testAddImageURLAsMedia_SkipsDuplicate() {
        let url = URL(string: "https://example.com/image.jpg")!
        var view = PostView(action: .posting(.none), damus_state: test_damus_state)
        view.uploadedMedias = [UploadedMedia(localURL: url, uploadedURL: url, metadata: nil)]

        view.addImageURLAsMedia(url)

        XCTAssertEqual(view.uploadedMedias.count, 1)
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
        }, initialTextSuffix: nil)
        let textView = UITextView()
        textView.attributedText = content

        XCTAssertEqual(coordinator.textView(textView, shouldChangeTextIn: replacementRange, replacementText: replacementText), shouldBeAbleToChangeAutomatically, "Expected shouldChangeTextIn to return \(shouldBeAbleToChangeAutomatically), but was \(!shouldBeAbleToChangeAutomatically)")
}

func testAddingStringAfterLink(str: String) {
    var content: NSMutableAttributedString

    content = NSMutableAttributedString(string: "Hello @user test")
    content.addAttribute(.link, value: "damus:1234", range: NSRange(location: 6, length: 5))
    checkMentionLinkEditorHandling(content: content, replacementText: str, replacementRange: NSRange(location: 11, length: 0), shouldBeAbleToChangeAutomatically: false, expectedNewCursorIndex: 12, handleNewContent: { newManuallyEditedContent in
        XCTAssertEqual(newManuallyEditedContent.string, "Hello @user" + str + " test")
        XCTAssertNil(newManuallyEditedContent.attribute(.link, at: 11, effectiveRange: nil))
    })
}


