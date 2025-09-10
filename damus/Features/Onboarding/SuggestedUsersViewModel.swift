//
//  SuggestedUsersViewModel.swift
//  damus
//
//  Created by klabo on 7/17/23.
//

import Foundation
import Combine

/// This model does the following:
///
/// - It loads follow packs (From the network, with a local copy fallback), and related profiles
/// - It tracks the interests and disinterests as selected by the user via an interface
/// - It computes publishes suggestions for users based on selected interests
@MainActor
class SuggestedUsersViewModel: ObservableObject {
    /// The Damus State
    public let damus_state: DamusState
    
    /// Keeps all the suggested follow packs available. For internal use only.
    private var allSuggestions: [FollowPackEvent]? = nil {
        didSet { self.recomputeSuggestions() }
    }
    
    /// The user-selected topics of interests
    @Published var interests: Set<Interest> = [] {
        didSet {
            self.recomputeSuggestions()
            if interests.contains(.bitcoin) {
                // Ensures there are no setting contradictions if user goes back and forth on onboarding
                reduceBitcoinContent = false
            }
        }
    }
    /// A user preference that allows users to reduce bitcoin content
    @Published var reduceBitcoinContent: Bool {
        didSet {
            self.recomputeDisinterests()
            damus_state.settings.reduce_bitcoin_content = reduceBitcoinContent
        }
    }
    @Published private(set) var disinterests: Set<Interest> = [] {
        didSet { self.recomputeSuggestions() }
    }
    
    /// Keeps the suggested follow packs to the user.
    ///
    /// ## Implementation notes
    ///
    /// This is technically meant to be a computed property (see `recomputeSuggestions`),
    /// but we also want views that display this to be automatically updated,
    /// so therefore we use `@Published` instead, and add property write observers on its logical dependencies
    @Published private(set) var suggestions: [FollowPackEvent]? = nil
    
    /// A map of suggested pubkeys and the particular interest categories they belong to
    private(set) var interestUserMap: [Pubkey: Set<Interest>] = [:]
    
    
    // MARK: - Helper types
    
    typealias FollowPackID = String
    typealias Interest = DIP06.Interest
    
    
    // MARK: - Initialization

    init(damus_state: DamusState) throws {
        self.damus_state = damus_state
        self.reduceBitcoinContent = damus_state.settings.reduce_bitcoin_content
        self.recomputeAll()
        Task.detached {
            await self.loadSuggestedFollowPacks()
        }
    }
    
    
    // MARK: - External interface methods

    /// Gets suggested user information from a provided pubkey
    func suggestedUser(pubkey: Pubkey) -> SuggestedUser? {
        let profile_txn = damus_state.profiles.lookup(id: pubkey)
        if let profile = profile_txn?.unsafeUnownedValue,
           let user = SuggestedUser(name: profile.name, about: profile.about, picture: profile.picture, pubkey: pubkey) {
            return user
        }
        return nil
    }

    /// Allows the user to follow a list of other users
    func follow(pubkeys: [Pubkey]) {
        for pubkey in pubkeys {
            notify(.follow(.pubkey(pubkey)))
        }
    }
    
    
    // MARK: - Internal state management logic
    
    /// State management function that recomputes all "computed" properties
    ///
    /// This helps ensure views get instant updates everytime the suggestions are supposed to be updated.
    private func recomputeAll() {
        self.recomputeDisinterests()
        self.recomputeSuggestions()
    }
    
    /// State management function that recomputes `disinterests` based its logical dependencies
    ///
    /// This helps ensure views get instant updates everytime the suggestions are supposed to be updated.
    private func recomputeDisinterests() {
        self.disinterests = reduceBitcoinContent ? Set([.bitcoin]) : []
    }
    
    /// State management function that recomputes `suggestions` based its logical dependencies
    ///
    /// This helps ensure views get instant updates everytime the suggestions are supposed to be updated.
    private func recomputeSuggestions() {
        self.suggestions = Self.computeSuggestions(basedOn: allSuggestions, interests: interests, disinterests: disinterests)
    }
    
    /// Purely functional function that computes suggestions based on the ones available, and the user's interest selections
    private static func computeSuggestions(basedOn allSuggestions: [FollowPackEvent]?, interests: Set<Interest>, disinterests: Set<Interest>) -> [FollowPackEvent]? {
        guard let allSuggestions else { return nil }
        return allSuggestions.filter({ suggestion in
            return !suggestion.interests.intersection(interests).isEmpty && suggestion.interests.intersection(disinterests).isEmpty
        })
    }
    
    // MARK: - Internal loading logic
    
    /// Loads suggestions
    ///
    /// (This is the main loading function that kicks-off the others)
    ///
    /// ## Usage notes
    ///
    /// - Long running task, preferably use this as a detached task
    private func loadSuggestedFollowPacks() async {
        // First, try preload events from the local file (To have a fallback in the case of an unstable internet connection)
        var packsById = await self.loadLocalSuggestedFollowPacks()
        
        // Then fetch the newest follow packs from the network and overwrite old ones where necessary
        let subscriptionTask = Task {
            await self.loadSuggestedFollowPacksFromNetwork(packsById: &packsById)
        }

        // Wait for 5 seconds before timing out
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        // Cancel the subscription task on timeout, to make sure we don't load forever
        subscriptionTask.cancel()
        
        // Finish loading and computing suggestions, as well as profile info
        let allPacks = Array(packsById.values)
        self.allSuggestions = allPacks
        await self.loadProfiles(for: allPacks)
    }
    
    /// Load the local follow packs, to have a fallback in the case of network instability
    ///
    /// ## Implementation notes
    ///
    /// This might seem redundant, but onboarding is a crucial moment for users, so we need to make sure they are onboarded successfully.
    private func loadLocalSuggestedFollowPacks() async -> [FollowPackID: FollowPackEvent] {
        var packsById: [String: FollowPackEvent] = [:]
        
        if let bundleURL = Bundle.main.url(forResource: "follow-packs", withExtension: "jsonl"),
           let jsonlData = try? Data(contentsOf: bundleURL),
           let jsonlString = String(data: jsonlData, encoding: .utf8) {
            
            let lines = jsonlString.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                if let note = NdbNote.owned_from_json(json: line) {
                    let followPack = FollowPackEvent.parse(from: note)
                    if let id = followPack.uuid {
                        packsById[id] = followPack
                    }
                }
            }
        }
        
        return packsById
    }
    
    /// Loads the newest follow packs from the network, and overwrites the provided follow packs where appropriate
    private func loadSuggestedFollowPacksFromNetwork(packsById: inout [FollowPackID: FollowPackEvent]) async {
        let filter = NostrFilter(
            kinds: [NostrKind.follow_list],
            authors: [Constants.ONBOARDING_FOLLOW_PACK_CURATOR_PUBKEY]
        )
        
        for await item in self.damus_state.nostrNetwork.reader.subscribe(filters: [filter]) {
            // Check for cancellation on each iteration
            guard !Task.isCancelled else { break }

            switch item {
            case .event(let lender):
                lender.justUseACopy({ event in
                    let followPack = FollowPackEvent.parse(from: event)
                    
                    guard let id = followPack.uuid else { return }
                    
                    let latestPackForThisId: FollowPackEvent
                    
                    if let existingPack = packsById[id], existingPack.event.created_at > followPack.event.created_at {
                        latestPackForThisId = existingPack
                    } else {
                        latestPackForThisId = followPack
                    }
                    
                    packsById[id] = latestPackForThisId
                })
            case .eose:
                break
            }
        }
    }

    /// Finds all profiles mentioned in the follow packs, and loads the profile data from the network
    private func loadProfiles(for packs: [FollowPackEvent]) async {
        var allPubkeys: [Pubkey] = []
        
        for followPack in packs {
            for pubkey in followPack.publicKeys {
                self.interestUserMap[pubkey] = Set(Array(self.interestUserMap[pubkey] ?? []) + Array(followPack.interests))
                allPubkeys.append(pubkey)
            }
        }
        
        let profileFilter = NostrFilter(kinds: [.metadata], authors: allPubkeys)
        for await item in damus_state.nostrNetwork.reader.subscribe(filters: [profileFilter]) {
            switch item {
            case .event(_):
                continue    // We just need NostrDB to ingest these for them to be available elsewhere, no need to analyze the data
            case .eose:
                break
            }
        }
    }
}
