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

    static func note(pubkey: Pubkey, note_id: NoteId) -> ReportTarget {
        return .note(ReportNoteTarget(pubkey: pubkey, note_id: note_id))
    }
}

struct Report {
    let type: ReportType
    let target: ReportTarget
    let message: String

}

func create_report_tags(target: ReportTarget, type: ReportType) -> [[String]] {
    switch target {
    case .user(let pubkey):
        return [["p", pubkey.hex(), type.rawValue]]
    case .note(let notet):
        return [["e", notet.note_id.hex(), type.rawValue],
                ["p", notet.pubkey.hex()]]
    }
}

func create_report_event(keypair: FullKeypair, report: Report) -> NostrEvent? {
    let kind: UInt32 = 1984
    let tags = create_report_tags(target: report.target, type: report.type)
    return NostrEvent(content: report.message, keypair: keypair.to_keypair(), kind: kind, tags: tags)
}
