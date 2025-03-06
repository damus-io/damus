//
//  DamusParseContentTests.swift
//  damusTests
//
//  Created by Joshua Jiang on 4/15/23.
//

import XCTest
@testable import damus

class ContentParserTests: XCTestCase {
    
    private let decoder = JSONDecoder()
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_url_parsing_with_emoji() throws {
        let url = "https://media.tenor.com/5MibLt95scAAAAAC/%ED%98%BC%ED%8C%8C%EB%A7%9D-%ED%94%BC%EC%9E%90.gif"
        let content = "gm 🤙\(url)"

        let blocks = parse_note_content(content: .content(content,nil))!.blocks
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], .text("gm 🤙"))
        XCTAssertEqual(blocks[1], .url(URL(string: url)!))
    }


    /*
    func test_damus_parse_content_can_parse_mention_without_white_space_at_front() throws {
        var bs = note_blocks()
        bs.num_blocks = 0;
        
        blocks_init(&bs)
        
        let content = "#[0]​, #[1]​,#[2]​,#[3]#[4]​,#[5]​,#[6]​,#[7]​, #[8]​, \n#[9]​, #[10]​, #[11]​, #[12]​"

        let tagsString = "[[\"p\",\"82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2\"],[\"p\",\"0339bb0d9d818ba126a39385a5edee5651993af7c21f18d4ceb0ba8c9de0d463\"],[\"p\",\"e7424ad457e512fdf4764a56bf6d428a06a13a1006af1fb8e0fe32f6d03265c7\"],[\"p\",\"520830c334a3f79f88cac934580d26f91a7832c6b21fb9625690ea2ed81b5626\"],[\"p\",\"971615b70ad9ec896f8d5ba0f2d01652f1dfe5f9ced81ac9469ca7facefad68b\"],[\"p\",\"2779f3d9f42c7dee17f0e6bcdcf89a8f9d592d19e3b1bbd27ef1cffd1a7f98d1\"],[\"p\",\"17538dc2a62769d09443f18c37cbe358fab5bbf981173542aa7c5ff171ed77c4\"],[\"p\",\"985a7c6b0e75508ad74c4110b2e52dfba6ce26063d80bca218564bd083a72b99\"],[\"p\",\"7fb2a29bd1a41d9a8ca43a19a7dcf3a8522f1bc09b4086253539190e9c29c51a\"],[\"p\",\"b88c7f007bbf3bc2fcaeff9e513f186bab33782c0baa6a6cc12add78b9110ba3\"],[\"p\",\"2f4fa408d85b962d1fe717daae148a4c98424ab2e10c7dd11927e101ed3257b2\"],[\"p\",\"bd1e19980e2c91e6dc657e92c25762ca882eb9272d2579e221f037f93788de91\"],[\"p\",\"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245\"]]"
        
        let tags = try decoder.decode([[String]].self, from: tagsString.data(using: .utf8)!)
        
        let bytes = content.utf8CString
        
        let _ = bytes.withUnsafeBufferPointer { p in
            damus_parse_content(&bs, p.baseAddress)
        }
        
        let isMentionBlockIndexList = [0,2,4,6,7,9,11,13,15,17,19,21,23]
        let isMentionBlockSet = Set(isMentionBlockIndexList)
        

        
        var i = 0
        while (i < bs.num_blocks) {
            let block = bs.blocks[i]
            
            guard let currentBlock = convert_block(block, tags: tags) else {
                XCTFail("Cannot parse block")
                return
            }
            
            if currentBlock.is_mention != nil {
                XCTAssert(isMentionBlockSet.contains(i))
            } else {
                XCTAssert(!isMentionBlockSet.contains(i))
            }
            
            i += 1
        }
    }
     */
}
