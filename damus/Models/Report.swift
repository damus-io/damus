//
//  Report.swift
//  damus
//
//  Created by William Casarin on 2023-01-24.
//

import Foundation

enum ReportType: String, CustomStringConvertible, CaseIterable {
    case spam
    case nudity
    case profanity
    case illegal
    case impersonation

    var description: String {
        switch self {
        case .spam:
            return NSLocalizedString("Spam", comment: "Description of report type for spam.")
        case .nudity:
            return NSLocalizedString("Nudity", comment: "Description of report type for nudity.")
        case .profanity:
            return NSLocalizedString("Profanity", comment: "Description of report type for profanity.")
        case .illegal:
            return NSLocalizedString("Illegal Content", comment: "Description of report type for illegal content.")
        case .impersonation:
            return NSLocalizedString("Impersonation", comment: "Description of report type for impersonation.")
        }
    }
}

struct ReportNoteTarget {
    let pubkey: Pubkey
    let note_id: NoteId
}

enum ReportTarget {
    case user(Pubkey)
    case note(ReportNoteTarget)
}

