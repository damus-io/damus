//
//  SuggestedHashtagsView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-10-09.
//

import SwiftUI

// Currently we have a hardcoded list of possible hashtags that might be nice to suggest,
// and we suggest the top-N ones most active in the past day.
// This might be simple and effective until we find a more sophisticated way to let the user discover new hashtags
let DEFAULT_SUGGESTED_HASHTAGS: [String] = [
    "grownostr", "damus", "zapathon", "introductions", "plebchain", "bitcoin", "food",
    "coffeechain", "nostr", "asknostr", "bounty", "freedom", "freedomtech", "foodstr",
    "memestr", "memes", "music", "musicstr", "art", "artstr"
]

struct SuggestedHashtagsView: View {
    struct HashtagWithUserCount: Hashable {
        var hashtag: String
        var count: Int
    }
    
    let damus_state: DamusState
    @StateObject var events: EventHolder
    @SceneStorage("SuggestedHashtagsView.show_suggested_hashtags") var show_suggested_hashtags : Bool = true
    var item_limit: Int?
    let suggested_hashtags: [String]
    var hashtags_with_count_to_display: [HashtagWithUserCount] {
        get {
            let all_items = self.suggested_hashtags
                .map({ hashtag in
                    return HashtagWithUserCount(
                        hashtag: hashtag,
                        count: self.users_talking_about(hashtag: Hashtag(hashtag: hashtag))
                    )
                })
                .sorted(by: { a, b in
                    a.count > b.count
                })
            guard let item_limit else {
                return all_items
            }
            return Array(all_items.prefix(item_limit))
        }
    }
    
    init(damus_state: DamusState, suggested_hashtags: [String]? = nil, max_items item_limit: Int? = nil, events: EventHolder) {
        self.damus_state = damus_state
        self.suggested_hashtags = suggested_hashtags ?? DEFAULT_SUGGESTED_HASHTAGS
        self.item_limit = item_limit
        _events = StateObject.init(wrappedValue: events)
    }
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "sparkles")
                Text("Suggested hashtags", comment: "A label indicating that the items below it are suggested hashtags")
                Spacer()
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        show_suggested_hashtags.toggle()
                    }
                }) {
                    if show_suggested_hashtags {
                        Image(systemName: "rectangle.compress.vertical")
                            .foregroundStyle(PinkGradient)
                    } else {
                        Image(systemName: "rectangle.expand.vertical")
                            .foregroundStyle(PinkGradient)
                    }
                }
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 10)
            
            if show_suggested_hashtags {
                ForEach(hashtags_with_count_to_display,
                        id: \.self) { hashtag_with_count in
                    SuggestedHashtagView(damus_state: damus_state, hashtag: hashtag_with_count.hashtag, count: hashtag_with_count.count)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private struct SuggestedHashtagView: View { // Purposefully private to SuggestedHashtagsView because it assumes the same 24h window
        let damus_state: DamusState
        let hashtag: String
        let count: Int
        
        init(damus_state: DamusState, hashtag: String, count: Int) {
            self.damus_state = damus_state
            self.hashtag = hashtag
            self.count = count
        }
        
        var body: some View {
            HStack {
                SingleCharacterAvatar(character: "#")
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: "#\(hashtag)")
                        .bold()
                    
                    let pluralizedString = pluralizedString(key: "users_talking_about_it", count: self.count)
                    Text(pluralizedString)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .onTapGesture {
                let search_model = SearchModel(state: damus_state, search: NostrFilter.init(hashtag: [hashtag]))
                damus_state.nav.push(route: Route.Search(search: search_model))
            }
        }
    }
    
    func users_talking_about(hashtag: Hashtag) -> Int {
        return self.events.all_events
            .filter({ $0.referenced_hashtags.contains(hashtag)})
            .reduce(Set<Pubkey>([]), { authors, note in
                return authors.union([note.pubkey])
            })
            .count
    }
}

struct SuggestedHashtagsView_Previews: PreviewProvider {
    static var previews: some View {
        let time_window: TimeInterval = 24 * 60 * 60 // 1 day
        let search_model = SearchModel(
            state: test_damus_state,
            search: NostrFilter.init(
                since: UInt32(Date.now.timeIntervalSince1970 - time_window),
                hashtag: ["nostr", "bitcoin", "zapathon"]
            )
        )
        
        SuggestedHashtagsView(
            damus_state: test_damus_state,
            events: search_model.events
        )
    }
}

