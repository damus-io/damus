import XCTest
@testable import damus

final class URLHandlerTests: XCTestCase {
    func testParseRelayURLDirectWsScheme() throws {
        let relayURLString = "wss://relay.damus.io"
        let url = try XCTUnwrap(URL(string: relayURLString))

        let parsed = DamusURLHandler.parse_url(url: url)

        switch parsed {
        case .relay(let relay):
            XCTAssertEqual(relay.absoluteString, relayURLString)
        default:
            XCTFail("Expected relay info for \(relayURLString) but got \(String(describing: parsed))")
        }
    }

    func testParseRelayURLFromDamusDeepLink() throws {
        let relayURLString = "wss://relay.damus.io"
        let encoded = relayURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? relayURLString
        let deepLinkString = "damus://relay?url=\(encoded)"
        let url = try XCTUnwrap(URL(string: deepLinkString))

        let parsed = DamusURLHandler.parse_url(url: url)

        switch parsed {
        case .relay(let relay):
            XCTAssertEqual(relay.absoluteString, relayURLString)
        default:
            XCTFail("Expected relay info for deep link but got \(String(describing: parsed))")
        }
    }

    func testParseRelayURLFromDamusRelayPath() throws {
        let relayURLString = "wss://relay.damus.io"
        let deepLinkString = "damus://relay/\(relayURLString)"
        let url = try XCTUnwrap(URL(string: deepLinkString))

        let parsed = DamusURLHandler.parse_url(url: url)

        switch parsed {
        case .relay(let relay):
            XCTAssertEqual(relay.absoluteString, relayURLString)
        default:
            XCTFail("Expected relay info for relay path but got \(String(describing: parsed))")
        }
    }
}
