//
//  CondensedProfilePicturesViewModel.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-09-15.
//
import Combine
import Foundation

class CondensedProfilePicturesViewModel: ObservableObject {
    let state: DamusState
    let pubkeys: [Pubkey]
    let maxPictures: Int
    var shownPubkeys: [Pubkey] {
        return Array(pubkeys.prefix(maxPictures))
    }
    var loadingTask: Task<Void, Never>? = nil
    
    init(state: DamusState, pubkeys: [Pubkey], maxPictures: Int) {
        self.state = state
        self.pubkeys = pubkeys
        self.maxPictures = min(maxPictures, pubkeys.count)
    }
    
    func load() {
        loadingTask?.cancel()
        loadingTask = Task { try? await loadingTask() }
    }
    
    func loadingTask() async throws {
        let filter = NostrFilter(kinds: [.metadata], authors: shownPubkeys)
        let _ = await state.nostrNetwork.reader.query(filters: [filter])
        for await _ in state.nostrNetwork.reader.streamNotesUntilEndOfStoredEvents(filters: [filter]) {
            // NO-OP, we just need it to be loaded into NostrDB.
            try Task.checkCancellation()
        }
        DispatchQueue.main.async {
            // Cause the view to re-render with the newly loaded profiles
            self.objectWillChange.send()
        }
    }
}
