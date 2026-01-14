//
//  Hashtags.swift
//  damus
//
//  Created by William Casarin on 2023-04-06.
//

import Foundation
import SwiftUI
import Kingfisher

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

// MARK: - Custom Emoji (NIP-30)

/// Size for inline custom emoji images.
private let CUSTOM_EMOJI_SIZE: CGFloat = 20

/// Regex pattern for matching :shortcode: in text.
private let shortcodePattern = try! NSRegularExpression(
    pattern: #":([a-zA-Z0-9_]+):"#,
    options: []
)

/// Processes text content and replaces :shortcode: patterns with custom emoji.
///
/// - Parameters:
///   - text: The text content to process
///   - emojis: Dictionary mapping shortcodes to CustomEmoji
/// - Returns: CompatibleText with emoji shortcodes replaced by images or styled text
func emojify_text(_ text: String, emojis: [String: CustomEmoji]) -> CompatibleText {
    guard !emojis.isEmpty else {
        return CompatibleText(stringLiteral: text)
    }
    #if DEBUG
    print("NIP-30 emojify: Processing text with \(emojis.count) emojis available")
    #endif

    let nsText = text as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    let matches = shortcodePattern.matches(in: text, options: [], range: fullRange)

    #if DEBUG
    print("NIP-30 emojify: Found \(matches.count) shortcode patterns in text")
    for match in matches {
        if match.numberOfRanges >= 2, let shortcodeRange = Range(match.range(at: 1), in: text) {
            let shortcode = String(text[shortcodeRange])
            let hasEmoji = emojis[shortcode] != nil
            print("NIP-30 emojify:   - :\(shortcode): -> emoji found: \(hasEmoji)")
        }
    }
    #endif

    guard !matches.isEmpty else {
        return CompatibleText(stringLiteral: text)
    }

    var items: [CompatibleText.Item] = []
    var lastEnd = 0

    for match in matches {
        guard match.numberOfRanges >= 2,
              let shortcodeRange = Range(match.range(at: 1), in: text) else {
            continue
        }

        let shortcode = String(text[shortcodeRange])

        guard let emoji = emojis[shortcode] else {
            continue
        }

        // Add text before this emoji
        let matchRange = match.range
        if matchRange.location > lastEnd {
            let beforeRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
            let beforeText = nsText.substring(with: beforeRange)
            items.append(.attributed_string(AttributedString(stringLiteral: beforeText)))
        }

        // Add the emoji (image if cached, styled text otherwise)
        let emojiItem = render_custom_emoji(emoji)
        items.append(emojiItem)

        lastEnd = matchRange.location + matchRange.length
    }

    // Add remaining text after last emoji
    if lastEnd < nsText.length {
        let afterRange = NSRange(location: lastEnd, length: nsText.length - lastEnd)
        let afterText = nsText.substring(with: afterRange)
        items.append(.attributed_string(AttributedString(stringLiteral: afterText)))
    }

    #if DEBUG
    print("NIP-30 emojify: Created \(items.count) items from emojified text")
    for (index, item) in items.enumerated() {
        switch item {
        case .attributed_string(let attrStr):
            let hasColor = attrStr.foregroundColor != nil
            let text = String(attrStr.characters)
            print("NIP-30 emojify:   item[\(index)]: attributed_string '\(text)' hasColor=\(hasColor)")
        case .icon(let name, _):
            print("NIP-30 emojify:   item[\(index)]: icon '\(name)'")
        case .imageIcon(_, _):
            print("NIP-30 emojify:   item[\(index)]: imageIcon (legacy)")
        case .customEmoji(_, let emoji, _):
            print("NIP-30 emojify:   item[\(index)]: customEmoji '\(emoji.shortcode)'")
        }
    }
    #endif

    return CompatibleText(items: items)
}

/// Renders a single custom emoji as a CompatibleText.Item.
private func render_custom_emoji(_ emoji: CustomEmoji) -> CompatibleText.Item {
    let cacheKey = emoji.url.absoluteString

    // Use synchronous in-memory cache retrieval
    if let cachedImage = ImageCache.default.retrieveImageInMemoryCache(forKey: cacheKey) {
        #if DEBUG
        print("NIP-30 render: :\(emoji.shortcode): using cached image")
        #endif
        let scaledImage = scaleEmojiImage(cachedImage, toSize: CGSize(width: CUSTOM_EMOJI_SIZE, height: CUSTOM_EMOJI_SIZE))
        // Use .customEmoji to preserve emoji metadata for context menu support
        return .customEmoji(scaledImage, emoji, offset: -3.0)
    }

    // Fallback: render as styled text with purple color
    #if DEBUG
    print("NIP-30 render: :\(emoji.shortcode): using purple fallback (not in memory cache)")
    #endif
    return styled_emoji_fallback(emoji.shortcode)
}

/// Creates a styled text fallback for an emoji shortcode.
private func styled_emoji_fallback(_ shortcode: String) -> CompatibleText.Item {
    var attributedString = AttributedString(stringLiteral: ":\(shortcode):")
    attributedString.foregroundColor = DamusColors.purple
    #if DEBUG
    // Verify the foreground color was set
    if let color = attributedString.foregroundColor {
        print("NIP-30 fallback: :\(shortcode): foregroundColor SET to \(color)")
    } else {
        print("NIP-30 fallback: :\(shortcode): foregroundColor is NIL!")
    }
    #endif
    return .attributed_string(attributedString)
}

/// Scales a UIImage to the specified size.
private func scaleEmojiImage(_ image: UIImage, toSize size: CGSize) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
}

/// Prefetches custom emoji images for caching.
func prefetch_custom_emojis<T: Collection>(_ emojis: T) where T.Element == CustomEmoji {
    let urls = emojis.map { $0.url }
    let prefetcher = ImagePrefetcher(urls: urls)
    prefetcher.start()
}

/// Builds a dictionary from an event's custom emoji tags for efficient lookup.
func build_custom_emoji_map(_ event: NostrEvent) -> [String: CustomEmoji] {
    var map: [String: CustomEmoji] = [:]
    for emoji in event.referenced_custom_emojis {
        map[emoji.shortcode] = emoji
    }
    return map
}
