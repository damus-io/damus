//
//  NdbDatabase+UI.swift
//  (UI/Features target)
//
//  This extension adds UI-specific properties to NdbDatabase for presentation purposes.
//  It should only be included in targets involving SwiftUI/UI presentation.
//

import SwiftUI

extension NdbDatabase {
    /// Human-readable database name
    var displayName: String {
        switch self {
        case .note:
            return NSLocalizedString("Notes (NDB_DB_NOTE)", comment: "Database name for notes")
        case .meta:
            return NSLocalizedString("Metadata (NDB_DB_META)", comment: "Database name for metadata")
        case .profile:
            return NSLocalizedString("Profiles (NDB_DB_PROFILE)", comment: "Database name for profiles")
        case .noteId:
            return NSLocalizedString("Note ID Index", comment: "Database name for note ID index")
        case .profileKey:
            return NSLocalizedString("Profile Key Index", comment: "Database name for profile key index")
        case .ndbMeta:
            return NSLocalizedString("NostrDB Metadata", comment: "Database name for NostrDB metadata")
        case .profileSearch:
            return NSLocalizedString("Profile Search Index", comment: "Database name for profile search")
        case .profileLastFetch:
            return NSLocalizedString("Profile Last Fetch", comment: "Database name for profile last fetch")
        case .noteKind:
            return NSLocalizedString("Note Kind Index", comment: "Database name for note kind index")
        case .noteText:
            return NSLocalizedString("Note Text Index", comment: "Database name for note text index")
        case .noteBlocks:
            return NSLocalizedString("Note Blocks", comment: "Database name for note blocks")
        case .noteTags:
            return NSLocalizedString("Note Tags Index", comment: "Database name for note tags index")
        case .notePubkey:
            return NSLocalizedString("Note Pubkey Index", comment: "Database name for note pubkey index")
        case .notePubkeyKind:
            return NSLocalizedString("Note Pubkey+Kind Index", comment: "Database name for note pubkey+kind index")
        case .noteRelayKind:
            return NSLocalizedString("Note Relay+Kind Index", comment: "Database name for note relay+kind index")
        case .noteRelays:
            return NSLocalizedString("Note Relays", comment: "Database name for note relays")
        case .other:
            return NSLocalizedString("Other Data", comment: "Database name for other/unaccounted data")
        }
    }

    /// SF Symbol icon name for this database type
    var icon: String {
        switch self {
        case .note:
            return "text.bubble.fill"
        case .profile:
            return "person.circle.fill"
        case .meta, .ndbMeta:
            return "info.circle.fill"
        case .noteBlocks:
            return "square.stack.3d.up.fill"
        case .noteId, .profileKey, .profileSearch, .noteKind, .noteText, .noteTags, .notePubkey, .notePubkeyKind, .noteRelayKind:
            return "list.bullet.indent"
        case .noteRelays:
            return "antenna.radiowaves.left.and.right"
        case .profileLastFetch, .other:
            return "internaldrive.fill"
        }
    }

    /// Color for chart and UI display
    var color: Color {
        switch self {
        case .note:
            return .green
        case .profile:
            return .blue
        case .noteBlocks:
            return .purple
        case .meta, .ndbMeta:
            return .orange
        case .noteId, .profileKey, .profileSearch, .noteKind, .noteText, .noteTags, .notePubkey, .notePubkeyKind, .noteRelayKind:
            return .gray
        case .noteRelays:
            return .cyan
        case .profileLastFetch, .other:
            return .secondary
        }
    }
}
