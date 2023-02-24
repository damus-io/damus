//
//  LocalizationUtil.swift
//  damus
//
//  Created by Terry Yiu on 2/24/23.
//

import Foundation

func bundleForLocale(locale: Locale) -> Bundle {
    let path = Bundle.main.path(forResource: locale.identifier, ofType: "lproj")
    return path != nil ? (Bundle(path: path!) ?? Bundle.main) : Bundle.main
}

func formatInt(_ int: Int) -> String {
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    return numberFormatter.string(from: NSNumber(integerLiteral: int)) ?? "\(int)"
}
