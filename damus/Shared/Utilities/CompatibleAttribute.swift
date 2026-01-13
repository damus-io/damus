//
//  CompatibleAttribute.swift
//  damus
//
//  Created by William Casarin on 2023-04-06.
//

import Foundation
import SwiftUI

// Concatening too many `Text` objects can cause crashes (See https://github.com/damus-io/damus/issues/1826)
fileprivate let MAX_TEXT_ITEMS = 100

class CompatibleText: Equatable {
    var text: some View {
        if items.count > MAX_TEXT_ITEMS {
            return AnyView(
                VStack {
                    Image("warning")
                    Text("This note contains too many items and cannot be rendered", comment: "Error message indicating that a note is too big and cannot be rendered")
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.secondary)
            )
        }
        // Use render_to_text() to properly render imageIcon items as Text(Image(uiImage:))
        return AnyView(
            items.reduce(Text(""), { (accumulated, item) in
                return accumulated + item.render_to_text()
            })
        )
    }
    var attributed: AttributedString {
        return items.reduce(AttributedString(stringLiteral: ""), { (accumulated, item) in
            guard let item_attributed_string = item.attributed_string() else { return accumulated }
            return accumulated + item_attributed_string
        })
    }
    var items: [Item]

    init() {
        self.items = [.attributed_string(AttributedString(stringLiteral: ""))]
    }

    init(stringLiteral: String) {
        self.items = [.attributed_string(AttributedString(stringLiteral: stringLiteral))]
    }

    init(attributed: AttributedString) {
        self.items = [.attributed_string(attributed)]
    }

    init(items: [Item]) {
        self.items = items
    }

    static func == (lhs: CompatibleText, rhs: CompatibleText) -> Bool {
        return lhs.items == rhs.items
    }

    static func +(lhs: CompatibleText, rhs: CompatibleText) -> CompatibleText {
        if case .attributed_string(let las) = lhs.items.last,
           case .attributed_string(let ras) = rhs.items.first
        {
            // Concatenate attributed strings whenever possible to reduce item count
            let combined_attributed_string = las + ras
            return CompatibleText(items:
                Array(lhs.items.prefix(upTo: lhs.items.count - 1)) +
                [.attributed_string(combined_attributed_string)] +
                Array(rhs.items.suffix(from: 1))
            )
        }
        else {
            return CompatibleText(items: lhs.items + rhs.items)
        }
    }

}

extension CompatibleText {
    enum Item: Equatable {
        case attributed_string(AttributedString)
        case icon(named: String, offset: CGFloat)
        case imageIcon(UIImage, offset: CGFloat)  // For custom emoji images

        static func == (lhs: Item, rhs: Item) -> Bool {
            switch (lhs, rhs) {
            case (.attributed_string(let l), .attributed_string(let r)):
                return l == r
            case (.icon(let lName, let lOffset), .icon(let rName, let rOffset)):
                return lName == rName && lOffset == rOffset
            case (.imageIcon(let lImg, let lOffset), .imageIcon(let rImg, let rOffset)):
                return lImg === rImg && lOffset == rOffset
            default:
                return false
            }
        }

        func render_to_text() -> Text {
            switch self {
                case .attributed_string(let attributed_string):
                    return Text(attributed_string)
                case .icon(named: let image_name, offset: let offset):
                    return Text(Image(image_name)).baselineOffset(offset)
                case .imageIcon(let uiImage, let offset):
                    return Text(Image(uiImage: uiImage)).baselineOffset(offset)
            }
        }

        func attributed_string() -> AttributedString? {
            switch self {
                case .attributed_string(let attributed_string):
                    return attributed_string
                case .icon(named: let name, offset: _):
                    guard let img = UIImage(named: name) else { return nil }
                    return icon_attributed_string(img: img)
                case .imageIcon(let img, offset: _):
                    return icon_attributed_string(img: img)
            }
        }
    }
}


func icon_attributed_string(img: UIImage) -> AttributedString {
    let attachment = NSTextAttachment()
    attachment.image = img
    let attachmentString = NSAttributedString(attachment: attachment)
    return AttributedString(attachmentString)
}


