//
//  PurpleVideoRoutesTests.swift
//  damusTests
//
//  Building the URLs the hosted-video API is reached at.
//
//  These matter more than they look. Every video route is NIP-98
//  authenticated, and the auth event signs the URL as a string in its `u` tag.
//  A trailing slash, an unencoded guid, or a query parameter added after the
//  event was built produces a 401 with no useful body — which reads exactly
//  like a broken keypair and is the single most likely way this client fails
//  in the field.
//

import XCTest
@testable import damus

final class PurpleVideoRoutesTests: XCTestCase {
    let base = URL(string: "http://localhost:8989")!

    func testAuthorizeRouteHasNoTrailingSlash() {
        // Express matches `/video` and `/video/` differently enough that a
        // redirect would drop the `Authorization` header on the way.
        XCTAssertEqual(PurpleVideoRoutes.authorize(base: base).absoluteString, "http://localhost:8989/video")
    }

    func testAuthorizeRouteToleratesABaseWithATrailingSlash() {
        let slashed = URL(string: "https://api.damus.io/")!
        XCTAssertEqual(PurpleVideoRoutes.authorize(base: slashed).absoluteString, "https://api.damus.io/video")
    }

    func testAuthorizeRouteKeepsAnExistingPathPrefix() {
        let prefixed = URL(string: "https://example.com/purple")!
        XCTAssertEqual(PurpleVideoRoutes.authorize(base: prefixed).absoluteString, "https://example.com/purple/video")
    }

    func testVideoRouteAppendsTheGuidAsOnePathComponent() throws {
        let url = try PurpleVideoRoutes.video(base: base, id: "1bdab18a-0dc5-4ad6-9874-092ec58cd6b5")
        XCTAssertEqual(url.absoluteString, "http://localhost:8989/video/1bdab18a-0dc5-4ad6-9874-092ec58cd6b5")
    }

    func testVideoRouteEncodesTheGuid() throws {
        // The signed `u` tag is this URL's `absoluteString`, so whatever
        // encoding happens has to happen once, here, before signing.
        let url = try PurpleVideoRoutes.video(base: base, id: "not a guid")
        XCTAssertEqual(url.absoluteString, "http://localhost:8989/video/not%20a%20guid")
    }

    func testVideoRouteRejectsAPathTraversalID() {
        // A guid is semi-public by design — it is the playback URL, and a
        // non-owner is deliberately given a 404. That is no reason to let one
        // walk out of our own base path.
        let hostile = ["../../admin", "a/b", "a\\b", "..", ".", "", "%2e%2e"]

        for id in hostile {
            XCTAssertThrowsError(try PurpleVideoRoutes.video(base: base, id: id), "accepted \(id)") { error in
                XCTAssertEqual(error as? PurpleVideoAPIError, .invalidVideoID(id))
            }
        }
    }

    func testVideoRouteRejectsAnIdThatIsAlreadyPercentEncoded() {
        // Escaping it again would produce a path the server never stored, and
        // the failure would arrive as a 404 rather than as a bad id.
        XCTAssertThrowsError(try PurpleVideoRoutes.video(base: base, id: "abc%20def"))
    }
}
