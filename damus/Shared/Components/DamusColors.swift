//
//  DamusColors.swift
//  damus
//
//  Created by William Casarin on 2023-03-27.
//

import Foundation
import SwiftUI

class DamusColors {
    static let adaptableGrey = Color("DamusAdaptableGrey")
    static let adaptableGrey2 = Color("DamusAdaptableGrey 2")
    static let adaptableLighterGrey = Color("DamusAdaptableLighterGrey")
    static let adaptablePurpleBackground = Color("DamusAdaptablePurpleBackground 1")
    static let adaptablePurpleBackground2 = Color("DamusAdaptablePurpleBackground 2")
    static let adaptablePurpleForeground = Color("DamusAdaptablePurpleForeground")
    static let adaptableBlack = Color("DamusAdaptableBlack")
    static let adaptableWhite = Color("DamusAdaptableWhite")
    static let white = Color("DamusWhite")
    static let black = Color("DamusBlack")
    static let brown = Color("DamusBrown")
    static let yellow = Color("DamusYellow")
    static let gold = hex_col(r: 226, g: 168, b: 0)
    static let lightGrey = Color("DamusLightGrey")
    static let mediumGrey = Color("DamusMediumGrey")
    static let darkGrey = Color("DamusDarkGrey")
    static let green = Color("DamusGreen")
    static let purple = Color("DamusPurple")
    static let deepPurple = Color("DamusDeepPurple")
    static let highlight = Color("DamusHighlight")
    /// Fill behind a search match.
    ///
    /// Deliberately not ``highlight``, which is the NIP-84 wash for marking a
    /// passage of longform prose you are already reading. A search match is
    /// scanned for rather than read — it has to be findable at a glance down a
    /// results list — so it is a stronger fill, clearing 3:1 against the page in
    /// both themes where the prose wash sits near 1.4:1.
    static let searchMatch = Color(UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 0xA3/255.0, green: 0x30/255.0, blue: 0x93/255.0, alpha: 1.0)
        } else {
            return UIColor(red: 0xD9/255.0, green: 0x5C/255.0, blue: 0xBF/255.0, alpha: 1.0)
        }
    })
    /// Text color for a span sitting on ``searchMatch``.
    ///
    /// The fill has to recolor the text it covers rather than leave it alone:
    /// hashtags render in ``purple`` and mentions and links are the same accent
    /// family, so accent-on-match is one hue against itself. No single fill can
    /// serve both those and plain body text, because reaching 4.5:1 against the
    /// accent magenta needs a near-white or near-black fill and both of those
    /// fail the body text the same match covers.
    static let searchMatchText = Color(UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.white
        } else {
            // Deep plum rather than plain black, to stay in the fill's hue
            return UIColor(red: 0x2A/255.0, green: 0x0A/255.0, blue: 0x26/255.0, alpha: 1.0)
        }
    })
    static let blue = Color("DamusBlue")
    static let bitcoin = Color("Bitcoin")
    static let success = Color("DamusSuccessPrimary")
    static let successSecondary = Color("DamusSuccessSecondary")
    static let successTertiary = Color("DamusSuccessTertiary")
    static let successQuaternary = Color("DamusSuccessQuaternary")
    static let successBorder = Color("DamusSuccessBorder")
    static let warning = Color("DamusWarningPrimary")
    static let warningSecondary = Color("DamusWarningSecondary")
    static let warningTertiary = Color("DamusWarningTertiary")
    static let warningQuaternary = Color("DamusWarningQuaternary")
    static let warningBorder = Color("DamusWarningBorder")
    static let danger = Color("DamusDangerPrimary")
    static let dangerSecondary = Color("DamusDangerSecondary")
    static let dangerTertiary = Color("DamusDangerTertiary")
    static let dangerQuaternary = Color("DamusDangerQuaternary")
    static let dangerBorder = Color("DamusDangerBorder")
    static let neutral1 = Color("DamusNeutral1")
    static let neutral3 = Color("DamusNeutral3")
    static let neutral6 = Color("DamusNeutral6")
    static let pink = Color(red: 211/255.0, green: 76/255.0, blue: 217/255.0)
    static let lighterPink = Color(red: 248/255.0, green: 105/255.0, blue: 182/255.0)
    static let lightBackgroundPink = Color(red: 0xF8/255.0, green: 0xE7/255.0, blue: 0xF8/255.0)

    // Sepia mode colors for comfortable longform reading
    // Light mode sepia
    static let sepiaBackgroundLight = Color(red: 0.98, green: 0.95, blue: 0.90)  // #FAF3E6 - warm off-white
    static let sepiaTextLight = Color(red: 0.35, green: 0.27, blue: 0.20)  // #5A4632 - warm brown
    // Dark mode sepia (subtle warm tint that blends with dark UI)
    static let sepiaBackgroundDark = Color(red: 0.08, green: 0.07, blue: 0.06)  // Near-black with subtle warmth
    static let sepiaTextDark = Color(red: 0.85, green: 0.80, blue: 0.72)  // Warm off-white text

    /// Returns appropriate sepia background for current color scheme.
    static func sepiaBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? sepiaBackgroundDark : sepiaBackgroundLight
    }

    /// Returns appropriate sepia text color for current color scheme.
    static func sepiaText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? sepiaTextDark : sepiaTextLight
    }
}

func hex_col(r: UInt8, g: UInt8, b: UInt8) -> Color {
    return Color(.sRGB,
                 red: Double(r) / Double(0xff),
                 green: Double(g) / Double(0xff),
                 blue: Double(b) / Double(0xff),
                 opacity: 1.0)
}
