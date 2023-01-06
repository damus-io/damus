//
//  MarkdownTests.swift
//  damusTests
//
//  Created by Lionello Lunesu on 2022-12-28.
//

import XCTest
@testable import damus

class MarkdownTests: XCTestCase {
    let md_opts: AttributedString.MarkdownParsingOptions =
        .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_convert_link() throws {
        let helper = Markdown()
        let md = helper.process("prologue https://nostr.build epilogue")
        let expected = try AttributedString(markdown: "prologue [https://nostr.build](https://nostr.build) epilogue", options: md_opts)
        XCTAssertEqual(md, expected)
    }

    func test_convert_link_no_scheme() throws {
        let helper = Markdown()
        let md = helper.process("prologue damus.io epilogue")
        let expected = try AttributedString(markdown: "prologue [damus.io](https://damus.io) epilogue", options: md_opts)
        XCTAssertEqual(md, expected)
    }

    func test_convert_links() throws {
        let helper = Markdown()
        let md = helper.process("prologue damus.io https://nostr.build epilogue")
        let expected = try AttributedString(markdown: "prologue [damus.io](https://damus.io) [https://nostr.build](https://nostr.build) epilogue", options: md_opts)
        XCTAssertEqual(md, expected)
    }

    func test_convert_http() throws {
        let helper = Markdown()
        let md = helper.process("prologue http://example.com epilogue")
        let expected = try AttributedString(markdown: "prologue [http://example.com](http://example.com) epilogue", options: md_opts)
        XCTAssertEqual(md, expected)
    }

    func test_convert_mailto() throws {
        let helper = Markdown()
        let md = helper.process("prologue test@example.com epilogue")
        let expected = try AttributedString(markdown: "prologue [test@example.com](mailto:test@example.com) epilogue", options: md_opts)
        XCTAssertEqual(md, expected)
    }

    func test_convert_mailto_implicit() throws {
        let helper = Markdown()
        let md = helper.process("prologue mailto:test@example.com epilogue")
        let expected = try AttributedString(markdown: "prologue [mailto:test@example.com](mailto:test@example.com) epilogue", options: md_opts)
        XCTAssertEqual(md, expected)
    }

    func test_parse_shrug() throws {
        let md = Markdown.parse(content: "¯\\_(ツ)_/¯")
        XCTAssertEqual(NSMutableAttributedString(md).string, "¯\\_(ツ)_/¯")
    }

    func test_parse_backslash() throws {
        let md = Markdown.parse(content: "\\a")
        XCTAssertEqual(NSMutableAttributedString(md).string, "\\a")
    }

}
