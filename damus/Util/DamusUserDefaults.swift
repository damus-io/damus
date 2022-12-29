//
//  DamusUserDefaults.swift
//  damus
//
//  Created by Benjamin Hakes on 12/28/22.
//

import Foundation

/// A namespace for placing UserDefault.standard getters and setters
///
/// Placing getters and setters here causes less public namespace polution
enum DamusUserDefaults {
  static func saveMostRecentWallet(name: String) {
      UserDefaults.standard.set(name, forKey: "most_recent_wallet")
  }

  static var mostRecentWalletName: String? {
    UserDefaults.standard.string(forKey: "most_recent_wallet")
  }
}
