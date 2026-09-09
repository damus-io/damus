import XCTest
@testable import damus

final class VoiceMediaReferenceTests: XCTestCase {
    private let hash = String(repeating: "a", count: 64)
    private let url = "https://media.example/opaque/path?token=a%2Fb&version=2"
    private var tags: [[String]] { [["url", url], ["blossom", hash, "audio/mp4"]] }

    func testOpaqueURLAndRepeatedConsistentDeclarationsArePreserved() throws {
        let reference = try VoiceMediaReference(tags: tags + tags + [
            ["x", hash], ["m", "Audio/MP4"],
            ["imeta", "url " + url, "x " + hash, "m audio/mp4"], ["duration", "1.250"]
        ])
        XCTAssertEqual(reference.url, url)
        XCTAssertEqual(reference.sha256, hash)
        XCTAssertEqual(reference.mimeType, "audio/mp4")
        XCTAssertEqual(reference.statedDuration, 1.25)
    }

    func testCoverMetadataDoesNotReplaceThePrimaryAudio() throws {
        let reference = try VoiceMediaReference(tags: tags + [
            ["imeta", "url https://images.example/cover", "x " + String(repeating: "b", count: 64), "m image/jpeg"]
        ])
        XCTAssertEqual(reference.url, url)
    }

    func testEveryAuthoritativeConflictIsRejectedRegardlessOfOrder() {
        let conflicts = [
            ["url", "https://media.example/different"], ["url"],
            ["blossom", String(repeating: "b", count: 64), "audio/mp4"],
            ["blossom", hash, "audio/mpeg"], ["blossom"],
            ["x", "bad"], ["m", "video/mp4"],
            ["imeta", "url " + url, "x wrong"],
            ["imeta", "url " + url, "m"],
            ["imeta", "x " + hash, "url"],
            ["imeta", "url https://media.example/different", "m audio/mp4"]
        ]
        for conflict in conflicts {
            XCTAssertThrowsError(try VoiceMediaReference(tags: tags + [conflict]), String(describing: conflict))
            XCTAssertThrowsError(try VoiceMediaReference(tags: [conflict] + tags), String(describing: conflict))
        }
    }

    func testMissingAuthorityIsNeverGuessedFromOtherTags() {
        XCTAssertThrowsError(try VoiceMediaReference(tags: [["url", url], ["x", hash], ["m", "audio/mp4"]]))
        XCTAssertThrowsError(try VoiceMediaReference(tags: [["blossom", hash, "audio/mp4"], ["r", url], ["imeta", "url " + url]]))
    }

    func testBadOrConflictingDurationDoesNotPreventReceiving() throws {
        for value in ["", "-1", "nan", "inf", "1e9", "broken", "1,5"] {
            let reference = try VoiceMediaReference(tags: tags + [["duration", value]])
            XCTAssertNil(reference.statedDuration, value)
            XCTAssertFalse(reference.tags.contains { $0.first == "duration" })
        }
        let conflicting = try VoiceMediaReference(tags: tags + [["duration", "1"], ["duration", "2"]])
        XCTAssertNil(conflicting.statedDuration)
        XCTAssertNil(try VoiceMediaReference(tags: tags).statedDuration)
    }

    func testHashMIMEAndHTTPSValidationRejectMalformedValues() {
        for badHash in ["", "abc", hash.uppercased(), String(repeating: "g", count: 64)] {
            XCTAssertThrowsError(try VoiceMediaReference(tags: [["url", url], ["blossom", badHash, "audio/mp4"]]))
        }
        for mime in ["video/mp4", "audio/", "audio/not a type", "audio/a/b", "audio/mp4\r\nInjected: yes"] {
            XCTAssertThrowsError(try VoiceMediaReference(tags: [["url", url], ["blossom", hash, mime]]))
        }
        for invalid in ["http://media.example/a", "file:///tmp/a.m4a", "https://user:pass@media.example/a", "https://media.example/a#fragment"] {
            XCTAssertThrowsError(try VoiceMediaReference(tags: [["url", invalid], ["blossom", hash, "audio/mp4"]]))
        }
    }

    func testSavedMetadataCannotBypassValidation() throws {
        let valid = try VoiceMediaReference(tags: tags + [["duration", "1.5"]])
        let encoded = try JSONEncoder().encode(valid)
        XCTAssertEqual(try JSONDecoder().decode(VoiceMediaReference.self, from: encoded), valid)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["url"] = "file:///private/recording.m4a"
        XCTAssertThrowsError(try JSONDecoder().decode(VoiceMediaReference.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    func testOutgoingDurationMustBeMeasuredAndFinite() throws {
        let receipt = try VoiceMediaReference(url: url, sha256: hash, mimeType: "audio/mp4")
        XCTAssertNil(receipt.statedDuration)
        XCTAssertFalse(receipt.tags.contains { $0.first == "duration" })
        for invalid in [Double.nan, .infinity, -0.1] {
            XCTAssertThrowsError(try VoiceMediaReference(url: url, sha256: hash, mimeType: "audio/mp4", duration: invalid))
        }
    }

    func testNostrBuildDefaultAndPaidSubdomainAreTheOnlyUploadDestinations() throws {
        XCTAssertEqual(try VoiceBlossomUploader.origin("").absoluteString, "https://blossom.band")
        XCTAssertEqual(try VoiceBlossomUploader.origin("https://alice.blossom.band/").host, "alice.blossom.band")
        for invalid in ["https://storage.example", "https://blossom.band.attacker.example", "https://notblossom.band",
                        "http://blossom.band", "https://blossom.band/upload", "https://blossom.band?token=x", "https://blossom.band:8443"] {
            XCTAssertThrowsError(try VoiceBlossomUploader.origin(invalid), invalid)
        }
    }
}
