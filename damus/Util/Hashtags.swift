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
    let display: String
    let offset: CGFloat?
    let color: Color?
    
    init(name: String, display: String, color: Color? = nil, offset: CGFloat? = nil) {
        self.name = name
        self.display = display
        self.color = color
        self.offset = offset
    }
}

let custom_hashtags: [String: CustomHashtag] = [
    "bitcoin": CustomHashtag(name: "bitcoin", display: "Bitcoin", color: Color.orange, offset: -3.0),
    "bitcoinwallet": CustomHashtag(name: "bitcoin", display: "Bitcoin", color: Color.orange, offset: -3.0),
    "bitcoinadoption": CustomHashtag(name: "bitcoin", display: "BitcoinAdoption", color: Color.orange, offset: -3.0),
    "bitcoinjungle": CustomHashtag(name: "bitcoin", display: "BitcoinJungle", color: Color.orange, offset: -3.0),
    "btc": CustomHashtag(name: "bitcoin", display: "BTC", color: Color.orange, offset: -3.0),
    "coffee": CustomHashtag(name: "coffee", display: "Coffee", color: DamusColors.brown, offset: -1.0),
    "coffeechain": CustomHashtag(name: "coffee", display: "CoffeeChain", color: DamusColors.brown, offset: -1.0),
    "nostr": CustomHashtag(name: "nostr", display: "Nostr", color: DamusColors.purple, offset: -2.0),
    "nostrica": CustomHashtag(name: "nostrica", display: "Nostrica", color: DamusColors.purple, offset: -2.0),
    "onlyzap": CustomHashtag(name: "onlyzap", display: "OnlyZap", color: DamusColors.yellow, offset: -4.0),
    "onlyzaps": CustomHashtag(name: "onlyzaps", display: "OnlyZaps", color: DamusColors.yellow, offset: -4.0),
    "plebchain": CustomHashtag(name: "plebchain", display: "PlebChain", color: DamusColors.deepPurple, offset: -3.0),
    "zap": CustomHashtag(name: "zap", display: "Zap", color: DamusColors.yellow, offset: -4.0),
    "zaps": CustomHashtag(name: "zaps", display: "Zaps", color: DamusColors.yellow, offset: -4.0),
    "zapathon": CustomHashtag(name: "zapathon", display: "Zapathon", color: DamusColors.yellow, offset: -4.0),
]

func hashtag_str(_ htag: String) -> CompatibleText {
    let lowertag = htag.lowercased()
    
    let displayText: String
    var displayColor: Color?
    var imageOffset: CGFloat?
    var tagName: String?
    
    if let custom_hashtag = custom_hashtags[lowertag] {
        displayText = custom_hashtag.display
        displayColor = custom_hashtag.color
        imageOffset = custom_hashtag.offset
        tagName = custom_hashtag.name.lowercased()
    } else {
        displayText = htag
        displayColor = DamusColors.purple
        imageOffset = nil
        tagName = lowertag
    }
    
    var attributedString = AttributedString(stringLiteral: "#\(displayText)")
    attributedString.link = URL(string: "damus:t:\(displayText)")
    attributedString.foregroundColor = displayColor
       
    var text = Text(attributedString)
    
    if let name = tagName, let img = UIImage(named: "\(name)-hashtag") {
        attributedString = attributedString + " "
        attributed_string_attach_icon(&attributedString, img: img)
        
        text = Text(attributedString)
        let img = Image("\(name)-hashtag")
        text = text + Text("\(img)").baselineOffset(imageOffset ?? 0.0)
    }
    
    return CompatibleText(text: text, attributed: attributedString)
 }

