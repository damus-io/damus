//
//  SensitiveDataScrubbingTests.swift
//  damus
//

import XCTest
import Sentry
@testable import damus

final class SensitiveDataScrubbingTests: XCTestCase {
    
    // MARK: - Test String Scrubbing
    
    func testScrubNsecPrivateKey() {
        let event = Event()
        event.message = SentryMessage(formatted: "User logged in with nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NSEC]"))
        XCTAssertFalse(message.contains("nsec1qqqq"))
    }
    
    func testScrubNpubPublicKey() {
        let event = Event()
        event.message = SentryMessage(formatted: "Profile: npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NPUB]"))
        XCTAssertFalse(message.contains("npub1abc123"))
    }
    
    func testScrubNoteId() {
        let event = Event()
        event.message = SentryMessage(formatted: "Viewing note note1xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz7")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NOTE]"))
        XCTAssertFalse(message.contains("note1xyz789"))
    }
    
    func testScrubNevent() {
        let event = Event()
        event.message = SentryMessage(formatted: "Event reference: nevent1qqsxyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NEVENT]"))
        XCTAssertFalse(message.contains("nevent1qqsxyz"))
    }
    
    func testScrubNprofile() {
        let event = Event()
        event.message = SentryMessage(formatted: "Profile link: nprofile1qqsxyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NPROFILE]"))
        XCTAssertFalse(message.contains("nprofile1qqsxyz"))
    }
    
    func testScrubNaddr() {
        let event = Event()
        event.message = SentryMessage(formatted: "Address: naddr1qqsxyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NADDR]"))
        XCTAssertFalse(message.contains("naddr1qqsxyz"))
    }
    
    func testScrubNrelay() {
        let event = Event()
        event.message = SentryMessage(formatted: "Relay: nrelay1qqsxyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NRELAY]"))
        XCTAssertFalse(message.contains("nrelay1qqsxyz"))
    }
    
    func testScrubShortNrelay() {
        let event = Event()
        event.message = SentryMessage(formatted: "Relay: nrelay1abc123")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NRELAY]"))
        XCTAssertFalse(message.contains("nrelay1abc123"))
    }
    
    func testScrubHexKey() {
        let event = Event()
        event.message = SentryMessage(formatted: "Key: 3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_HEX]"))
        XCTAssertFalse(message.contains("3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"))
    }
    
    func testScrubEmailAddress() {
        let event = Event()
        event.message = SentryMessage(formatted: "Contact user@example.com for support")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_EMAIL]"))
        XCTAssertFalse(message.contains("user@example.com"))
    }
    
    func testScrubMultipleSensitivePatterns() {
        let event = Event()
        event.message = SentryMessage(formatted: "User nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq with npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123 and nevent1qqsxyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789 emailed test@test.com")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NSEC]"))
        XCTAssertTrue(message.contains("[REDACTED_NPUB]"))
        XCTAssertTrue(message.contains("[REDACTED_NEVENT]"))
        XCTAssertTrue(message.contains("[REDACTED_EMAIL]"))
        XCTAssertFalse(message.contains("nsec1qqqq"))
        XCTAssertFalse(message.contains("npub1abc123"))
        XCTAssertFalse(message.contains("nevent1qqsxyz"))
        XCTAssertFalse(message.contains("test@test.com"))
    }
    
    // MARK: - Test Exception Scrubbing
    
    func testScrubExceptionValue() {
        let event = Event()
        
        let sentryException = Exception(value: "Error: npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123", type: "Error")
        event.exceptions = [sentryException]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.exceptions)
        let exceptionValue = scrubbedEvent?.exceptions?.first?.value ?? ""
        XCTAssertTrue(exceptionValue.contains("[REDACTED_NPUB]"))
        XCTAssertFalse(exceptionValue.contains("npub1abc123"))
    }
    
    func testScrubExceptionMechanismDescription() {
        let event = Event()
        let sentryException = Exception(value: "Error", type: "Error")
        let mechanism = Mechanism(type: "generic")
        mechanism.desc = "Failure for nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
        sentryException.mechanism = mechanism
        event.exceptions = [sentryException]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        let mechanismDescription = scrubbedEvent?.exceptions?.first?.mechanism?.desc ?? ""
        XCTAssertTrue(mechanismDescription.contains("[REDACTED_NSEC]"))
        XCTAssertFalse(mechanismDescription.contains("nsec1qqqq"))
    }
    
    // MARK: - Test Context Scrubbing
    
    func testScrubContextData() {
        let event = Event()
        event.context = [
            "nostr": [
                "pubkey": "npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123",
                "email": "context@example.com",
                "nested": [
                    "private_key": "nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
                    "hex": "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
                ]
            ]
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        guard let nostrContext = scrubbedEvent?.context?["nostr"] else {
            XCTFail("Expected nostr context")
            return
        }
        
        XCTAssertEqual(nostrContext["pubkey"] as? String, "[REDACTED_NPUB]")
        XCTAssertEqual(nostrContext["email"] as? String, "[REDACTED_EMAIL]")
        
        guard let nested = nostrContext["nested"] as? [String: Any] else {
            XCTFail("Expected nested context")
            return
        }
        
        XCTAssertEqual(nested["private_key"] as? String, "[REDACTED_NSEC]")
        XCTAssertEqual(nested["hex"] as? String, "[REDACTED_HEX]")
    }
    
    // MARK: - Test Tag Scrubbing
    
    func testScrubTags() {
        let event = Event()
        event.tags = [
            "user_id": "npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123",
            "key": "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.tags)
        let userId = scrubbedEvent?.tags?["user_id"] ?? ""
        let key = scrubbedEvent?.tags?["key"] ?? ""
        XCTAssertTrue(userId.contains("[REDACTED_NPUB]"))
        XCTAssertTrue(key.contains("[REDACTED_HEX]"))
        XCTAssertFalse(userId.contains("npub1abc123"))
        XCTAssertFalse(key.contains("3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"))
    }
    
    // MARK: - Test User Data Scrubbing
    
    func testScrubUserEmail() {
        let event = Event()
        let user = User()
        user.email = "sensitive@example.com"
        user.userId = "npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123"
        user.username = "user@domain.com"
        event.user = user
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.user)
        XCTAssertTrue(scrubbedEvent?.user?.email?.contains("[REDACTED_EMAIL]") ?? false)
        XCTAssertTrue(scrubbedEvent?.user?.userId?.contains("[REDACTED_NPUB]") ?? false)
        XCTAssertTrue(scrubbedEvent?.user?.username?.contains("[REDACTED_EMAIL]") ?? false)
    }
    
    func testScrubUserData() {
        let event = Event()
        let user = User()
        user.data = [
            "private_key": "nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
            "email": "test@example.com"
        ]
        event.user = user
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.user?.data)
        let privateKey = scrubbedEvent?.user?.data?["private_key"] as? String
        let email = scrubbedEvent?.user?.data?["email"] as? String
        XCTAssertTrue(privateKey?.contains("[REDACTED_NSEC]") ?? false)
        XCTAssertTrue(email?.contains("[REDACTED_EMAIL]") ?? false)
    }
    
    // MARK: - Test Breadcrumb Scrubbing
    
    func testScrubBreadcrumbMessage() {
        let breadcrumb = Breadcrumb()
        breadcrumb.message = "User logged in with nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
        
        let scrubbedBreadcrumb = DamusSentry.scrubSensitiveDataInBreadcrumb(breadcrumb)
        
        XCTAssertNotNil(scrubbedBreadcrumb?.message)
        XCTAssertTrue(scrubbedBreadcrumb?.message?.contains("[REDACTED_NSEC]") ?? false)
        XCTAssertFalse(scrubbedBreadcrumb?.message?.contains("nsec1") ?? true)
    }
    
    func testScrubBreadcrumbData() {
        let breadcrumb = Breadcrumb()
        breadcrumb.data = [
            "pubkey": "npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123",
            "email": "user@example.com"
        ]
        
        let scrubbedBreadcrumb = DamusSentry.scrubSensitiveDataInBreadcrumb(breadcrumb)
        
        XCTAssertNotNil(scrubbedBreadcrumb?.data)
        let pubkey = scrubbedBreadcrumb?.data?["pubkey"] as? String
        let email = scrubbedBreadcrumb?.data?["email"] as? String
        XCTAssertTrue(pubkey?.contains("[REDACTED_NPUB]") ?? false)
        XCTAssertTrue(email?.contains("[REDACTED_EMAIL]") ?? false)
    }
    
    func testScrubBreadcrumbShortNrelay() {
        let breadcrumb = Breadcrumb()
        breadcrumb.message = "Relay: nrelay1abc123"
        
        let scrubbedBreadcrumb = DamusSentry.scrubSensitiveDataInBreadcrumb(breadcrumb)
        
        XCTAssertNotNil(scrubbedBreadcrumb?.message)
        XCTAssertTrue(scrubbedBreadcrumb?.message?.contains("[REDACTED_NRELAY]") ?? false)
        XCTAssertFalse(scrubbedBreadcrumb?.message?.contains("nrelay1abc123") ?? true)
    }
    
    // MARK: - Test Nested Dictionary Scrubbing
    
    func testScrubNestedDictionary() {
        let event = Event()
        event.extra = [
            "level1": [
                "level2": [
                    "key": "nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
                    "email": "nested@example.com"
                ]
            ]
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.extra)
        if let level1 = scrubbedEvent?.extra?["level1"] as? [String: Any],
           let level2 = level1["level2"] as? [String: Any] {
            let key = level2["key"] as? String
            let email = level2["email"] as? String
            XCTAssertTrue(key?.contains("[REDACTED_NSEC]") ?? false)
            XCTAssertTrue(email?.contains("[REDACTED_EMAIL]") ?? false)
        } else {
            XCTFail("Nested dictionary not properly structured")
        }
    }
    
    // MARK: - Test Array Scrubbing
    
    func testScrubArrayOfStrings() {
        let event = Event()
        event.extra = [
            "keys": [
                "nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
                "npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123",
                "user@example.com"
            ]
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.extra)
        if let keys = scrubbedEvent?.extra?["keys"] as? [String] {
            XCTAssertTrue(keys[0].contains("[REDACTED_NSEC]"))
            XCTAssertTrue(keys[1].contains("[REDACTED_NPUB]"))
            XCTAssertTrue(keys[2].contains("[REDACTED_EMAIL]"))
        } else {
            XCTFail("Array not properly scrubbed")
        }
    }
    
    // MARK: - Test Edge Cases
    
    func testDoesNotScrubNonSensitiveData() {
        let event = Event()
        event.message = SentryMessage(formatted: "This is a normal message with no sensitive data")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        XCTAssertEqual(scrubbedEvent?.message?.formatted, "This is a normal message with no sensitive data")
    }
    
    func testDoesNotScrubShortHexStrings() {
        let event = Event()
        event.message = SentryMessage(formatted: "Color: #FF5733 is nice")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        // Should not scrub short hex strings
        XCTAssertTrue(message.contains("FF5733"))
    }
    
    func testScrubIncompleteEmailPattern() {
        let event = Event()
        event.message = SentryMessage(formatted: "Contact: user@example.io")
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        // This should be scrubbed as it matches the email pattern
        XCTAssertTrue(message.contains("[REDACTED_EMAIL]"))
        XCTAssertFalse(message.contains("user@example.io"))
    }
    
    func testReturnsEventWhenNoSensitiveData() {
        let event = Event()
        event.message = SentryMessage(formatted: "Normal log message")
        event.tags = ["environment": "production"]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent)
        XCTAssertEqual(scrubbedEvent?.message?.formatted, "Normal log message")
        XCTAssertEqual(scrubbedEvent?.tags?["environment"], "production")
    }
    
    // MARK: - Test containsSensitiveDataInDictionary
    
    func testContainsSensitiveDataInDictionaryDetectsSensitiveString() {
        // Test via event extra which internally uses containsSensitiveDataInDictionary
        let event = Event()
        event.extra = [
            "user_key": "npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123",
            "safe_data": "normal value"
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.extra)
        if let userKey = scrubbedEvent?.extra?["user_key"] as? String {
            XCTAssertTrue(userKey.contains("[REDACTED_NPUB]"))
        }
    }
    
    func testContainsSensitiveDataInDictionaryNestedDictionary() {
        let event = Event()
        event.extra = [
            "level1": [
                "level2": [
                    "secret": "nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
                ]
            ]
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.extra)
        if let level1 = scrubbedEvent?.extra?["level1"] as? [String: Any],
           let level2 = level1["level2"] as? [String: Any],
           let secret = level2["secret"] as? String {
            XCTAssertTrue(secret.contains("[REDACTED_NSEC]"))
        } else {
            XCTFail("Nested dictionary should be scrubbed")
        }
    }
    
    func testContainsSensitiveDataInDictionaryWithArray() {
        let event = Event()
        event.extra = [
            "items": [
                "safe_value",
                "user@example.com",
                "another_safe_value"
            ]
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.extra)
        if let items = scrubbedEvent?.extra?["items"] as? [String] {
            XCTAssertEqual(items[0], "safe_value")
            XCTAssertTrue(items[1].contains("[REDACTED_EMAIL]"))
            XCTAssertEqual(items[2], "another_safe_value")
        } else {
            XCTFail("Array should be scrubbed")
        }
    }
    
    // MARK: - Test containsSensitiveDataInArray
    
    func testContainsSensitiveDataInArrayDetectsSensitiveString() {
        let event = Event()
        event.extra = [
            "keys": [
                "nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
                "clean_value"
            ]
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.extra)
        if let keys = scrubbedEvent?.extra?["keys"] as? [String] {
            XCTAssertTrue(keys[0].contains("[REDACTED_NSEC]"))
            XCTAssertEqual(keys[1], "clean_value")
        } else {
            XCTFail("Array with sensitive data should be scrubbed")
        }
    }
    
    func testContainsSensitiveDataInArrayNestedDictionary() {
        let event = Event()
        event.extra = [
            "users": [
                ["name": "Alice", "email": "alice@example.com"],
                ["name": "Bob", "id": "safe_id"]
            ]
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.extra)
        if let users = scrubbedEvent?.extra?["users"] as? [[String: String]] {
            XCTAssertEqual(users[0]["name"], "Alice")
            XCTAssertTrue(users[0]["email"]?.contains("[REDACTED_EMAIL]") ?? false)
            XCTAssertEqual(users[1]["name"], "Bob")
            XCTAssertEqual(users[1]["id"], "safe_id")
        } else {
            XCTFail("Array with nested dictionaries should be scrubbed")
        }
    }
    
    func testContainsSensitiveDataInArrayNestedArray() {
        let event = Event()
        event.extra = [
            "matrix": [
                ["safe1", "safe2"],
                ["3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", "safe3"]
            ]
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.extra)
        if let matrix = scrubbedEvent?.extra?["matrix"] as? [[String]] {
            XCTAssertEqual(matrix[0][0], "safe1")
            XCTAssertEqual(matrix[0][1], "safe2")
            XCTAssertTrue(matrix[1][0].contains("[REDACTED_HEX]"))
            XCTAssertEqual(matrix[1][1], "safe3")
        } else {
            XCTFail("Nested array should be scrubbed")
        }
    }
    
    func testContainsSensitiveDataInArrayAllCleanValues() {
        let event = Event()
        event.extra = [
            "items": ["value1", "value2", "value3"]
        ]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.extra)
        if let items = scrubbedEvent?.extra?["items"] as? [String] {
            XCTAssertEqual(items, ["value1", "value2", "value3"])
        } else {
            XCTFail("Clean array should remain unchanged")
        }
    }
    
    // MARK: - Test scrubStacktrace
    
    func testScrubStacktraceFunction() {
        let event = Event()
        let exception = Exception(value: "Test error", type: "TestException")
        
        let frame1 = Frame()
        frame1.function = "loginWithKey(nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq)"
        
        let frame2 = Frame()
        frame2.function = "processUser(user@example.com)"
        
        let stacktrace = SentryStacktrace(frames: [frame1, frame2], registers: [:])
        exception.stacktrace = stacktrace
        event.exceptions = [exception]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.exceptions)
        if let frames = scrubbedEvent?.exceptions?.first?.stacktrace?.frames {
            XCTAssertEqual(frames.count, 2)
            XCTAssertTrue(frames[0].function?.contains("[REDACTED_NSEC]") ?? false)
            XCTAssertFalse(frames[0].function?.contains("nsec1") ?? true)
            XCTAssertTrue(frames[1].function?.contains("[REDACTED_EMAIL]") ?? false)
            XCTAssertFalse(frames[1].function?.contains("user@example.com") ?? true)
        } else {
            XCTFail("Stacktrace frames should be scrubbed")
        }
    }
    
    func testScrubStacktraceFileName() {
        let event = Event()
        let exception = Exception(value: "Test error", type: "TestException")
        
        let frame = Frame()
        frame.function = "testFunction"
        frame.fileName = "UserProfile_npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123.swift"
        
        let stacktrace = SentryStacktrace(frames: [frame], registers: [:])
        exception.stacktrace = stacktrace
        event.exceptions = [exception]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.exceptions)
        if let frames = scrubbedEvent?.exceptions?.first?.stacktrace?.frames {
            XCTAssertEqual(frames.count, 1)
            XCTAssertTrue(frames[0].fileName?.contains("[REDACTED_NPUB]") ?? false)
            XCTAssertFalse(frames[0].fileName?.contains("npub1abc123") ?? true)
        } else {
            XCTFail("Stacktrace filename should be scrubbed")
        }
    }
    
    func testScrubStacktraceVars() {
        let event = Event()
        let exception = Exception(value: "Test error", type: "TestException")
        
        let frame = Frame()
        frame.function = "processData"
        frame.vars = [
            "userKey": "npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123",
            "email": "test@example.com",
            "count": "5"
        ]
        
        let stacktrace = SentryStacktrace(frames: [frame], registers: [:])
        exception.stacktrace = stacktrace
        event.exceptions = [exception]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.exceptions)
        if let frames = scrubbedEvent?.exceptions?.first?.stacktrace?.frames,
           let vars = frames[0].vars {
            XCTAssertTrue((vars["userKey"] as? String)?.contains("[REDACTED_NPUB]") ?? false)
            XCTAssertTrue((vars["email"] as? String)?.contains("[REDACTED_EMAIL]") ?? false)
            XCTAssertEqual(vars["count"] as? String, "5")
        } else {
            XCTFail("Stacktrace vars should be scrubbed")
        }
    }
    
    func testScrubStacktraceMultipleFrames() {
        let event = Event()
        let exception = Exception(value: "Test error", type: "TestException")
        
        let frame1 = Frame()
        frame1.function = "topLevel"
        frame1.vars = ["key": "nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"]
        
        let frame2 = Frame()
        frame2.function = "middleLevel with 3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d hex"
        frame2.fileName = "path/to/NormalFile.swift"
        
        let frame3 = Frame()
        frame3.function = "bottomLevel(email: admin@example.com)"
        
        let stacktrace = SentryStacktrace(frames: [frame1, frame2, frame3], registers: [:])
        exception.stacktrace = stacktrace
        event.exceptions = [exception]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.exceptions)
        if let frames = scrubbedEvent?.exceptions?.first?.stacktrace?.frames {
            XCTAssertEqual(frames.count, 3)
            
            // Check frame 1
            let frame1Key = frames[0].vars?["key"] as? String
            XCTAssertNotNil(frame1Key, "Frame 1 should have vars with key")
            XCTAssertTrue(frame1Key?.contains("[REDACTED_NSEC]") ?? false, "Frame 1 key should be redacted, got: \(frame1Key ?? "nil")")
            
            // Check frame 2
            let frame2Function = frames[1].function
            XCTAssertNotNil(frame2Function, "Frame 2 should have function")
            XCTAssertTrue(frame2Function?.contains("[REDACTED_HEX]") ?? false, "Frame 2 function should be redacted, got: \(frame2Function ?? "nil")")
            
            // Check frame 3
            let frame3Function = frames[2].function
            XCTAssertNotNil(frame3Function, "Frame 3 should have function")
            XCTAssertTrue(frame3Function?.contains("[REDACTED_EMAIL]") ?? false, "Frame 3 function should be redacted, got: \(frame3Function ?? "nil")")
        } else {
            XCTFail("Multiple stacktrace frames should be scrubbed")
        }
    }
    
    func testScrubStacktraceInThread() {
        let event = Event()
        let thread = SentryThread(threadId: 1)
        
        let frame = Frame()
        frame.function = "authenticate(nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq)"
        
        let stacktrace = SentryStacktrace(frames: [frame], registers: [:])
        thread.stacktrace = stacktrace
        event.threads = [thread]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.threads)
        if let threads = scrubbedEvent?.threads,
           let frames = threads.first?.stacktrace?.frames {
            XCTAssertTrue(frames[0].function?.contains("[REDACTED_NSEC]") ?? false)
            XCTAssertFalse(frames[0].function?.contains("nsec1") ?? true)
        } else {
            XCTFail("Thread stacktrace should be scrubbed")
        }
    }
    
    func testScrubStacktraceEmptyVars() {
        let event = Event()
        let exception = Exception(value: "Test error", type: "TestException")
        
        let frame = Frame()
        frame.function = "testFunction"
        frame.vars = [:] // Empty vars
        
        let stacktrace = SentryStacktrace(frames: [frame], registers: [:])
        exception.stacktrace = stacktrace
        event.exceptions = [exception]
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.exceptions)
        // Should not crash with empty vars
        XCTAssertNotNil(scrubbedEvent?.exceptions?.first?.stacktrace?.frames)
    }
    
    // MARK: - Test Real-world Scenarios
    
    func testScrubComplexErrorMessage() {
        let event = Event()
        event.message = SentryMessage(formatted: """
            Authentication failed for user npub1abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123
            Private key: nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
            Hex ID: 3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d
            Contact: support@damus.io
            Note: note1xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz7
            Event: nevent1qqsxyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789
            Profile: nprofile1qqsxyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789xyz789
        """)
        
        let scrubbedEvent = DamusSentry.scrubSensitiveData(in: event)
        
        XCTAssertNotNil(scrubbedEvent?.message?.formatted)
        let message = scrubbedEvent?.message?.formatted ?? ""
        XCTAssertTrue(message.contains("[REDACTED_NPUB]"))
        XCTAssertTrue(message.contains("[REDACTED_NSEC]"))
        XCTAssertTrue(message.contains("[REDACTED_HEX]"))
        XCTAssertTrue(message.contains("[REDACTED_EMAIL]"))
        XCTAssertTrue(message.contains("[REDACTED_NOTE]"))
        XCTAssertTrue(message.contains("[REDACTED_NEVENT]"))
        XCTAssertTrue(message.contains("[REDACTED_NPROFILE]"))
        
        // Ensure original sensitive data is not present
        XCTAssertFalse(message.contains("npub1abc"))
        XCTAssertFalse(message.contains("nsec1qqq"))
        XCTAssertFalse(message.contains("3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"))
        XCTAssertFalse(message.contains("support@damus.io"))
        XCTAssertFalse(message.contains("note1xyz"))
        XCTAssertFalse(message.contains("nevent1qqsxyz"))
        XCTAssertFalse(message.contains("nprofile1qqsxyz"))
    }
}
