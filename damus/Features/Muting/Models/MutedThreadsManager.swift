//
//  MutedThreadsManager.swift
//  damus
//
//  Created by Terry Yiu on 4/6/23.
//

import Foundation

fileprivate func getMutedThreadsKey(pubkey: Pubkey) -> String {
    pk_setting_key(pubkey, key: "muted_threads")
}

func loadOldMutedThreads(pubkey: Pubkey) -> [NoteId] {
    let key = getMutedThreadsKey(pubkey: pubkey)
    let xs = UserDefaults.standard.stringArray(forKey: key) ?? []
    return xs.reduce(into: [NoteId]()) { ids, k in
        guard let note_id = hex_decode(k) else { return }
        ids.append(NoteId(Data(note_id)))
    }
}

// We need to still use it since existing users might have their muted threads stored in UserDefaults
// So now all it's doing is moving a users muted threads to the new kind:10000 system
// It should not be used for any purpose beyond that
@MainActor
func migrate_old_muted_threads_to_new_mutelist(keypair: Keypair, damus_state: DamusState) {
    // Ensure that keypair is fullkeypair
    guard let fullKeypair = keypair.to_full() else { return }
    // Load existing muted threads
    let mutedThreads = loadOldMutedThreads(pubkey: fullKeypair.pubkey)
    guard !mutedThreads.isEmpty else { return }
    // Set new muted system for those existing threads
    let previous_mute_list_event = damus_state.mutelist_manager.event
    guard let new_mutelist_event = create_or_update_mutelist(keypair: fullKeypair, mprev: previous_mute_list_event, to_add: Set(mutedThreads.map { MuteItem.thread($0, nil) })) else { return }
    damus_state.mutelist_manager.set_mutelist(new_mutelist_event)
    damus_state.settings.latest_mutelist_event_id_hex = new_mutelist_event.id.hex()
    Task { await damus_state.nostrNetwork.postbox.send(new_mutelist_event) }
    // Set existing muted threads to an empty array
    UserDefaults.standard.set([], forKey: getMutedThreadsKey(pubkey: keypair.pubkey))
}
