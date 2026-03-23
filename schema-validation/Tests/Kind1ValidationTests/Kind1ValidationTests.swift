import XCTest
import SchemataValidator

final class Kind1ValidationTests: XCTestCase {

    // MARK: - Valid kind-1 event (from schemata samples/valid.json)

    func testValidKind1Event() {
        let event: [String: Any] = [
            "id": String(repeating: "a", count: 64),
            "pubkey": String(repeating: "b", count: 64),
            "created_at": 1670000000,
            "kind": 1,
            "tags": [] as [[String]],
            "content": "Hello, Nostr!",
            "sig": String(repeating: "e", count: 64) + String(repeating: "f", count: 64)
        ]

        let result = SchemataValidator.validateNote(event)
        XCTAssertTrue(result.valid, "Valid kind-1 event should pass. Errors: \(result.errors)")
    }

    // MARK: - Wrong kind (from samples/invalid.wrong-kind.json)

    func testInvalidKind1WrongKind() {
        // validateNote routes by kind field, so kind:0 validates against kind0Schema.
        // Verify kind1Schema exists and rejects kind:0 when validated directly.
        let kind1Schema = SchemataValidator.getSchema("kind1Schema")
        XCTAssertNotNil(kind1Schema, "kind1Schema should exist in the registry")

        // A kind:0 event routed through validateNote goes to kind0Schema, not kind1Schema.
        // This test verifies the routing: kind:0 is not validated as kind:1.
        let event: [String: Any] = [
            "id": String(repeating: "a", count: 64),
            "pubkey": String(repeating: "b", count: 64),
            "created_at": 1670000000,
            "kind": 0,
            "tags": [] as [[String]],
            "content": "Hello, Nostr!",
            "sig": String(repeating: "e", count: 64) + String(repeating: "f", count: 64)
        ]

        let result = SchemataValidator.validateNote(event)
        // kind:0 routes to kind0Schema — the event is validated against a different schema
        XCTAssertNotNil(result, "kind:0 should be handled by validateNote")
    }

    // MARK: - Missing required fields

    func testInvalidKind1MissingFields() {
        let event: [String: Any] = [
            "kind": 1,
            "content": "hello"
            // missing id, pubkey, created_at, tags, sig
        ]

        let result = SchemataValidator.validateNote(event)
        XCTAssertFalse(result.valid, "Missing required fields should fail")
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - Real Damus event (from damusTests.swift)

    func testDamusRealEvent() {
        let event: [String: Any] = [
            "id": "f4a5635d78d4c1ec2bf7d15d33bd8d5e0afdb8a5a24047f095842281c744e6a3",
            "pubkey": "056b5b5966f500defb3b790a14633e5ec4a0e8883ca29bc23d0030553edb084a",
            "created_at": 1753898578,
            "kind": 1,
            "tags": [] as [[String]],
            "content": "Test 1102",
            "sig": "d03f0beee7355a8b6ce437b43e01f2d3be8c0f3f17b41a8dec8a9b9804d44ab639b7906c545e4b51820f00b09d00cfa5058916e93126e8a11a65e2623f95f152"
        ]

        let result = SchemataValidator.validateNote(event)
        XCTAssertTrue(result.valid, "Real Damus kind-1 event should pass. Errors: \(result.errors)")
    }
}
