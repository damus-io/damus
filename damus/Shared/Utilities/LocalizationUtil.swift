//
//  LocalizationUtil.swift
//  damus
//
//  Created by Terry Yiu on 2/24/23.
//

import Foundation

private var _bundleCache: [String: Bundle] = [:]

func bundleForLocale(locale: Locale) -> Bundle {
    let id = locale.identifier
    if let cached = _bundleCache[id] {
        return cached
    }
    let bundle: Bundle
    if let path = Bundle.main.path(forResource: id, ofType: "lproj") {
        bundle = Bundle(path: path) ?? Bundle.main
    } else {
        bundle = Bundle.main
    }
    _bundleCache[id] = bundle
    return bundle
}

private let _enUSFallbackBundle: Bundle = bundleForLocale(locale: Locale(identifier: "en-US"))

func localizedStringFormat(key: String, locale: Locale) -> String {
    let bundle = bundleForLocale(locale: locale)
    let fallback = _enUSFallbackBundle.localizedString(forKey: key, value: nil, table: nil)
    return bundle.localizedString(forKey: key, value: fallback, table: nil)
}

/**
 Removes the variant part of a locale code so that it contains only the language code.
 */
func localeToLanguage(_ locale: String) -> String? {
    if #available(iOS 16, *) {
        return Locale.LanguageCode(stringLiteral: locale).identifier(.alpha2)
    } else {
        return NSLocale(localeIdentifier: locale).languageCode
    }
}

/// Returns a localized string that is pluralized based on a single Int-typed count variable.
func pluralizedString(key: String, count: Int, locale: Locale = Locale.current) -> String {
    let format = localizedStringFormat(key: key, locale: locale)
    return String(format: format, locale: locale, count)
}
