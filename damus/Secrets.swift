//
//  Secrets.swift
//  damus
//
//  Created by eric on 12/18/25.
//
// This file contains a list of secrets imported from environment variables,
// where those environment variables cannot be committed to git for security reasons.

import Foundation

enum Secrets {
    static let TENOR_API_KEY: String? = ProcessInfo.processInfo.environment["TENOR_API_KEY"]
}
