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
    let pubkey: String
    let note_id: String
}

enum ReportTarget {
    case user(String)
    case note(ReportNoteTarget)
}

struct Report {
    let type: ReportType
    let target: ReportTarget
    let message: String
}

func create_report_tags(target: ReportTarget, type: ReportType) -> [[String]] {
    switch target {
    case .user(let pubkey):
        return [["p", pubkey, type.rawValue]]
    case .note(let notet):
        return [["e", notet.note_id, type.rawValue], ["p", notet.pubkey]]
    }
}

func create_report_event(privkey: String, report: Report) -> NostrEvent? {
    guard let pubkey = privkey_to_pubkey(privkey: privkey) else {
        return nil
    }
    
    let kind = 1984
    let tags = create_report_tags(target: report.target, type: report.type)
    let ev = NostrEvent(content: report.message, pubkey: pubkey, kind: kind, tags: tags)
    
    ev.id = calculate_event_id(ev: ev)
    ev.sig = sign_event(privkey: privkey, ev: ev)
    
    return ev
}
