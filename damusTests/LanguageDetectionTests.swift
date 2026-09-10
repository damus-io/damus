//
//  LanguageDetectionTests.swift
//  damusTests
//
//  Created for testing language detection false positives.
//

import XCTest
import NaturalLanguage
@testable import damus

final class LanguageDetectionTests: XCTestCase {

    // 107 sample texts: (text, isEnglish, expectedLangs)
    //
    // English texts should be detected as "en" or nil, never as a foreign language.
    // Foreign texts should be detected as a non-English language. When expectedLangs
    // is non-empty, the detected language must be in that set (accounts for closely
    // related languages that NLLanguageRecognizer may confuse, e.g. ru/bg/uk).
    //
    // The English set includes 28 phrases confirmed to trigger false positives
    // under the old single-hypothesis 50% threshold logic on iOS 26.2.
    static let sampleTexts: [(text: String, isEnglish: Bool, expectedLangs: Set<String>)] = [

        // -- Confirmed false positives under old logic (28 samples) --
        // Each of these is English but NLLanguageRecognizer's top hypothesis
        // at >= 50% confidence is a non-English language.
        ("gut",                          true, []),  // → de 98%
        ("vast",                         true, []),  // → nl 93%
        ("hat",                          true, []),  // → de 91%
        ("ez",                           true, []),  // → hu 90%
        ("W",                            true, []),  // → pl 87%
        ("cap",                          true, []),  // → ca 83%
        ("sus",                          true, []),  // → es 82%
        ("cope",                         true, []),  // → es 81%
        ("no cap",                       true, []),  // → ca 81%
        ("no me",                        true, []),  // → es 81%
        ("nah",                          true, []),  // → id 79%
        ("don\u{2019}t care",            true, []),  // → ro 79%
        ("it\u{2019}s joever",           true, []),  // → nl 72%
        ("idk",                          true, []),  // → id 70%
        ("ya know",                      true, []),  // → id 69%
        ("vet",                          true, []),  // → nb 65%
        ("halt",                         true, []),  // → de 65%
        ("nice one",                     true, []),  // → id 62%
        ("You\u{2019}re funner",         true, []),  // → nb 61%
        ("water",                        true, []),  // → nl 58%
        ("secular",                      true, []),  // → es 56%
        ("slim",                         true, []),  // → tr 56%
        ("stem",                         true, []),  // → nl 55%
        ("gn gn",                        true, []),  // → id 54%
        ("menu",                         true, []),  // → id 54%
        ("game over",                    true, []),  // → nl 53%
        ("general",                      true, []),  // → es 51%
        ("gm frens",                     true, []),  // → ca 51%

        // -- Additional short English (22 samples) --
        ("good morning",                 true, []),
        ("gm",                           true, []),
        ("hello",                        true, []),
        ("thanks",                       true, []),
        ("let\u{2019}s go",              true, []),
        ("LFG",                          true, []),
        ("GM",                           true, []),
        ("GN",                           true, []),
        ("It\u{2019}s a meme",           true, []),
        ("sure thing",                   true, []),
        ("sounds good",                  true, []),
        ("that\u{2019}s cool",           true, []),
        ("love this",                    true, []),
        ("great post",                   true, []),
        ("well said",                    true, []),
        ("based",                        true, []),
        ("this is the way",              true, []),
        ("facts",                        true, []),
        ("probably nothing",             true, []),
        ("don\u{2019}t trust, verify",   true, []),
        ("have fun staying poor",        true, []),
        ("stack sats",                   true, []),

        // -- Medium/longer English (20 samples) --
        ("I just had the best coffee this morning", true, []),
        ("Bitcoin is going to change the world",    true, []),
        ("Has anyone tried the new update?",        true, []),
        ("This is why I love Nostr",                true, []),
        ("The weather is beautiful today",          true, []),
        ("Just deployed a new version of my app",   true, []),
        ("Happy birthday! Hope you have a great day", true, []),
        ("I\u{2019}ve been thinking about this for a while", true, []),
        ("Check out this amazing sunset",           true, []),
        ("Bitcoin fixes this lol",                  true, []),
        ("Not your keys, not your coins",           true, []),
        ("Does anyone else feel this way?",         true, []),
        ("I can\u{2019}t believe it\u{2019}s already March", true, []),
        ("Nostr is the super app. Because it\u{2019}s actually an ecosystem of apps, all of which make each other better.", true, []),
        ("I think the problem with social media is that it incentivizes outrage over thoughtful discussion.", true, []),
        ("Just finished reading a great book about the history of cryptography. Highly recommend it.", true, []),
        ("The best part about open protocols is that anyone can build on them without asking for permission.", true, []),
        ("I spent the whole weekend working on this project and I\u{2019}m really happy with how it turned out.", true, []),
        ("The internet was supposed to decentralize power but instead it concentrated it in a few companies.", true, []),
        ("Running a relay is one of the most impactful things you can do for the Nostr network right now.", true, []),

        // -- Short foreign texts (7 samples, all < 11 chars) --
        // These exercise the non-Latin script bypass in the short-text guard.
        // expectedLangs allows related scripts the recognizer may confuse.
        ("Привет",       false, ["ru", "bg", "uk"]),  // Cyrillic, 6 chars
        ("こんにちは",       false, ["ja"]),              // Japanese, 5 chars
        ("你好",           false, ["zh"]),              // Chinese, 2 chars
        ("مرحبا",          false, ["ar", "ur"]),        // Arabic, 5 chars
        ("สวัสดี",          false, ["th"]),              // Thai, 6 chars
        ("안녕",           false, ["ko"]),              // Korean, 2 chars
        ("Γεια",          false, ["el"]),              // Greek, 4 chars

        // -- Foreign language texts (30 samples) --
        ("Bonjour, comment allez-vous aujourd\u{2019}hui?", false, ["fr"]),
        ("Ich bin ein Berliner und ich liebe diese Stadt",   false, ["de"]),
        ("Buenas noches a todos mis amigos",                 false, ["es"]),
        ("こんにちは、今日はいい天気ですね",                         false, ["ja"]),
        ("今天天气真好，出去走走吧",                               false, ["zh"]),
        ("Привет, как дела? Давно не виделись!",              false, ["ru"]),
        ("오늘 날씨가 정말 좋네요",                               false, ["ko"]),
        ("สวัสดีครับ วันนี้อากาศดีมาก",                        false, ["th"]),
        ("مرحبا، كيف حالك اليوم؟",                            false, ["ar"]),
        ("Bom dia! Tudo bem com você?",                      false, ["pt"]),
        ("Ciao, come stai? Tutto bene?",                     false, ["it"]),
        ("Merhaba, bugün hava çok güzel",                    false, ["tr"]),
        ("Hej, hur mår du idag?",                            false, ["sv"]),
        ("Hei, hvordan har du det i dag?",                   false, ["nb", "da"]),
        ("Tere, kuidas teil läheb?",                         false, ["fi", "et"]),
        ("Γεια σας, πώς είστε σήμερα;",                      false, ["el"]),
        ("Cześć, jak się masz dzisiaj?",                     false, ["pl"]),
        ("Ahoj, jak se máš dnes?",                           false, ["cs", "sk"]),
        ("Hallo, hoe gaat het met je?",                      false, ["nl"]),
        ("Xin chào, bạn khỏe không?",                       false, ["vi"]),
        ("La vie est belle quand on est libre",              false, ["fr"]),
        ("Das Leben ist schön wenn man frei ist",            false, ["de"]),
        ("La vida es bella cuando eres libre",               false, ["es", "ca"]),
        ("人生は自由であるとき美しい",                              false, ["ja"]),
        ("Жизнь прекрасна, когда ты свободен",               false, ["ru"]),
        ("인생은 자유로울 때 아름답다",                             false, ["ko"]),
        ("ชีวิตสวยงามเมื่อคุณเป็นอิสระ",                      false, ["th"]),
        ("الحياة جميلة عندما تكون حرا",                       false, ["ar"]),
        ("A vida é bela quando se é livre",                  false, ["pt"]),
        ("La vita è bella quando sei libero",                false, ["it"]),
    ]

    // MARK: - Tests

    /// Regression test: English phrases must not be detected as foreign.
    /// This test FAILS before the fix and PASSES after.
    ///
    /// Requires English locale because note_language() consults Locale.current
    /// for the hypothesis check on short text.
    func testShortEnglishPhrasesNotDetectedAsForeign() throws {
        try XCTSkipUnless(
            localeToLanguage(Locale.current.identifier) == "en",
            "Test requires English locale (Locale.current: \(Locale.current.identifier))"
        )
        let expectation = XCTestExpectation(description: "Language detection")

        DispatchQueue.global().async {
            var failures: [(text: String, detected: String)] = []

            for (text, isEnglish, _) in Self.sampleTexts {
                guard isEnglish else { continue }

                guard let event = NostrEvent(
                    content: text,
                    keypair: test_keypair,
                    createdAt: UInt32(Date().timeIntervalSince1970)
                ) else {
                    XCTFail("Could not create event for '\(text)'")
                    continue
                }

                let lang = event.note_language(test_keypair)

                // English text must return "en" or nil, never a foreign language.
                // Returning a foreign language causes the "translate note" button
                // to appear, which is the bug we are fixing.
                if let lang, lang != "en" {
                    failures.append((text: text, detected: lang))
                }
            }

            if !failures.isEmpty {
                let report = failures.map { "  '\($0.text)' → \($0.detected)" }.joined(separator: "\n")
                XCTFail("\(failures.count) English phrases falsely detected as foreign:\n\(report)")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30)
    }

    /// Foreign language texts must be detected as a non-English language.
    /// When expectedLangs is specified, the detected language must match.
    func testForeignTextsDetectedCorrectly() {
        let expectation = XCTestExpectation(description: "Language detection")

        DispatchQueue.global().async {
            var failures: [(text: String, detected: String?, reason: String)] = []

            for (text, isEnglish, expectedLangs) in Self.sampleTexts {
                guard !isEnglish else { continue }

                guard let event = NostrEvent(
                    content: text,
                    keypair: test_keypair,
                    createdAt: UInt32(Date().timeIntervalSince1970)
                ) else {
                    XCTFail("Could not create event for '\(text)'")
                    continue
                }

                let lang = event.note_language(test_keypair)

                if lang == "en" || lang == nil {
                    failures.append((text: text, detected: lang, reason: "detected as \(lang ?? "nil")"))
                } else if !expectedLangs.isEmpty, let lang, !expectedLangs.contains(lang) {
                    failures.append((text: text, detected: lang, reason: "expected \(expectedLangs) but got \(lang)"))
                }
            }

            if !failures.isEmpty {
                let report = failures.map { "  '\($0.text)' → \($0.reason)" }.joined(separator: "\n")
                XCTFail("\(failures.count) foreign phrases detected incorrectly:\n\(report)")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30)
    }

    /// Comparison report: prints old vs new detection side by side for all samples.
    ///
    /// Requires English locale because the false-positive/negative counts are
    /// relative to an English-speaking user.
    func testLanguageDetectionComparison() throws {
        try XCTSkipUnless(
            localeToLanguage(Locale.current.identifier) == "en",
            "Test requires English locale (Locale.current: \(Locale.current.identifier))"
        )
        let expectation = XCTestExpectation(description: "Comparison")

        DispatchQueue.global().async {
            var lines: [String] = []
            lines.append("\n=== LANGUAGE DETECTION BEFORE/AFTER COMPARISON ===")
            lines.append(self.padRow("Text", "Expect", "Old", "New", "Hypotheses"))
            lines.append(String(repeating: "-", count: 110))

            var falsePosBefore = 0
            var falsePosAfter = 0
            var falseNegBefore = 0
            var falseNegAfter = 0

            for (text, isEnglish, _) in Self.sampleTexts {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(text)
                let hyps = recognizer.languageHypotheses(withMaximum: 3)

                // Old logic: single top hypothesis >= 50%
                let oldResult: String? = {
                    guard let top = hyps.max(by: { $0.value < $1.value }),
                          top.value >= 0.5 else { return nil }
                    return localeToLanguage(top.key.rawValue)
                }()

                // New logic: call the actual shipped function
                let newResult: String? = {
                    guard let event = NostrEvent(
                        content: text,
                        keypair: test_keypair,
                        createdAt: UInt32(Date().timeIntervalSince1970)
                    ) else { return nil }
                    return event.note_language(test_keypair)
                }()

                let hypStr = hyps.sorted(by: { $0.value > $1.value })
                    .map { "\(localeToLanguage($0.key.rawValue) ?? "?"):\(String(format: "%.0f%%", $0.value * 100))" }
                    .joined(separator: " ")

                let expectStr = isEnglish ? "en" : "other"
                let oldStr = oldResult ?? "nil"
                let newStr = newResult ?? "nil"
                let textCol = String(text.prefix(41))
                lines.append(self.padRow(textCol, expectStr, oldStr, newStr, hypStr))

                if isEnglish {
                    if let o = oldResult, o != "en" { falsePosBefore += 1 }
                    if let n = newResult, n != "en" { falsePosAfter += 1 }
                } else {
                    if oldResult == "en" || oldResult == nil { falseNegBefore += 1 }
                    if newResult == "en" || newResult == nil { falseNegAfter += 1 }
                }
            }

            lines.append("\n=== SUMMARY ===")
            lines.append("False positives (English wrongly detected as foreign): \(falsePosBefore) before → \(falsePosAfter) after")
            lines.append("False negatives (foreign wrongly detected as English/nil): \(falseNegBefore) before → \(falseNegAfter) after")
            lines.append("Total samples: \(Self.sampleTexts.count)")

            for line in lines { print(line) }

            XCTAssertEqual(falsePosAfter, 0, "Expected zero false positives after fix")
            XCTAssertEqual(falseNegAfter, 0, "Expected zero false negatives after fix")

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 30)
    }

    private func padRow(_ text: String, _ expect: String, _ old: String, _ new: String, _ hyps: String) -> String {
        let col1 = text.padding(toLength: 42, withPad: " ", startingAt: 0)
        let col2 = expect.padding(toLength: 8, withPad: " ", startingAt: 0)
        let col3 = old.padding(toLength: 7, withPad: " ", startingAt: 0)
        let col4 = new.padding(toLength: 7, withPad: " ", startingAt: 0)
        return "\(col1) \(col2) \(col3) \(col4) \(hyps)"
    }
}
