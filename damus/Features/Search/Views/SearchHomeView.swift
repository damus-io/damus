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

    /// The advanced query the filter sheet edits.
    ///
    /// Seeded from ``search`` every time the sheet opens and rendered back into it
    /// when the sheet runs, so the sheet really is a front-end to the same query
    /// the text field expresses rather than a second place to say things.
    @State private var advancedQuery = AdvancedSearchQuery()
    @State private var filtersPresented = false

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
    }

    /// Resolves a `from:` name against the local profile index, the same path the
    /// existing profile search uses.
    private func resolveAuthor(_ name: String) -> Pubkey? {
        search_profiles(profiles: damus_state.profiles, contacts: damus_state.contacts, search: name).first
    }

    private func authorToken(_ pubkey: Pubkey) -> String {
        let profile = try? damus_state.profiles.lookup(id: pubkey)
        let name = Profile.displayName(profile: profile, pubkey: pubkey).username
        return AdvancedSearchQueryDSL.friendlyAuthorToken(for: pubkey, name: name, resolve: resolveAuthor)
    }

    /// The filter button, badged so an active author or date window is never
    /// invisible.
    ///
    /// On the search input's trailing edge rather than in a bottom accessory: the
    /// pane's bottom is already spoken for by `TimelineFilterAccessory` on iOS 26.
    var FilterButton: some View {
        let query = AdvancedSearchQueryDSL.parse(search, resolveAuthor: resolveAuthor).query
        let count = AdvancedSearchConstraint.all(in: query).filter(\.isFilter).count

        return Button(action: {
            advancedQuery = AdvancedSearchQueryDSL.parse(search, resolveAuthor: resolveAuthor).query
            filtersPresented = true
        }) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title2)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(verbatim: "\(count)")
                            .font(.caption2)
                            .padding(4)
                            .background(Circle().fill(Color.accentColor))
                            .foregroundColor(.white)
                            .offset(x: 8, y: -6)
                    }
                }
        }
        .accessibilityLabel(NSLocalizedString("Search filters", comment: "Accessibility label for the button that opens the advanced search filters."))
    }

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

            FilterButton

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
            filter: content_filter(FilterState.posts),
            content: {
                AnyView(VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(PinkGradient)
                        Text("Follow Packs", comment: "A label indicating that the items below it are follow packs")
                            .foregroundStyle(PinkGradient)
                    }
                    .padding(.top)
                    .padding(.horizontal)
                    
                    FollowPackTimelineView<AnyView>(events: model.followPackEvents, loading: $model.loading, damus: damus_state, show_friend_icon: true, filter: content_filter(FilterState.follow_list)
                    ).padding(.bottom)
                    
                    Divider()
                        .frame(height: 1)
                    
                    HStack {
                        Image("notes.fill")
                        Text("All recent notes", comment: "A label indicating that the notes being displayed below it are all recent notes")
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
                    .padding(.horizontal)
                }.padding(.bottom, 50))
            }
        )
    }
    
    var SearchContent: some View {
        SearchResultsView(damus_state: damus_state, search: $search)
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
        .sheet(isPresented: $filtersPresented) {
            AdvancedSearchFilterSheet(damus_state: damus_state, query: $advancedQuery, onSearch: {
                // Render the query back into the field before navigating, so
                // the sheet and the text field stay the same query rather than
                // two descriptions of it that can disagree.
                isFocused = false
                search = AdvancedSearchQueryDSL.render(advancedQuery, authorToken: authorToken)
                guard !advancedQuery.isTrivial else { return }
                damus_state.nav.push(route: .AdvancedSearch(model: AdvancedSearchModel(damus_state: damus_state, query: advancedQuery)))
            })
        }
        .task {
            await model.load()
        }
    }
}

struct SearchHomeView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        SearchHomeView(damus_state: state, model: SearchHomeModel(damus_state: state))
    }
}
