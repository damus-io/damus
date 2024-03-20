//
//  PullDownSearch.swift
//  damus
//
//  Created by William Casarin on 2023-12-03.
//

import Foundation

import SwiftUI

struct PullDownSearchView: View {
    let debouncer: Debouncer = Debouncer(interval: 0.25)
    let state: DamusState
    
    @Binding var search_text: String
    @Binding var results: [NostrEvent]
    @FocusState private var isFocused: Bool
    
    func do_search(query: String) {
        let limit = 16
        var note_keys = state.ndb.text_search(query: query, limit: limit, order: .newest_first)
        var res = [NostrEvent]()
        // TODO: fix duplicate results from search
        var keyset = Set<NoteKey>()

        // try reverse because newest first is a bit buggy on partial searches
        if note_keys.count == 0 {
            // don't touch existing results if there are no new ones
            return
        }

        do {
            guard let txn = NdbTxn(ndb: state.ndb) else { return }
            for note_key in note_keys {
                guard let note = state.ndb.lookup_note_by_key_with_txn(note_key, txn: txn) else {
                    continue
                }

                if !keyset.contains(note_key) {
                    let owned_note = note.to_owned()
                    res.append(owned_note)
                    keyset.insert(note_key)
                }
            }
        }

        let res_ = res

        Task { @MainActor [res_] in
            results = res_
        }
    }
    
    var SearchInput: some View {
        HStack {
            HStack{
                Image("search")
                    .foregroundColor(.gray)
                TextField(NSLocalizedString("Search", comment: "Placeholder text to prompt entry of search query."), text: $search_text)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .onChange(of: search_text) { query in
                        debouncer.debounce {
                            Task.detached {
                                do_search(query: query)
                            }
                        }
                    }
            }
            .padding(7)
            .background(.secondary.opacity(0.2))
            .cornerRadius(15)
            
            if(!search_text.isEmpty || isFocused) {
                Button(action: {
                    search_text = ""
                    isFocused = false
                    results = []
                }, label: {
                    Text("Cancel", comment: "Button to cancel out of search text entry mode.")
                })
            }
        }
        .padding([.horizontal, .top], 10)
    }

    var body: some View {
        VStack(alignment: .leading) {
            SearchInput
        }
    }
}

struct PullDownSearchView_Previews: PreviewProvider {
    static var previews: some View {
        PullDownSearchView(state: test_damus_state, search_text: .constant(""), results: .constant([]))
    }
}
