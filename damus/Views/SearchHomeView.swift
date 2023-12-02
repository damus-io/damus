//
//  SearchHomeView.swift
//  damus
//
//  Created by William Casarin on 2022-05-19.
//

import SwiftUI
import CryptoKit
import NaturalLanguage

struct SearchHomeView: View {
    let damus_state: DamusState
    @StateObject var model: SearchHomeModel
    @State var search: String = ""
    @FocusState private var isFocused: Bool

    var content_filter: (NostrEvent) -> Bool {
        let filters = ContentFilters.defaults(damus_state: self.damus_state)
        return ContentFilters(filters: filters).filter
    }

    let preferredLanguages = Set(Locale.preferredLanguages.map { localeToLanguage($0) })
    
    var SearchInput: some View {
        HStack {
            HStack{
                Image("search")
                    .foregroundColor(.gray)
                TextField(NSLocalizedString("Search...", comment: "Placeholder text to prompt entry of search query."), text: $search)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
            }
            .padding(10)
            .background(.secondary.opacity(0.2))
            .cornerRadius(20)
            
            if(!search.isEmpty) {
                Text("Cancel", comment: "Cancel out of search view.")
                    .foregroundColor(.accentColor)
                    .padding(EdgeInsets(top: 0.0, leading: 0.0, bottom: 0.0, trailing: 10.0))
                    .onTapGesture {
                        self.search = ""
                        isFocused = false
                    }
            }
        }
    }
    
    var GlobalContent: some View {
        return TimelineView<AnyView>(
            events: model.events,
            loading: $model.loading,
            damus: damus_state,
            show_friend_icon: true,
            filter: { ev in
                if !content_filter(ev) {
                    return false
                }
                
                if damus_state.muted_threads.isMutedThread(ev, keypair: self.damus_state.keypair) {
                    return false
                }

                if damus_state.settings.show_only_preferred_languages == false {
                    return true
                }

                // If we can't determine the note's language with 50%+ confidence, lean on the side of caution and show it anyway.
                let note_lang = damus_state.events.get_cache_data(ev.id).translations_model.note_language
                guard let note_lang else {
                    return true
                }

                return preferredLanguages.contains(note_lang)
            },
            content: {
                AnyView(VStack {
                    SuggestedHashtagsView(damus_state: damus_state, max_items: 5, events: model.events)
                    
                    Divider()
                        .frame(height: 1)
                    
                    HStack {
                        Image("notes.fill")
                        Text(NSLocalizedString("All recent notes", comment: "A label indicating that the notes being displayed below it are all recent notes"))
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
                    .padding(.horizontal)
                })
            }
        )
        .refreshable {
            // Fetch new information by unsubscribing and resubscribing to the relay
            model.unsubscribe()
            model.subscribe()
        }
    }
    
    var SearchContent: some View {
        SearchResultsView(damus_state: damus_state, search: $search)
            .refreshable {
                // Fetch new information by unsubscribing and resubscribing to the relay
                model.unsubscribe()
                model.subscribe()
            }
    }
    
    var MainContent: some View {
        Group {
            if search.isEmpty {
                GlobalContent
            } else {
                SearchContent
            }
        }
    }
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            MainContent
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                SearchInput
                    //.frame(maxWidth: 275)
                    .padding()
                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .onReceive(handle_notify(.new_mutes)) { _ in
            self.model.filter_muted()
        }
        .onAppear {
            if model.events.events.isEmpty {
                model.subscribe()
            }
        }
        .onDisappear {
            model.unsubscribe()
        }
    }
}

struct SearchHomeView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        SearchHomeView(damus_state: state, model: SearchHomeModel(damus_state: state))
    }
}
