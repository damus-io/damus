//
//  InvoiceTests.swift
//  damusTests
//
//  Created by William Casarin on 2022-10-18.
//

import XCTest
@testable import damus


final class InvoiceTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    
    func testParseAnyAmountInvoice() throws {
        let invstr = "LNBC1P3MR5UJSP5G7SA48YD4JWTTPCHWMY4QYN4UWZQCJQ8NMWKD6QE3HCRVYTDLH9SPP57YM9TSA9NN4M4XU59XMJCXKR7YDV29DDP6LVQUT46ZW6CU3KE9GQDQ9V9H8JXQ8P3MYLZJCQPJRZJQF60PZDVNGGQWQDNERZSQN35L8CVQ3QG2Z5NSZYD0D3Q0JW2TL6VUZA7FYQQWKGQQYQQQQLGQQQQXJQQ9Q9QXPQYSGQ39EM4QJMQFKZGJXZVGL7QJMYNSWA8PGDTAGXXRG5Z92M7VLCGKQK2L2THDF8LM0AUKAURH7FVAWDLRNMVF38W4EYJDNVN9V4Z9CRS5CQCV465C"
        
        guard let blockGroup: NdbBlockGroup = try? NdbBlockGroup.parse(content: invstr) else {
            XCTFail("Parsing threw an error")
            return
        }
        
        blockGroup.withList({ blockList in
            XCTAssertEqual(blockList.count, 1)
            let success: Bool? = blockList.useItem(at: 0, { block in
                switch block {
                case .invoice(let invoiceData):
                    let invoice = invoiceData.as_invoice()
                    XCTAssertEqual(invoice.amount, .any)
                    XCTAssertEqual(invoice.string, invstr)
                    return true
                default:
                    XCTFail("Block is not an invoice")
                    return false
                }
            })
            XCTAssertEqual(success, true)
        })
    }
    
    /*
    // gh-3144: It was decided on a standup meeting that we do not need invoices to render, few people use this feature.
    func testTextAfterInvoice() throws {
        let invstr = """
    LNBC1P3MR5UJSP5G7SA48YD4JWTTPCHWMY4QYN4UWZQCJQ8NMWKD6QE3HCRVYTDLH9SPP57YM9TSA9NN4M4XU59XMJCXKR7YDV29DDP6LVQUT46ZW6CU3KE9GQDQ9V9H8JXQ8P3MYLZJCQPJRZJQF60PZDVNGGQWQDNERZSQN35L8CVQ3QG2Z5NSZYD0D3Q0JW2TL6VUZA7FYQQWKGQQYQQQQLGQQQQXJQQ9Q9QXPQYSGQ39EM4QJMQFKZGJXZVGL7QJMYNSWA8PGDTAGXXRG5Z92M7VLCGKQK2L2THDF8LM0AUKAURH7FVAWDLRNMVF38W4EYJDNVN9V4Z9CRS5CQCV465C  hi there
    """
        
        guard let blockGroup: NdbBlockGroup = try? NdbBlockGroup.parse(content: invstr) else {
            XCTFail("Parsing threw an error")
            return
        }
        
        blockGroup.withList({ blockList in
            XCTAssertEqual(blockList.count, 2)
            
            // Check invoice block
            let invoiceSuccess: Bool? = blockList.useItem(at: 0, { block in
                switch block {
                case .invoice(let invoiceData):
                    guard let invoice = invoiceData.as_invoice() else {
                        XCTFail("Cannot get invoice from invoice block")
                        return false
                    }
                    XCTAssertEqual(invoice.amount, .any)
                    return true
                default:
                    XCTFail("First block is not an invoice")
                    return false
                }
            })
            XCTAssertEqual(invoiceSuccess, true)
            
            // Check text block
            let textSuccess: Bool? = blockList.useItem(at: 1, { block in
                switch block {
                case .text(let text):
                    XCTAssertEqual(text.as_str(), "  hi there")
                    return true
                default:
                    XCTFail("Second block is not text")
                    return false
                }
            })
            XCTAssertEqual(textSuccess, true)
        })
    }
     */
    
    func testParseInvoiceUpper() throws {
        let invstr = "LNBC100N1P357SL0SP5T9N56WDZTUN39LGDQLR30XQWKSG3K69Q4Q2RKR52APLUJW0ESN0QPP5MRQGLJK62Z20Q4NVGR6LZCYN6FHYLZCCWDVU4K77APG3ZMRKUJJQDPZW35XJUEQD9EJQCFQV3JHXCMJD9C8G6T0DCXQYJW5QCQPJRZJQT56H4GVP5YX36U2UZQA6QWCSK3E2DUUNFXPPZJ9VHYPC3WFE2WSWZ607UQQ3XQQQSQQQQQQQQQQQLQQYG9QYYSGQAGX5H20AEULJ3GDWX3KXS8U9F4MCAKDKWUAKASAMM9562FFYR9EN8YG20LG0YGNR9ZPWP68524KMDA0T5XP2WYTEX35PU8HAPYJAJXQPSQL29R"
        
        guard let blockGroup: NdbBlockGroup = try? NdbBlockGroup.parse(content: invstr) else {
            XCTFail("Parsing threw an error")
            return
        }
        
        blockGroup.withList({ blockList in
            XCTAssertEqual(blockList.count, 1)
            let success: Bool? = blockList.useItem(at: 0, { block in
                switch block {
                case .invoice(let invoiceData):
                    let invoice = invoiceData.as_invoice()
                    XCTAssertEqual(invoice.amount, .specific(10000))
                    XCTAssertEqual(invoice.expiry, 604800)
                    XCTAssertEqual(invoice.created_at, 1666139119)
                    XCTAssertEqual(invoice.string, invstr)
                    return true
                default:
                    XCTFail("Block is not an invoice")
                    return false
                }
            })
            XCTAssertEqual(success, true)
        })
    }

    func testParseInvoiceWithPrefix() throws {
        let invstr = "lightning:lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r"
        
        guard let blockGroup: NdbBlockGroup = try? NdbBlockGroup.parse(content: invstr) else {
            XCTFail("Parsing threw an error")
            return
        }
        
        blockGroup.withList({ blockList in
            XCTAssertEqual(blockList.count, 1)
            let success: Bool? = blockList.useItem(at: 0, { block in
                switch block {
                case .invoice(_):
                    return true
                default:
                    XCTFail("Block is not an invoice")
                    return false
                }
            })
            XCTAssertEqual(success, true)
        })
    }
    
    func testParseInvoiceWithPrefixCapitalized() throws {
        let invstr = "LIGHTNING:LNBC100N1P357SL0SP5T9N56WDZTUN39LGDQLR30XQWKSG3K69Q4Q2RKR52APLUJW0ESN0QPP5MRQGLJK62Z20Q4NVGR6LZCYN6FHYLZCCWDVU4K77APG3ZMRKUJJQDPZW35XJUEQD9EJQCFQV3JHXCMJD9C8G6T0DCXQYJW5QCQPJRZJQT56H4GVP5YX36U2UZQA6QWCSK3E2DUUNFXPPZJ9VHYPC3WFE2WSWZ607UQQ3XQQQSQQQQQQQQQQQLQQYG9QYYSGQAGX5H20AEULJ3GDWX3KXS8U9F4MCAKDKWUAKASAMM9562FFYR9EN8YG20LG0YGNR9ZPWP68524KMDA0T5XP2WYTEX35PU8HAPYJAJXQPSQL29R"
        
        guard let blockGroup: NdbBlockGroup = try? NdbBlockGroup.parse(content: invstr) else {
            XCTFail("Parsing threw an error")
            return
        }
        
        blockGroup.withList({ blockList in
            XCTAssertEqual(blockList.count, 1)
            let success: Bool? = blockList.useItem(at: 0, { block in
                switch block {
                case .invoice(_):
                    return true
                default:
                    XCTFail("Block is not an invoice")
                    return false
                }
            })
            XCTAssertEqual(success, true)
        })
    }

    /// Test parsing the specific invoice from GitHub issue that wasn't rendering
    func testParseSpecificFailingInvoice() throws {
        let invstr = "lnbc130n1p5h7alnpp5f83swv5wx9h25ansxsvkw7364c65vxktthy2m9ww5zf3cjrzp0vsdq9tfpygcqzysxqzjcsp5essuf0xnfeu4rpw7nllcggr6e9635xdpnaklr2fadtkwej0vvyfs9qxpqysgqddjjzxa2dwhntx8uvppx3u6pu864ul5dxkayp6jgf7n45ql5x7u9xzrvuav5rzsaz7h8d2gq455je2ezku40a5xrshu0w00ylprk03qq6kvvjd"

        guard let blockGroup: NdbBlockGroup = try? NdbBlockGroup.parse(content: invstr) else {
            XCTFail("Parsing threw an error")
            return
        }

        blockGroup.withList({ blockList in
            XCTAssertEqual(blockList.count, 1, "Expected 1 block, got \(blockList.count)")
            let success: Bool? = blockList.useItem(at: 0, { block in
                switch block {
                case .invoice(let invoiceData):
                    let invoice = invoiceData.as_invoice()
                    XCTAssertEqual(invoice.amount, .specific(13000))
                    return true
                case .text(let txt):
                    XCTFail("Expected invoice block, got text block")
                    return false
                default:
                    XCTFail("Block is not an invoice")
                    return false
                }
            })
            XCTAssertEqual(success, true)
        })
    }

    // MARK: - Invoice parsing tests for issue #3456 (MAX_PREFIX fix)
    // These test invoices with longer HRP prefixes that require MAX_PREFIX > 10

    /// Test invoice from gh-3456: 10,000 sats (100 micro-BTC)
    /// HRP: lnbc100u (7 chars) - should work with old MAX_PREFIX
    func testParseInvoice_gh3456_100u() throws {
        let invstr = "lnbc100u1p55gjvwpp5fgrv9nq4y5turswulpym74rm2q7jnwvqzqr90y4m7xrjyu8025vshp5jxmcdmqe5kp7kcmsngxxejshcqe5pglk5w9rjgk5ltqc3ada5wlscqzzsxqyz5vqsp5f358u7jquhy20cpxq9r6kspcsd46ksgns0zrx028x2csat2cqzrs9qxpqysgqzwsxjn7wmwc2n9yl3h3pu4ph9mma2w7q6f7h8xxhql0d9nxu90087jru6e30t79l6d70rcphsa65kzw6l5kzz2njr777e8e2m80l4ygqjw8mm3"

        guard let invoice = decode_bolt11(invstr) else {
            XCTFail("Failed to decode invoice - MAX_PREFIX may be too small")
            return
        }

        // 100 micro-BTC = 10,000 sats = 10,000,000 millisats
        XCTAssertEqual(invoice.amount, .specific(10_000_000))
    }

    /// Test invoice from gh-3456: 13,013 sats (130130 nano-BTC)
    /// HRP: lnbc130130n (11 chars) - requires MAX_PREFIX > 10
    func testParseInvoice_gh3456_130130n() throws {
        let invstr = "lnbc130130n1p5h77tgpp5edwq8elur9e66vhd7wf0s75p20hvppna49dsrchel6xkq69tm4aqdq4w3jhxapqvehhygrzda68xcqzzsxqyz5vqsp56cdkune763pdxqy0jk44hhmv784jzf9m8mk8wspyngq2etehadps9qxpqysgquhrggc6a654gyelax0tcqd9gc9hyajt39t8wksgv0n0jy7q95l4htvgqsydz4fvdlgwa72xqddynsy6k3zq0tmhnxva0dfkhcxduh6gpyl0rgn"

        guard let invoice = decode_bolt11(invstr) else {
            XCTFail("Failed to decode invoice - MAX_PREFIX may be too small for 11-char HRP")
            return
        }

        // 130130 nano-BTC = 13,013 sats = 13,013,000 millisats
        XCTAssertEqual(invoice.amount, .specific(13_013_000))
    }

    // Note: Tests for lnbc23450n (2345 sats) and lnbc19710n (1971 sats) would require
    // real invoice strings. The testParseInvoice_gh3456_130130n test above covers
    // the 11-char HRP case which exercises the MAX_PREFIX fix more thoroughly than
    // 10-char HRPs would. If specific test invoices become available, add tests here.

    /*
    // gh-3144: It was decided on a standup meeting that we do not need invoices to render, few people use this feature.
    func testParseInvoice() throws {
        let invstr = " lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r"

        guard let blockGroup: NdbBlockGroup = try? NdbBlockGroup.parse(content: invstr) else {
            XCTFail("Parsing threw an error")
            return
        }
        blockGroup.withList({ blockList in
            XCTAssertEqual(blockList.count, 3)
            let success: Bool? = blockList.useItem(at: 1, { block in
                switch block {
                case .invoice(let invoiceData):
                    guard let invoice = invoiceData.as_invoice() else {
                        XCTFail("Cannot get invoice from invoice block")
                        return false
                    }
                    XCTAssertEqual(invoice.amount, .specific(10000))
                    XCTAssertEqual(invoice.expiry, 604800)
                    XCTAssertEqual(invoice.created_at, 1666139119)
                    XCTAssertEqual(invoice.string, invstr)
                    return true
                default:
                    XCTFail("Block is not an invoice")
                    return false
                }
            })
            XCTAssertEqual(success, true)
        })
    }
    */
    
    /// Tests decoding a BOLT11 invoice using the decode_bolt11 function
    func testDecodeBolt11Invoice() throws {
        let invstr = "lnbc19710n1p5czpejsp5rmhun0ghrzv9ce0whqn3q2ll8y5kql8mgad90kxlq2zuq784wwuqpp53ks03npkdadza0c8r0qrsgypfx7wsrtr90pqxsgzpcw8yf3358uqhp5vc0usy5w5clt4xwdu6txzgyuxcnyuyd2r6f8ncjacvzrzxtvg50sxq9z0rgqcqpnrzjqt0mfswatysklf4z358sztscs5t0vdghmd5vfe9c9sa0gy6r5pdugrjqtsqqdtcqqyqqqqqqqqqqdpsq8s9qxpqysgq59ja4yg7ayty0cu8etja0unme76d4lm6crzsw5g9uj3h5748xcypwf4ahgyut7vegpz4a6jvq7lj5p8zqutaznjrxgcgnuwejm8cwtsqgzcx97"
        
        // Try decoding with lowercase (standard format)
        var invoice = decode_bolt11(invstr)
        
        // If lowercase fails, try uppercase
        if invoice == nil {
            invoice = decode_bolt11(invstr.uppercased())
        }
        
        guard let decodedInvoice = invoice else {
            XCTFail("Failed to decode BOLT11 invoice with both lowercase and uppercase")
            return
        }
        
        // Verify that the invoice was successfully decoded
        XCTAssertNotNil(decodedInvoice)
        
        // Verify the invoice has a specific amount (19710 nanosatoshis in the invoice string)
        // Note: The amount is encoded as 1971 * 10 = 19710 nanosatoshis = 1,971,000 millisatoshis
        switch decodedInvoice.amount {
        case .specific(let amount):
            XCTAssertGreaterThan(amount, 0, "Invoice amount should be greater than 0")
        case .any:
            XCTFail("Expected specific amount, got .any")
        }
        
        // Verify basic invoice properties exist
        XCTAssertGreaterThan(decodedInvoice.created_at, 0)
        XCTAssertGreaterThan(decodedInvoice.expiry, 0)
    }

}
