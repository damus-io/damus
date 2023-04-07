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
    let color: Color?
    
    init(name: String, color: Color? = nil) {
        self.name = name
        self.color = color
    }
    
    static let coffee = CustomHashtag(name: "coffee", color: DamusColors.brown)
    static let bitcoin = CustomHashtag(name: "bitcoin", color: Color.orange)
    static let nostr = CustomHashtag(name: "nostr", color: DamusColors.purple)
}


let custom_hashtags: [String: CustomHashtag] = [
    "bitcoin": CustomHashtag.bitcoin,
    "nostr": CustomHashtag.nostr,
    "coffee": CustomHashtag.coffee,
    "coffeechain": CustomHashtag.coffee,
]

func hashtag_str(_ htag: String) -> CompatibleText {
    var attributedString = AttributedString(stringLiteral: "#\(htag)")
    attributedString.link = URL(string: "damus:t:\(htag)")
    
    let lowertag = htag.lowercased()
    
    var text = Text(attributedString)
    if let custom_hashtag = custom_hashtags[lowertag] {
        if let col = custom_hashtag.color {
            attributedString.foregroundColor = col
        }
        
        let name = custom_hashtag.name
        
        text = Text(attributedString)
        if let img = UIImage(named: "\(name)-hashtag") {
            attributedString = attributedString + " "
            attributed_string_attach_icon(&attributedString, img: img)
        }
        let img = Image("\(name)-hashtag")
        text = text + Text(" \(img)")
    } else {
        attributedString.foregroundColor = DamusColors.purple
    }
    
    return CompatibleText(text: text, attributed: attributedString)
 }

