//
//  Block+Tests.swift
//  damusTests
//
//  Created by Kyle Roucis on 9/1/23.
//

import Foundation
@testable import damus


extension Block {
    var asText: String? {
        switch self {
        case .text(let text):
            return text
        default:
            return nil
        }
    }
    
    var isText: Bool {
        return self.asText != nil
    }
    
    var asURL: URL? {
        switch self {
        case .url(let url):
            return url
        default:
            return nil
        }
    }
    
    var isURL: Bool {
        return self.asURL != nil
    }
    
    var asMention: Mention<MentionRef>? {
        switch self {
        case .mention(let mention):
            return mention
        default:
            return nil
        }
    }
    
    var asHashtag: String? {
        switch self {
        case .hashtag(let hashtag):
            return hashtag
        default:
            return nil
        }
    }
}
