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

func loadMutedThreads(pubkey: Pubkey) -> [NoteId] {
    let key = getMutedThreadsKey(pubkey: pubkey)
    let xs = UserDefaults.standard.stringArray(forKey: key) ?? []
    return xs.reduce(into: [NoteId]()) { ids, k in
        guard let note_id = hex_decode(k) else { return }
        ids.append(NoteId(Data(note_id)))
    }
}

func saveMutedThreads(pubkey: Pubkey, currentValue: [NoteId], value: [NoteId]) -> Bool {
    let uniqueMutedThreads = Array(Set(value))

    if uniqueMutedThreads != currentValue {
        UserDefaults.standard.set(uniqueMutedThreads, forKey: getMutedThreadsKey(pubkey: pubkey))
        return true
    }

    return false
}

class MutedThreadsManager: ObservableObject {

    private let keypair: Keypair

    private var _mutedThreadsSet: Set<NoteId>
    private var _mutedThreads: [NoteId]
    var mutedThreads: [NoteId] {
        get {
            return _mutedThreads
        }
        set {
            if saveMutedThreads(pubkey: keypair.pubkey, currentValue: _mutedThreads, value: newValue) {
                self._mutedThreads = newValue
                self.objectWillChange.send()
            }
        }
    }

    init(keypair: Keypair) {
        self._mutedThreads = loadMutedThreads(pubkey: keypair.pubkey)
        self._mutedThreadsSet = Set(_mutedThreads)
        self.keypair = keypair
    }

    func isMutedThread(_ ev: NostrEvent, privkey: Privkey?) -> Bool {
        return _mutedThreadsSet.contains(ev.thread_id(privkey: privkey))
    }

    func updateMutedThread(_ ev: NostrEvent) {
        let threadId = ev.thread_id(privkey: nil)
        if isMutedThread(ev, privkey: keypair.privkey) {
            mutedThreads = mutedThreads.filter { $0 != threadId }
            _mutedThreadsSet.remove(threadId)
            notify(.unmute_thread(ev))
        } else {
            mutedThreads.append(threadId)
            _mutedThreadsSet.insert(threadId)
            notify(.mute_thread(ev))
        }
    }
}
