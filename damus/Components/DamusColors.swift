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
}

func hex_col(r: UInt8, g: UInt8, b: UInt8) -> Color {
    return Color(.sRGB,
                 red: Double(r) / Double(0xff),
                 green: Double(g) / Double(0xff),
                 blue: Double(b) / Double(0xff),
                 opacity: 1.0)
}
