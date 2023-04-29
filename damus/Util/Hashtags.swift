//
//  Hashtags.swift
//  damus
//
//  Created by William Casarin on 2023-04-06.
//

import Foundation
import SwiftUI

struct CustomHashtag {
    let image_name: String
    let display: String
    let offset: CGFloat?
    let color: Color?
    
    init(image_name: String, display: String, color: Color? = nil, offset: CGFloat? = nil) {
        self.image_name = image_name
        self.display = display
        self.color = color
        self.offset = offset
    }
}

let custom_hashtags: [String: CustomHashtag] = [
    "bitcoin": CustomHashtag(image_name: "bitcoin", display: "Bitcoin", color: Color.orange, offset: -3.0),
    "bitcoinwallet": CustomHashtag(image_name: "bitcoin", display: "Bitcoin", color: Color.orange, offset: -3.0),
    "bitcoinadoption": CustomHashtag(image_name: "bitcoin", display: "BitcoinAdoption", color: Color.orange, offset: -3.0),
    "bitcoinjungle": CustomHashtag(image_name: "bitcoin", display: "BitcoinJungle", color: Color.orange, offset: -3.0),
    "btc": CustomHashtag(image_name: "bitcoin", display: "BTC", color: Color.orange, offset: -3.0),
    "coffee": CustomHashtag(image_name: "coffee", display: "Coffee", color: DamusColors.brown, offset: -1.0),
    "coffeechain": CustomHashtag(image_name: "coffee", display: "CoffeeChain", color: DamusColors.brown, offset: -1.0),
    "nostr": CustomHashtag(image_name: "nostr", display: "Nostr", color: DamusColors.purple, offset: -2.0),
    "nostrica": CustomHashtag(image_name: "nostr", display: "Nostrica", color: DamusColors.purple, offset: -2.0),
    "onlyzap": CustomHashtag(image_name: "zap", display: "OnlyZap", color: DamusColors.yellow, offset: -4.0),
    "onlyzaps": CustomHashtag(image_name: "zap", display: "OnlyZaps", color: DamusColors.yellow, offset: -4.0),
    "plebchain": CustomHashtag(image_name: "plebchain", display: "PlebChain", color: DamusColors.deepPurple, offset: -3.0),
    "zap": CustomHashtag(image_name: "zap", display: "Zap", color: DamusColors.yellow, offset: -4.0),
    "zaps": CustomHashtag(image_name: "zap", display: "Zaps", color: DamusColors.yellow, offset: -4.0),
    "zapathon": CustomHashtag(image_name: "zap", display: "Zapathon", color: DamusColors.yellow, offset: -4.0),
]

func hashtag_str(htag: String, camel_case: Bool) -> CompatibleText {
    let lowertag = htag.lowercased()
    
    let display_text: String
    var display_color: Color?
    var image_offset: CGFloat?
    var image_name: String?
    
    if let custom_hashtag = custom_hashtags[lowertag] {
        display_text = custom_hashtag.display
        display_color = custom_hashtag.color
        image_offset = custom_hashtag.offset
        image_name = custom_hashtag.image_name
    } else {
        display_text = htag
        display_color = DamusColors.purple
        image_offset = nil
        image_name = nil
    }
    
    print("Hashtags: camel_case is \(camel_case)")
    var attributed_string = AttributedString(stringLiteral: "#\(camel_case ? display_text : htag)")
    print("Hashtags: attributed_string is \(attributed_string)")
    attributed_string.link = URL(string: "damus:t:\(display_text)")
    attributed_string.foregroundColor = display_color
       
    var text = Text(attributed_string)
    
    if let image_name, let img = UIImage(named: "\(image_name)-hashtag") {
        attributed_string = attributed_string + " "
        attributed_string_attach_icon(&attributed_string, img: img)
        
        text = Text(attributed_string)
        let img = Image("\(image_name)-hashtag")
        text = text + Text("\(img)").baselineOffset(image_offset ?? 0.0)
    }
    
    return CompatibleText(text: text, attributed: attributed_string)
 }

