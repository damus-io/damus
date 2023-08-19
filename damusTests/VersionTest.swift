// VersionInfo.swift

import Foundation
import UIKit

class VersionInfo {
  // File name for git hash 
  private static let gitHashFileName = "build-git-hash.txt"
  // Compute and cache the version string
  static var version: String = {
    let versionString = buildVersionString()
    // Cache it
    _version = versionString
    return versionString
  }()
  private static var _version: String?
  private static func buildVersionString() -> String {
    // Get version numbers from bundle
    guard 
      let versionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    else {
      return "Unknown"
    }
    let iOSVersion = UIDevice.current.systemVersion
    let gitHash = getGitHash()
    // Build string
    let versionString = "Damus: \(versionNumber) (\(buildNumber)) \(gitHash) iOS: \(iOSVersion)"
    return versionString
  }
  // Get git hash from hash file if exists
  private static func getGitHash() -> String {
    guard 
      let url = Bundle.main.url(forResource: gitHashFileName, withExtension: "txt"),
      let gitHash = try? String(contentsOf: url, encoding: .utf8) 
    else {
      return "" 
    }
    return gitHash.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
