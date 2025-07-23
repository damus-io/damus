//
//  Hashtags.swift
//  damus
//
//  Created by William Casarin on 2023-04-06.
//

import Foundation
import SwiftUI

struct CustomHashtag {
    let name: String
    let offset: CGFloat?
    let color: Color?
    
    init(name: String, color: Color? = nil, offset: CGFloat? = nil) {
        self.name = name
        self.color = color
        self.offset = offset
    }
    
    static let coffee = CustomHashtag(name: "coffee", color: DamusColors.brown, offset: -1.0)
    static let bitcoin = CustomHashtag(name: "bitcoin", color: Color.orange, offset: -3.0)
    static let nostr = CustomHashtag(name: "nostr", color: DamusColors.purple, offset: -2.0)
    static let plebchain = CustomHashtag(name: "plebchain", color: DamusColors.deepPurple, offset: -3.0)
    static let zap = CustomHashtag(name: "zap", color: DamusColors.yellow, offset: -4.0)
}


let custom_hashtags: [String: CustomHashtag] = [
    "bitcoin": CustomHashtag.bitcoin,
    "btc": CustomHashtag.bitcoin,
    "nostr": CustomHashtag.nostr,
    "coffee": CustomHashtag.coffee,
    "coffeechain": CustomHashtag.coffee,
    "plebchain": CustomHashtag.plebchain,
    "zap": CustomHashtag.zap,
    "zaps": CustomHashtag.zap,
    "zapathon": CustomHashtag.zap,
    "onlyzaps": CustomHashtag.zap,
]

func hashtag_str(_ htag: String) -> CompatibleText {
    var attributedString = AttributedString(stringLiteral: "#\(htag)")
    attributedString.link = URL(string: "damus:t:\(htag.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? htag)")

    let lowertag = htag.lowercased()

    if let custom_hashtag = custom_hashtags[lowertag] {
        if let col = custom_hashtag.color {
            attributedString.foregroundColor = col
        }

        let name = custom_hashtag.name

        attributedString = attributedString + " "
        return CompatibleText(items: [.attributed_string(attributedString), .icon(named: "\(name)-hashtag", offset: custom_hashtag.offset ?? 0.0)])
    } else {
        attributedString.foregroundColor = DamusColors.purple
        return CompatibleText(items: [.attributed_string(attributedString)])
    }
 }
