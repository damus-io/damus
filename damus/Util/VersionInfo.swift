//
//  VersionInfo.swift
//  damus
//
//  Created by William Casarin on 2023-08-01.
//

import Foundation


class VersionInfo {
    private static var _version: String? = nil

    static var version: String {
        if let _version {
            return _version
        }

        guard let short_version = Bundle.main.infoDictionary?["CFBundleShortVersionString"],
              let bundle_version = Bundle.main.infoDictionary?["CFBundleVersion"]
        else {
            return "Unknown"
        }

        // we only have these in debug builds
        let hash = git_hash ?? ""
        let ver = "\(short_version) (\(bundle_version)) \(hash)"

        _version = ver
        return ver
    }

    static var git_hash: String? {
        if let url = Bundle.main.url(forResource: "build-git-hash", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil
        }
    }
}
