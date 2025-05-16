//
//  SuggestedUsersViewModel.swift
//  damus
//
//  Created by klabo on 7/17/23.
//

import Foundation
import Combine


struct SuggestedUserGroup: Identifiable, Codable {
    var id: String { category }
    let category: String
    let users: [Pubkey]

    enum CodingKeys: String, CodingKey {
        case category, users
    }
    
    /// Returns user groups where
    static func from(suggestions: UserSuggestions) -> [SuggestedUserGroup] {
        var groups: [String: [Pubkey]] = [:]
        for (pubkey, categories) in suggestions {
            for category in categories {
                groups[category, default: []].append(pubkey)
            }
        }
        return groups.map({ (category, users) in
            return SuggestedUserGroup(category: category, users: users)
        })
    }
}

typealias UserSuggestions = [Pubkey: Set<String>]
typealias UserSuggestionsEncoded = [String: Set<String>]

func filter(suggestions: UserSuggestions, interests: Set<String>, disinterests: Set<String>) -> UserSuggestions {
    return suggestions.filter({ (pubkey, categories) in
        return !categories.intersection(interests).isEmpty && categories.intersection(disinterests).isEmpty
    })
}

@MainActor
class SuggestedUsersViewModel: ObservableObject {

    public let damus_state: DamusState
    
    @Published var allSuggestions: [FollowPackEvent]? = nil
    var suggestions: [FollowPackEvent]? {
        guard let allSuggestions else { return nil }
        return allSuggestions.filter({ suggestion in
            return !suggestion.interests.intersection(self.interests).isEmpty && suggestion.interests.intersection(self.disinterests).isEmpty
        })
    }
    var interestUserMap: [Pubkey: Set<Interest>] = [:]
    @Published var interests: Set<Interest> = []
    @Published var disinterests: Set<Interest> = []

    private let sub_id = UUID().uuidString

    init(damus_state: DamusState) throws {
        self.damus_state = damus_state
        Task {
            await self.loadSuggestedFollowPacks()
        }
    }

    func suggestedUser(pubkey: Pubkey) -> SuggestedUser? {
        let profile_txn = damus_state.profiles.lookup(id: pubkey)
        if let profile = profile_txn?.unsafeUnownedValue,
           let user = SuggestedUser(name: profile.name, about: profile.about, picture: profile.picture, pubkey: pubkey) {
            return user
        }
        return nil
    }

    func follow(pubkeys: [Pubkey]) {
        for pubkey in pubkeys {
            notify(.follow(.pubkey(pubkey)))
        }
    }

    private func loadSuggestedFollowPacks() async {
        var followPacks = [FollowPackEvent]()
        let filter = NostrFilter(
            kinds: [NostrKind.follow_list],
            authors: [Constants.ONBOARDING_FOLLOW_PACK_CURATOR_PUBKEY]
        )

        // Create a task to process the subscription
        let subscriptionTask = Task {
            for await item in self.damus_state.nostrNetwork.reader.subscribe(filters: [filter]) {
                // Check for cancellation on each iteration
                guard !Task.isCancelled else { break }

                switch item {
                case .event(let borrow):
                    try? borrow { event in
                        let followPack = FollowPackEvent.parse(from: event.toOwned())
                        followPacks.append(followPack)
                        for pubkey in followPack.publicKeys {
                            self.interestUserMap[pubkey] = Set(Array(self.interestUserMap[pubkey] ?? []) + Array(followPack.interests))
                        }
                    }
                case .eose:
                    break
                }
            }
        }

        // Wait for 5 seconds before timing out
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        // Cancel the subscription task on timeout
        subscriptionTask.cancel()
        
        self.allSuggestions = followPacks
        
        let pubkeys = getPubkeys(suggestions: followPacks)
        let profileFilter = NostrFilter(kinds: [.metadata], authors: pubkeys)
        for await item in damus_state.nostrNetwork.reader.subscribe(filters: [profileFilter]) {
            switch item {
            case .event(borrow: let borrow):
                continue    // We just need NostrDB to ingest these
            case .eose:
                break
            }
        }
    }
    
    enum UserSuggestionLoadingErrorReason: Error {
        case fileNotFound
        case decodingFailed
    }

    private func getPubkeys(suggestions: [FollowPackEvent]) -> [Pubkey] {
        var allPubkeys: [Pubkey] = []
        for suggestion in suggestions {
            allPubkeys.append(contentsOf: suggestion.publicKeys)
        }
        return allPubkeys
    }
}
