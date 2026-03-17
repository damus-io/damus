//
//  Secrets.swift
//  damus
//
//  Created by eric on 12/18/25.
//
// This file contains a list of secrets imported from Info.plist,
// where those secrets are baked in at build time from environment variables
// and cannot be committed to git for security reasons.

import Foundation

enum Secrets {
    /// TENOR_API_KEY is baked into Info.plist at build time from the TENOR_API_KEY environment variable.
    /// The build system substitutes $(TENOR_API_KEY) in Info.plist with the actual value during compilation.
    static let TENOR_API_KEY: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "TENOR_API_KEY") as? String,
              !key.isEmpty,
              key != "$(TENOR_API_KEY)" else { // Fallback if substitution didn't occur
            return nil
        }
        return key
    }()
}
