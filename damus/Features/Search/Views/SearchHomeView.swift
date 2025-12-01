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
    @State var loadingTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)
        return ContentFilters(filters: filters).filter
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
                    
                    // Show a lightweight skeleton while we fetch follow packs.
                    if model.loading {
                        FollowPackLoadingPlaceholder()
                            .shimmer(!reduceMotion)
                            .padding(.horizontal)
                            .padding(.bottom)
                    } else {
                        FollowPackTimelineView<AnyView>(events: model.followPackEvents, loading: $model.loading, damus: damus_state, show_friend_icon: true, filter: content_filter(FilterState.follow_list)
                        ).padding(.bottom)
                    }
                    
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
        .onAppear {
            if model.events.events.isEmpty {
                loadingTask = Task { await model.load() }
            }
        }
        .onDisappear {
            loadingTask?.cancel()
        }
    }
}

struct SearchHomeView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        SearchHomeView(damus_state: state, model: SearchHomeModel(damus_state: state))
    }
}

/// Skeleton for the follow-pack rail used on the Universe view while data loads.
private struct FollowPackLoadingPlaceholder: View {
    private let rows = 3
    private var pillColor: Color { DamusColors.adaptableGrey.opacity(0.3) }
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { _ in
                FollowPackSkeletonRow(pillColor: pillColor)
            }
        }
        .accessibilityHidden(true) // Visual affordance only; Timeline skeleton already exposed accessibility labels.
    }
}

private struct FollowPackSkeletonRow: View {
    let pillColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(pillColor)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                skeletonLine(relativeWidth: 0.5, height: 10)
                    .opacity(0.85)
                skeletonLine(relativeWidth: 0.32, height: 8)
            }
            
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pillColor.opacity(0.25)))
    }
    
    private func skeletonLine(relativeWidth: CGFloat, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let targetWidth = max(60, proxy.size.width * relativeWidth)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(pillColor)
                .frame(width: targetWidth, height: height, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
    }
}
