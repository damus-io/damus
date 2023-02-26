//
//  LocalizationUtil.swift
//  damus
//
//  Created by Terry Yiu on 2/24/23.
//

import Foundation

func bundleForLocale(locale: Locale?) -> Bundle {
    if locale == nil {
        return Bundle.main
    }

    let path = Bundle.main.path(forResource: locale!.identifier, ofType: "lproj")
    return path != nil ? (Bundle(path: path!) ?? Bundle.main) : Bundle.main
}
