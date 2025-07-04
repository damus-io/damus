//
//  NoteContentViewTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-08-02.
//

import XCTest
import SwiftUI
@testable import damus

class NoteContentViewTests: XCTestCase {
    /*
    func testRenderBlocksWithNonLatinHashtags() {
        let content = "Damusはかっこいいです #cool #かっこいい"
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair, tags: [["t", "かっこいい"]]))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state
        
        let text: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles, note: note, can_hide_last_previewable_refs: true) 
        let attributedText: AttributedString = text.content.attributed
        
        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        print(runArray.description)
        XCTAssertEqual(runArray[1].link?.absoluteString, "damus:t:cool", "Latin-character hashtag is missing. Runs description :\(runArray.description)")
        XCTAssertEqual(runArray[3].link?.absoluteString.removingPercentEncoding, "damus:t:かっこいい", "Non-latin-character hashtag is missing. Runs description :\(runArray.description)")
    }

    func testRenderBlocksWithLeadingAndTrailingWhitespacesTrimmed() throws {
        let content = "  \n\n  Hello, \nworld! \n\n   "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles, can_hide_last_previewable_refs: true)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed
        let text = attributedText.description

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)

        XCTAssertEqual(runArray.count, 1)
        XCTAssertTrue(text.contains("Hello, \nworld!"))
        XCTAssertFalse(text.contains(content))
    }

    func testRenderBlocksWithMediaBlockInMiddleRendered() throws {
        let content = "    Check this out: https://damus.io/image.png Isn't this cool?    "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 3)
        XCTAssertTrue(runArray[0].description.contains("Check this out: "))
        XCTAssertTrue(runArray[1].description.contains("https://damus.io/image.png "))
        XCTAssertEqual(runArray[1].link?.absoluteString, "https://damus.io/image.png")
        XCTAssertTrue(runArray[2].description.contains(" Isn't this cool?"))

        XCTAssertEqual(noteArtifactsSeparated.images.count, 1)
        XCTAssertEqual(noteArtifactsSeparated.images[0].absoluteString, "https://damus.io/image.png")
    }

    func testRenderBlocksWithInvoiceInMiddleAbbreviated() throws {
        let invoiceString = "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r"
        let content = "    Donations appreciated: \(invoiceString) Pura Vida    "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 3)
        XCTAssertTrue(runArray[0].description.contains("Donations appreciated: "))
        XCTAssertTrue(runArray[1].description.contains("lnbc100n:qpsql29r"))
        XCTAssertEqual(runArray[1].link?.absoluteString, "damus:lightning:\(invoiceString)")
        XCTAssertTrue(runArray[2].description.contains(" Pura Vida"))
    }

    func testRenderBlocksWithNoteIdInMiddleAreRendered() throws {
        let noteId = test_note.id.bech32
        let content = "    Check this out: nostr:\(noteId) Pura Vida    "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 3)
        XCTAssertTrue(runArray[0].description.contains("Check this out: "))
        XCTAssertTrue(runArray[1].description.contains("note1qqq:qqn2l0z3"))
        XCTAssertEqual(runArray[1].link?.absoluteString, "damus:nostr:\(noteId)")
        XCTAssertTrue(runArray[2].description.contains(" Pura Vida"))
    }

    func testRenderBlocksWithNeventInMiddleAreRendered() throws {
        let nevent = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        let content = "    Check this out: nostr:\(nevent) Pura Vida    "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 3)
        XCTAssertTrue(runArray[0].description.contains("Check this out: "))
        XCTAssertTrue(runArray[1].description.contains("nevent1q:t5nxnepm"))
        XCTAssertEqual(runArray[1].link?.absoluteString, "damus:nostr:\(nevent)")
        XCTAssertTrue(runArray[2].description.contains(" Pura Vida"))
    }

    func testRenderBlocksWithPreviewableBlocksAtEndAreHidden() throws {
        let noteId = test_note.id.bech32
        let invoiceString = "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r"
        let content = "    Check this out.   \nhttps://hidden.tld/\nhttps://damus.io/hidden1.png\n\(invoiceString)\nhttps://damus.io/hidden2.png\nnostr:\(noteId) "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles, can_hide_last_previewable_refs: true)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 1)
        XCTAssertTrue(runArray[0].description.contains("Check this out."))
        XCTAssertFalse(runArray[0].description.contains("https://hidden.tld/"))
        XCTAssertFalse(runArray[0].description.contains("https://damus.io/hidden1.png"))
        XCTAssertFalse(runArray[0].description.contains("lnbc100n:qpsql29r"))
        XCTAssertFalse(runArray[0].description.contains("https://damus.io/hidden2.png"))
        XCTAssertFalse(runArray[0].description.contains("note1qqq:qqn2l0z3"))

        XCTAssertEqual(noteArtifactsSeparated.images.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.images[0].absoluteString, "https://damus.io/hidden1.png")
        XCTAssertEqual(noteArtifactsSeparated.images[1].absoluteString, "https://damus.io/hidden2.png")

        XCTAssertEqual(noteArtifactsSeparated.media.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.media[0].url.absoluteString, "https://damus.io/hidden1.png")
        XCTAssertEqual(noteArtifactsSeparated.media[1].url.absoluteString, "https://damus.io/hidden2.png")

        XCTAssertEqual(noteArtifactsSeparated.links.count, 1)
        XCTAssertEqual(noteArtifactsSeparated.links[0].absoluteString, "https://hidden.tld/")

        XCTAssertEqual(noteArtifactsSeparated.invoices.count, 1)
        XCTAssertEqual(noteArtifactsSeparated.invoices[0].string, invoiceString)
    }

    func testRenderBlocksWithMultipleLinksAtEndAreNotHidden() throws {
        let noteId = test_note.id.bech32
        let invoiceString = "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r"
        let content = "    Check this out.   \nhttps://nothidden1.tld/\nhttps://nothidden2.tld/\nhttps://damus.io/nothidden1.png\n\(invoiceString)\nhttps://damus.io/nothidden2.png\nnostr:\(noteId) "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles, can_hide_last_previewable_refs: true)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 12)
        XCTAssertTrue(runArray[0].description.contains("Check this out."))
        XCTAssertTrue(runArray[1].description.contains("https://nothidden1.tld/"))
        XCTAssertTrue(runArray[3].description.contains("https://nothidden2.tld/"))
        XCTAssertTrue(runArray[5].description.contains("https://damus.io/nothidden1.png"))
        XCTAssertTrue(runArray[7].description.contains("lnbc100n:qpsql29r"))
        XCTAssertTrue(runArray[9].description.contains("https://damus.io/nothidden2.png"))
        XCTAssertTrue(runArray[11].description.contains("note1qqq:qqn2l0z3"))

        XCTAssertEqual(noteArtifactsSeparated.images.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.images[0].absoluteString, "https://damus.io/nothidden1.png")
        XCTAssertEqual(noteArtifactsSeparated.images[1].absoluteString, "https://damus.io/nothidden2.png")

        XCTAssertEqual(noteArtifactsSeparated.media.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.media[0].url.absoluteString, "https://damus.io/nothidden1.png")
        XCTAssertEqual(noteArtifactsSeparated.media[1].url.absoluteString, "https://damus.io/nothidden2.png")

        XCTAssertEqual(noteArtifactsSeparated.links.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.links[0].absoluteString, "https://nothidden1.tld/")
        XCTAssertEqual(noteArtifactsSeparated.links[1].absoluteString, "https://nothidden2.tld/")

        XCTAssertEqual(noteArtifactsSeparated.invoices.count, 1)
        XCTAssertEqual(noteArtifactsSeparated.invoices[0].string, invoiceString)
    }

    func testRenderBlocksWithMultipleEventsAtEndAreNotHidden() throws {
        let noteId = test_note.id.bech32
        let nevent = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        let invoiceString = "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r"
        let content = "    Check this out.   \nnostr:\(noteId)\nnostr:\(nevent)\nhttps://damus.io/nothidden1.png\n\(invoiceString)\nhttps://damus.io/nothidden2.png "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles, can_hide_last_previewable_refs: true)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 10)
        XCTAssertTrue(runArray[0].description.contains("Check this out."))
        XCTAssertTrue(runArray[1].description.contains("note1qqq:qqn2l0z3"))
        XCTAssertTrue(runArray[3].description.contains("nevent1q:t5nxnepm"))
        XCTAssertTrue(runArray[5].description.contains("https://damus.io/nothidden1.png"))
        XCTAssertTrue(runArray[7].description.contains("lnbc100n:qpsql29r"))
        XCTAssertTrue(runArray[9].description.contains("https://damus.io/nothidden2.png"))

        XCTAssertEqual(noteArtifactsSeparated.images.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.images[0].absoluteString, "https://damus.io/nothidden1.png")
        XCTAssertEqual(noteArtifactsSeparated.images[1].absoluteString, "https://damus.io/nothidden2.png")

        XCTAssertEqual(noteArtifactsSeparated.media.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.media[0].url.absoluteString, "https://damus.io/nothidden1.png")
        XCTAssertEqual(noteArtifactsSeparated.media[1].url.absoluteString, "https://damus.io/nothidden2.png")

        XCTAssertEqual(noteArtifactsSeparated.links.count, 0)

        XCTAssertEqual(noteArtifactsSeparated.invoices.count, 1)
        XCTAssertEqual(noteArtifactsSeparated.invoices[0].string, invoiceString)
    }

    func testRenderBlocksWithPreviewableBlocksAtEndAreNotHiddenWhenMediaBlockPrecedesThem() throws {
        let content = "    Check this out: https://damus.io/image.png Isn't this cool?   \nhttps://damus.io/nothidden.png "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles, can_hide_last_previewable_refs: true)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 4)
        XCTAssertTrue(runArray[0].description.contains("Check this out: "))
        XCTAssertTrue(runArray[1].description.contains("https://damus.io/image.png "))
        XCTAssertEqual(runArray[1].link?.absoluteString, "https://damus.io/image.png")
        XCTAssertTrue(runArray[2].description.contains(" Isn't this cool?"))
        XCTAssertTrue(runArray[3].description.contains("https://damus.io/nothidden.png"))
        XCTAssertEqual(runArray[3].link?.absoluteString, "https://damus.io/nothidden.png")

        XCTAssertEqual(noteArtifactsSeparated.images.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.images[0].absoluteString, "https://damus.io/image.png")
        XCTAssertEqual(noteArtifactsSeparated.images[1].absoluteString, "https://damus.io/nothidden.png")
    }

    func testRenderBlocksWithPreviewableBlocksAtEndAreNotHiddenWhenInvoicePrecedesThem() throws {
        let invoiceString = "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r"
        let content = "    Donations appreciated: \(invoiceString) Pura Vida   \nhttps://damus.io/nothidden.png "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles, can_hide_last_previewable_refs: true)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 4)
        XCTAssertTrue(runArray[0].description.contains("Donations appreciated: "))
        XCTAssertTrue(runArray[1].description.contains("lnbc100n:qpsql29r"))
        XCTAssertEqual(runArray[1].link?.absoluteString, "damus:lightning:\(invoiceString)")
        XCTAssertTrue(runArray[2].description.contains(" Pura Vida"))
        XCTAssertTrue(runArray[3].description.contains("https://damus.io/nothidden.png"))
        XCTAssertEqual(runArray[3].link?.absoluteString, "https://damus.io/nothidden.png")

        XCTAssertEqual(noteArtifactsSeparated.images.count, 1)
        XCTAssertEqual(noteArtifactsSeparated.images[0].absoluteString, "https://damus.io/nothidden.png")
    }

    func testRenderBlocksWithPreviewableBlocksAtEndAreHiddenWhenHashtagsAreEmbedded() throws {
        let noteId = test_note.id.bech32
        let invoiceString = "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r"
        let content = "    Check this out.   \nhttps://hidden.tld/\nhttps://damus.io/hidden1.png\n\(invoiceString)\nhttps://damus.io/hidden2.png\nnostr:\(noteId)#hashtag1 #hashtag2 "
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair))
        let parsed: Blocks = parse_note_content(content: .init(note: note, keypair: test_keypair))

        let testState = test_damus_state

        let noteArtifactsSeparated: NoteArtifactsSeparated = render_blocks(blocks: parsed, profiles: testState.profiles, can_hide_last_previewable_refs: true)
        let attributedText: AttributedString = noteArtifactsSeparated.content.attributed

        let runs: AttributedString.Runs = attributedText.runs
        let runArray: [AttributedString.Runs.Run] = Array(runs)
        XCTAssertEqual(runArray.count, 4)
        XCTAssertTrue(runArray[0].description.contains("Check this out."))
        XCTAssertFalse(runArray[0].description.contains("https://hidden.tld/"))
        XCTAssertFalse(runArray[0].description.contains("https://damus.io/hidden1.png"))
        XCTAssertFalse(runArray[0].description.contains("lnbc100n:qpsql29r"))
        XCTAssertFalse(runArray[0].description.contains("https://damus.io/hidden2.png"))
        XCTAssertFalse(runArray[0].description.contains("note1qqq:qqn2l0z3"))
        XCTAssertTrue(runArray[1].description.contains("#hashtag1"))
        XCTAssertTrue(runArray[3].description.contains("#hashtag2"))

        XCTAssertEqual(noteArtifactsSeparated.images.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.images[0].absoluteString, "https://damus.io/hidden1.png")
        XCTAssertEqual(noteArtifactsSeparated.images[1].absoluteString, "https://damus.io/hidden2.png")

        XCTAssertEqual(noteArtifactsSeparated.media.count, 2)
        XCTAssertEqual(noteArtifactsSeparated.media[0].url.absoluteString, "https://damus.io/hidden1.png")
        XCTAssertEqual(noteArtifactsSeparated.media[1].url.absoluteString, "https://damus.io/hidden2.png")

        XCTAssertEqual(noteArtifactsSeparated.links.count, 1)
        XCTAssertEqual(noteArtifactsSeparated.links[0].absoluteString, "https://hidden.tld/")

        XCTAssertEqual(noteArtifactsSeparated.invoices.count, 1)
        XCTAssertEqual(noteArtifactsSeparated.invoices[0].string, invoiceString)
    }
     */

    /// Based on https://github.com/damus-io/damus/issues/1468
    /// Tests whether a note content view correctly parses an image block when url in JSON content contains optional escaped slashes
    func testParseImageBlockInContentWithEscapedSlashes() throws {
        let testJSONWithEscapedSlashes = "{\"tags\":[],\"pubkey\":\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\",\"content\":\"https:\\/\\/cdn.nostr.build\\/i\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg\",\"created_at\":1691864981,\"kind\":1,\"sig\":\"fc0033aa3d4df50b692a5b346fa816fdded698de2045e36e0642a021391468c44ca69c2471adc7e92088131872d4aaa1e90ea6e1ad97f3cc748f4aed96dfae18\",\"id\":\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\"}"
        let testNote = NostrEvent.owned_from_json(json: testJSONWithEscapedSlashes)!
        let parsed = parse_note_content(content: .init(note: testNote, keypair: test_keypair))!

        XCTAssertTrue((parsed.blocks[0].asURL != nil), "NoteContentView does not correctly parse an image block when url in JSON content contains optional escaped slashes.")
    }
    
    /// Quick test that exercises the direct parsing methods (i.e. not fetching blocks from nostrdb) from `NdbBlockGroup`, and its bridging code with C.
    /// The parsing logic itself already has test coverage at the nostrdb level.
    func testDirectBlockParsing() {
        let kp = test_keypair_full
        let dm: NdbNote = NIP04.create_dm("Test", to_pk: kp.pubkey, tags: [], keypair: kp.to_keypair())!
        let blocks = try! NdbBlockGroup.from(event: dm, using: test_damus_state.ndb, and: kp.to_keypair())
        let blockCount1 = try? blocks.withList({ $0.count })
        XCTAssertEqual(blockCount1, 1)
        
        let post = NostrPost(content: "Test", kind: .text)
        let event = post.to_event(keypair: kp)!
        let blocks2 = try! NdbBlockGroup.from(event: event, using: test_damus_state.ndb, and: kp.to_keypair())
        let blockCount2 = try? blocks2.withList({ $0.count })
        XCTAssertEqual(blockCount2, 1)
    }
    
    func testMentionStr_Pubkey_ContainsAbbreviated() throws {
        let compatibleText = createCompatibleText(test_pubkey.npub)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "17ldvg64:nq5mhr77")
    }
    
    func testMentionStr_Pubkey_ContainsFullBech32() {
        let compatableText = createCompatibleText(test_pubkey.npub)

        assertCompatibleTextHasExpectedString(compatibleText: compatableText, expected: test_pubkey.npub)
    }
    
    func testMentionStr_Nprofile_ContainsAbbreviated() throws {
        let compatibleText = createCompatibleText("nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p")
                
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "180cvv07:wsyjh6w6")
    }
    
    func testMentionStr_Nprofile_ContainsFullBech32() throws {
        let bech = "nprofile1qqsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8gpp4mhxue69uhhytnc9e3k7mgpz4mhxue69uhkg6nzv9ejuumpv34kytnrdaksjlyr9p"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: bech)
    }
    
    func testMentionStr_Note_ContainsAbbreviated() {
        let compatibleText = createCompatibleText(test_note.id.bech32)

        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "note1qqq:qqn2l0z3")
    }
    
    func testMentionStr_Note_ContainsFullBech32() {
        let compatibleText = createCompatibleText(test_note.id.bech32)

        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: test_note.id.bech32)
    }
    
    func testMentionStr_Nevent_ContainsAbbreviated() {
        let bech = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        let compatibleText = createCompatibleText(bech)

        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "nevent1q:t5nxnepm")
    }
    
    func testMentionStr_Nevent_ContainsFullBech32() throws {
        let bech = "nevent1qqstna2yrezu5wghjvswqqculvvwxsrcvu7uc0f78gan4xqhvz49d9spr3mhxue69uhkummnw3ez6un9d3shjtn4de6x2argwghx6egpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5nxnepm"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: bech)
    }
    
    func testMentionStr_Nrelay_ContainsAbbreviated() {
        let bech = "nrelay1qqt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueq4r295t"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "wss://relay.nostr.band")
    }
    
    func testMentionStr_Nrelay_ContainsFullBech32() {
        let bech = "nrelay1qqt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueq4r295t"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: bech)
    }
    
    func testMentionStr_Naddr_ContainsAbbreviated() {
        let bech = "naddr1qqxnzdesxqmnxvpexqunzvpcqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqzypve7elhmamff3sr5mgxxms4a0rppkmhmn7504h96pfcdkpplvl2jqcyqqq823cnmhuld"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: "naddr1qq:3cnmhuld")
    }
    
    func testMentionStr_Naddr_ContainsFullBech32() {
        let bech = "naddr1qqxnzdesxqmnxvpexqunzvpcqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqzypve7elhmamff3sr5mgxxms4a0rppkmhmn7504h96pfcdkpplvl2jqcyqqq823cnmhuld"
        let compatibleText = createCompatibleText(bech)
        
        assertCompatibleTextHasExpectedString(compatibleText: compatibleText, expected: bech)
    }

}

private func assertCompatibleTextHasExpectedString(compatibleText: CompatibleText, expected: String) {
    guard let hasExpected = compatibleText.items.first?.attributed_string()?.description.contains(expected) else {
        XCTFail()
        return
    }
    
    XCTAssertTrue(hasExpected)
}

private func createCompatibleText(_ bechString: String) -> CompatibleText {
    guard let mentionRef = Bech32Object.parse(bechString)?.toMentionRef() else {
        XCTFail("Failed to create MentionRef from Bech32 string")
        return CompatibleText()
    }
    return mention_str(.any(mentionRef), profiles: test_damus_state.profiles)
}
