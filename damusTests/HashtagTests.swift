//
//  HashtagTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-07-11.
//  Modified by Jon Marrs on 2023-09-12.
//

import XCTest
@testable import damus


final class HashtagTests: XCTestCase {
    
    // Basic hashtag tests
    
    func testParseHashtag() {
        let parsed = parse_note_content(content: .content("some hashtag #bitcoin derp",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "some hashtag ")
        XCTAssertEqual(parsed[1].asHashtag, "bitcoin")
        XCTAssertEqual(parsed[2].asText, " derp")
    }
    
    func testParseHashtagEnd() {
        let parsed = parse_note_content(content: .content("some hashtag #bitcoin",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].asText, "some hashtag ")
        XCTAssertEqual(parsed[1].asHashtag, "bitcoin")
    }
    
    //------------------------------------------------------------
    // Test ASCII
    //------------------------------------------------------------
    
    // Test ASCII punctuation exceptions (punctuation that is allowed in hashtags)
    
    // Underscores are allowed in hashtags
    func testHashtagWithUnderscore() {
        let parsed = parse_note_content(content: .content("the #under_score is allowed in hashtags",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "under_score")
        XCTAssertEqual(parsed[2].asText, " is allowed in hashtags")
    }
    
    // Test ASCII punctuation (not allowed in hashtags)
    
    func testHashtagWithComma() {
        let parsed = parse_note_content(content: .content("the #comma, is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "comma")
        XCTAssertEqual(parsed[2].asText, ", is not allowed")
    }
    
    func testHashtagWithPeriod() {
        let parsed = parse_note_content(content: .content("the #period. is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "period")
        XCTAssertEqual(parsed[2].asText, ". is not allowed")
    }
    
    func testHashtagWithQuestionMark() {
        let parsed = parse_note_content(content: .content("the #question?mark is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "question")
        XCTAssertEqual(parsed[2].asText, "?mark is not allowed")
    }
    
    func testHashtagWithGraveAccent() {
        let parsed = parse_note_content(content: .content("the #grave`accent is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "grave")
        XCTAssertEqual(parsed[2].asText, "`accent is not allowed")
    }
    
    func testHashtagWithTilde() {
        let parsed = parse_note_content(content: .content("the #tilde~ is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "tilde")
        XCTAssertEqual(parsed[2].asText, "~ is not allowed")
    }
    
    func testHashtagWithExclamationPoint() {
        let parsed = parse_note_content(content: .content("the #exclamation!point is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "exclamation")
        XCTAssertEqual(parsed[2].asText, "!point is not allowed")
    }
    
    func testHashtagWithAtSign() {
        let parsed = parse_note_content(content: .content("the #at@sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "at")
        XCTAssertEqual(parsed[2].asText, "@sign is not allowed")
    }
    
    func testHashtagWithDollarSign() {
        let parsed = parse_note_content(content: .content("the #dollar$sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "dollar")
        XCTAssertEqual(parsed[2].asText, "$sign is not allowed")
    }
    
    func testHashtagWithPercentSign() {
        let parsed = parse_note_content(content: .content("the #percent%sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "percent")
        XCTAssertEqual(parsed[2].asText, "%sign is not allowed")
    }
    
    func testHashtagWithCaret() {
        let parsed = parse_note_content(content: .content("the #caret^ is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "caret")
        XCTAssertEqual(parsed[2].asText, "^ is not allowed")
    }
    
    func testHashtagWithAmpersand() {
        let parsed = parse_note_content(content: .content("the #ampersand& is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "ampersand")
        XCTAssertEqual(parsed[2].asText, "& is not allowed")
    }
    
    func testHashtagWithAsterisk() {
        let parsed = parse_note_content(content: .content("the #asterisk* is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "asterisk")
        XCTAssertEqual(parsed[2].asText, "* is not allowed")
    }
    
    func testHashtagWithLeftParenthesis() {
        let parsed = parse_note_content(content: .content("the #left(parenthesis is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "left")
        XCTAssertEqual(parsed[2].asText, "(parenthesis is not allowed")
    }
    
    func testHashtagWithRightParenthesis() {
        let parsed = parse_note_content(content: .content("the #right)parenthesis is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "right")
        XCTAssertEqual(parsed[2].asText, ")parenthesis is not allowed")
    }
    
    func testHashtagWithDash() {
        let parsed = parse_note_content(content: .content("the #dash- is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "dash")
        XCTAssertEqual(parsed[2].asText, "- is not allowed")
    }
    
    func testHashtagWithPlusSign() {
        let parsed = parse_note_content(content: .content("the #plus+sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "plus")
        XCTAssertEqual(parsed[2].asText, "+sign is not allowed")
    }
    
    func testHashtagWithEqualsSign() {
        let parsed = parse_note_content(content: .content("the #equals=sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "equals")
        XCTAssertEqual(parsed[2].asText, "=sign is not allowed")
    }
    
    func testHashtagWithLeftBracket() {
        let parsed = parse_note_content(content: .content("the #left[bracket is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "left")
        XCTAssertEqual(parsed[2].asText, "[bracket is not allowed")
    }
    
    func testHashtagWithRightBracket() {
        let parsed = parse_note_content(content: .content("the #right]bracket is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "right")
        XCTAssertEqual(parsed[2].asText, "]bracket is not allowed")
    }
    
    func testHashtagWithLeftBrace() {
        let parsed = parse_note_content(content: .content("the #left{brace is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "left")
        XCTAssertEqual(parsed[2].asText, "{brace is not allowed")
    }
    
    func testHashtagWithRightBrace() {
        let parsed = parse_note_content(content: .content("the #right}brace is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "right")
        XCTAssertEqual(parsed[2].asText, "}brace is not allowed")
    }
    
    func testHashtagWithBackslash() {
        let parsed = parse_note_content(content: .content("the #back\\slash is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "back")
        XCTAssertEqual(parsed[2].asText, "\\slash is not allowed")
    }
    
    func testHashtagWithVerticalLine() {
        let parsed = parse_note_content(content: .content("the #vertical|line is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "vertical")
        XCTAssertEqual(parsed[2].asText, "|line is not allowed")
    }
    
    func testHashtagWithSemicolon() {
        let parsed = parse_note_content(content: .content("the #semicolon; is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "semicolon")
        XCTAssertEqual(parsed[2].asText, "; is not allowed")
    }
    
    func testHashtagWithColon() {
        let parsed = parse_note_content(content: .content("the #colon: is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "colon")
        XCTAssertEqual(parsed[2].asText, ": is not allowed")
    }
    
    func testHashtagWithApostrophe() {
        let parsed = parse_note_content(content: .content("the #apostrophe' is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "apostrophe")
        XCTAssertEqual(parsed[2].asText, "' is not allowed")
    }
    
    func testHashtagWithQuotationMark() {
        let parsed = parse_note_content(content: .content("the #quotation\"mark is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "quotation")
        XCTAssertEqual(parsed[2].asText, "\"mark is not allowed")
    }
    
    func testHashtagWithLessThanSign() {
        let parsed = parse_note_content(content: .content("the #lessthan<sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "lessthan")
        XCTAssertEqual(parsed[2].asText, "<sign is not allowed")
    }
    
    func testHashtagWithGreaterThanSign() {
        let parsed = parse_note_content(content: .content("the #greaterthan>sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "greaterthan")
        XCTAssertEqual(parsed[2].asText, ">sign is not allowed")
    }
    
    //------------------------------------------------------------
    // Test Unicode (UTF-8)
    //------------------------------------------------------------
    
    // Test UTF-8 Latin-1 Supplement Punctuation: U+00A1 to U+00BF (not allowed)
    
    // Test pound sign (£) (U+00A3)
    func testHashtagWithPoundSign() {
        let parsed = parse_note_content(content: .content("the #pound£sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "pound")
        XCTAssertEqual(parsed[2].asText, "£sign is not allowed")
    }
    
    // Test yen sign (¥) (U+00A5)
    func testHashtagWithYenSign() {
        let parsed = parse_note_content(content: .content("the #yen¥sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "yen")
        XCTAssertEqual(parsed[2].asText, "¥sign is not allowed")
    }
    
    // Test section sign (§) (U+00A7)
    func testHashtagWithSectionSign() {
        let parsed = parse_note_content(content: .content("the #section§sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "section")
        XCTAssertEqual(parsed[2].asText, "§sign is not allowed")
    }
    
    // Test plus-minus sign (±) (U+00B1)
    func testHashtagWithPlusMinusSign() {
        let parsed = parse_note_content(content: .content("the #plusminus±sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "plusminus")
        XCTAssertEqual(parsed[2].asText, "±sign is not allowed")
    }
    
    // Test inverted question mark (¿) (U+00BF)
    func testHashtagWithInvertedQuestionMark() {
        let parsed = parse_note_content(content: .content("the #invertedquestion¿mark is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "invertedquestion")
        XCTAssertEqual(parsed[2].asText, "¿mark is not allowed")
    }
    
    // Test UTF-8 Latin-1 Supplement Non-Punctuation: U+00C0 to U+00FF (allowed)
    
    // Test Latin small letter u with diaeresis (ü) (U+00FC) (allowed in hashtags)
    func testHashtagWithAccents() {
        let parsed = parse_note_content(content: .content("hello from #türkiye",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].asText, "hello from ")
        XCTAssertEqual(parsed[1].asHashtag, "türkiye")
    }
    
    // Test UTF-8 General Punctuation: U+2000 to U+206F (not allowed in hashtags)
    
    // Test en dash (–) (U+2013)
    func testHashtagWithEnDash() {
        let parsed = parse_note_content(content: .content("the #en–dash is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "en")
        XCTAssertEqual(parsed[2].asText, "–dash is not allowed")
    }
    
    // Test em dash (—) (U+2014)
    func testHashtagWithEmDash() {
        let parsed = parse_note_content(content: .content("the #em—dash is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "em")
        XCTAssertEqual(parsed[2].asText, "—dash is not allowed")
    }
    
    // Test horizontal bar (―) (U+2015)
    func testHashtagWithHorizontalBar() {
        let parsed = parse_note_content(content: .content("the #horizontal―bar is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "horizontal")
        XCTAssertEqual(parsed[2].asText, "―bar is not allowed")
    }
    
    // Test horizontal ellipsis (…) (U+2026)
    func testHashtagWithHorizontalEllipsis() {
        let parsed = parse_note_content(content: .content("the #horizontal…ellipsis is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "horizontal")
        XCTAssertEqual(parsed[2].asText, "…ellipsis is not allowed")
    }
    
    // Test UTF-8 Currency Symbols: U+20A0 to U+20CF (not allowed in hashtags)
    
    // Test euro sign (€) (U+20AC)
    func testHashtagWithEuroSign() {
        let parsed = parse_note_content(content: .content("the #euro€sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "euro")
        XCTAssertEqual(parsed[2].asText, "€sign is not allowed")
    }
    
    // Test Bitcoin sign (₿) (U+20BF)
    func testHashtagWithBitcoinSign() {
        let parsed = parse_note_content(content: .content("the #bitcoin₿sign is not allowed",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "the ")
        XCTAssertEqual(parsed[1].asHashtag, "bitcoin")
        XCTAssertEqual(parsed[2].asText, "₿sign is not allowed")
    }
    
    // Test UTF-8 Miscellaneous Symbols: U+2600 to U+26FF (allowed in hashtags)
    
    // Emojis such as ☕️ (U+2615) are allowed in hashtags
    func testHashtagWithEmoji() {
        let content = "some hashtag #bitcoin☕️ cool"
        let parsed = parse_note_content(content: .content(content, nil))!.blocks
        let post_blocks = parse_post_blocks(content: content)!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "some hashtag ")
        XCTAssertEqual(parsed[1].asHashtag, "bitcoin☕️")
        XCTAssertEqual(parsed[2].asText, " cool")

        XCTAssertEqual(post_blocks.count, 3)
        XCTAssertEqual(post_blocks[0].asText, "some hashtag ")
        XCTAssertEqual(post_blocks[1].asHashtag, "bitcoin☕️")
        XCTAssertEqual(post_blocks[2].asText, " cool")
    }
    
    // Test international Unicode (UTF-8) characters
    
    // Japanese: wave dash (〜) (U+301C) (allowed in hashtags)
    func testPowHashtag() {
        let content = "pow! #ぽわ〜"
        let parsed = parse_note_content(content: .content(content,nil))!.blocks
        let post_blocks = parse_post_blocks(content: content)!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].asText, "pow! ")
        XCTAssertEqual(parsed[1].asHashtag, "ぽわ〜")

        XCTAssertEqual(post_blocks.count, 2)
        XCTAssertEqual(post_blocks[0].asText, "pow! ")
        XCTAssertEqual(post_blocks[1].asHashtag, "ぽわ〜")
    }
    
    // Hangul: Hangul Syllable Si (시) (U+C2DC) and
    // Hangul Syllable Heom (험) (U+D5D8) (allowed in hashtags)
    func testHashtagWithNonLatinCharacters() {
        let parsed = parse_note_content(content: .content("this is a #시험 hope it works",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "this is a ")
        XCTAssertEqual(parsed[1].asHashtag, "시험")
        XCTAssertEqual(parsed[2].asText, " hope it works")
    }
    
    // Japanese: fullwidth tilde (～) (U+FF5E) (allowed in hashtags)
    func testHashtagWithFullwidthTilde() {
        let parsed = parse_note_content(content: .content("pow! the fullwidth tilde #ぽわ～ is allowed in hashtags",nil))!.blocks

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "pow! the fullwidth tilde ")
        XCTAssertEqual(parsed[1].asHashtag, "ぽわ～")
        XCTAssertEqual(parsed[2].asText, " is allowed in hashtags")
    }
    
    // Japanese: bai (倍) (U+500D) (allowed in hashtags)
    func testHashtagWithBaiKanji() {
        let parsed = parse_note_content(content: .content("pow! #10倍界王拳 is allowed in hashtags",nil))!.blocks
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].asText, "pow! ")
        XCTAssertEqual(parsed[1].asHashtag, "10倍界王拳")
        XCTAssertEqual(parsed[2].asText, " is allowed in hashtags")
    }

}
