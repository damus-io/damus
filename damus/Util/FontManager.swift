//
//  FontManager.swift
//  damus
//
//  Created by Ben Weeks on 27/05/2023.
//

import Foundation
import SwiftUI

struct FontManager {
    struct dynamicSize {
        public static var largeTitle: CGFloat = UIFont.preferredFont(forTextStyle: .largeTitle).pointSize - 1
        public static var title1: CGFloat = UIFont.preferredFont(forTextStyle: .title1).pointSize - 0
        public static var title2: CGFloat = UIFont.preferredFont(forTextStyle: .title2).pointSize - 0
        public static var title3: CGFloat = UIFont.preferredFont(forTextStyle: .title3).pointSize - 0
        public static var body: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize - 1
        public static var callout: CGFloat = UIFont.preferredFont(forTextStyle: .callout).pointSize - 1
        public static var caption1: CGFloat = UIFont.preferredFont(forTextStyle: .caption1).pointSize - 1
        public static var caption2: CGFloat = UIFont.preferredFont(forTextStyle: .caption2).pointSize - 1
        public static var footnote: CGFloat = UIFont.preferredFont(forTextStyle: .footnote).pointSize - 1
        public static var headline: CGFloat = UIFont.preferredFont(forTextStyle: .headline).pointSize - 1
        public static var subheadline: CGFloat = UIFont.preferredFont(forTextStyle: .subheadline).pointSize - 1
        // repeat for all the dynamic sizes
    }

    struct Inter {
        static let familyRoot = "Inter"

        static let bold = "\(familyRoot)-Bold"
        static let regular = "\(familyRoot)-Regular"
        static let light = "\(familyRoot)-Light"
        static let medium = "\(familyRoot)-Medium"
        static let semibold = "\(familyRoot)-SemiBold"
        static let italic = "\(familyRoot)-Italic"

        static let largeTitle: Font = Font.custom(FontManager.Inter.regular, size: FontManager.dynamicSize.largeTitle)
        static let title1: Font = Font.custom(FontManager.Inter.semibold, size: FontManager.dynamicSize.title1)
        static let title2: Font = Font.custom(FontManager.Inter.semibold, size: FontManager.dynamicSize.title2)
        static let title3: Font = Font.custom(FontManager.Inter.semibold, size: FontManager.dynamicSize.title3)
        static let body: Font = Font.custom(FontManager.Inter.regular, size: FontManager.dynamicSize.body)
        static let caption1: Font = Font.custom(FontManager.Inter.regular, size: FontManager.dynamicSize.caption1)
        static let caption2: Font = Font.custom(FontManager.Inter.regular, size: FontManager.dynamicSize.caption2)
        static let footnote: Font = Font.custom(FontManager.Inter.regular, size: FontManager.dynamicSize.footnote)
        static let headline: Font = Font.custom(FontManager.Inter.regular, size: FontManager.dynamicSize.headline)
        static let subheadline: Font = Font.custom(FontManager.Inter.regular, size: FontManager.dynamicSize.subheadline)
        // repeat for other sizes
    }
}

extension Font {
    public static var largeTitle = FontManager.Inter.largeTitle
    public static var title1 = FontManager.Inter.title1
    public static var title2 = FontManager.Inter.title2
    public static var title3 = FontManager.Inter.title3
    public static var body = FontManager.Inter.body
    public static var caption1 = FontManager.Inter.caption1
    public static var caption2 = FontManager.Inter.caption2
    public static var footnote = FontManager.Inter.footnote
    public static var headline = FontManager.Inter.headline
    public static var subheadline = FontManager.Inter.subheadline
    // repeat for the rest of the dynamic sizes
}
