//
//  FaviconCache.swift
//  damus
//
//  Created by Terry Yiu on 5/23/25.
//

import Foundation
import FaviconFinder

class FaviconCache {
    private var nip05DomainFavicons: [String: [FaviconURL]] = [:]

    @MainActor
    func lookup(_ domain: String) async -> [FaviconURL] {
        let lowercasedDomain = domain.lowercased()
        if let faviconURLs = nip05DomainFavicons[lowercasedDomain] {
            return faviconURLs
        }

        guard let siteURL = URL(string: "https://\(lowercasedDomain)"),
              let faviconURLs = try? await FaviconFinder(
                url: siteURL,
                configuration: .init(
                    preferredSource: .ico, // Prefer using common favicon .ico filenames at root level to avoid scraping HTML when possible.
                    preferences: [
                        .html: FaviconFormatType.appleTouchIcon.rawValue,
                        .ico: "favicon.ico",
                        .webApplicationManifestFile: FaviconFormatType.launcherIcon4x.rawValue
                    ]
                )
              ).fetchFaviconURLs()
        else {
            return []
        }

        nip05DomainFavicons[lowercasedDomain] = faviconURLs

        return faviconURLs
    }
}
