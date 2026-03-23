import XCTest
import SchemataValidator
@testable import damus

class SchemaValidationTests: XCTestCase {

    /// Create a kind-1 event via Damus API, serialize it, and validate against schema.
    /// Proves NostrEvent → event_to_json() output is NIP-01 schema-compliant.
    func testKind1EventSchemaCompliance() throws {
        let ev = NostrEvent(content: "hello nostr", keypair: test_keypair, kind: 1)!
        let json = event_to_json(ev: ev)
        let dict = try jsonToDict(json)
        let result = SchemataValidator.validateNote(dict)
        XCTAssertTrue(result.valid, "NostrEvent serialization should be schema-compliant. Errors: \(result.errors)")
    }

    /// Validate a real Damus test fixture event.
    func testRealDamusEventSchemaCompliance() throws {
        let json = event_to_json(ev: test_note)
        let dict = try jsonToDict(json)
        let result = SchemataValidator.validateNote(dict)
        XCTAssertTrue(result.valid, "Real Damus test_note should be schema-compliant. Errors: \(result.errors)")
    }

    /// Event with p-tag serializes correctly.
    func testKind1WithTagsSchemaCompliance() throws {
        let ev = NostrEvent(content: "hi", keypair: test_keypair, kind: 1, tags: [["p", test_pubkey.hex()]])!
        let json = event_to_json(ev: ev)
        let dict = try jsonToDict(json)
        let result = SchemataValidator.validateNote(dict)
        XCTAssertTrue(result.valid, "NostrEvent with tags should be schema-compliant. Errors: \(result.errors)")
    }

    /// Missing required fields should fail validation.
    func testMissingFieldsFails() {
        let incomplete: [String: Any] = ["kind": 1, "content": "hello"]
        let result = SchemataValidator.validateNote(incomplete)
        XCTAssertFalse(result.valid, "Missing required fields should fail")
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - Helpers

    /// Parses a JSON string into a dictionary for schema validation.
    private func jsonToDict(_ json: String) throws -> [String: Any] {
        let data = json.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data)
        return obj as! [String: Any]
    }
}
