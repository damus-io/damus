//
//  OutboxRecoveryTracker.swift
//  damus
//
//  Created by OpenAI Codex on 2025-09-06.
//

import Foundation

/// Tracks which note IDs were recovered via outbox so UI can surface badges.
@MainActor
final class OutboxRecoveryTracker {
    static let shared = OutboxRecoveryTracker()
    
    private var recoveredNoteIds: Set<NoteId> = []
    
    func mark(noteId: NoteId) {
        recoveredNoteIds.insert(noteId)
    }
    
    func hasRecovered(noteId: NoteId) -> Bool {
        recoveredNoteIds.contains(noteId)
    }
}
