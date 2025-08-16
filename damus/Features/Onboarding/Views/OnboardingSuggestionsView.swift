//
//  OnboardingSuggestionsView.swift
//  damus
//
//  Created by klabo on 7/17/23.
//

import SwiftUI

fileprivate let first_post_example_1: String = NSLocalizedString("Hello everybody!\n\nThis is my first post on Damus, I am happy to meet you all 🤙. What’s up?\n\n#introductions", comment: "First post example given to the user during onboarding, as a suggestion as to what they could post first")
fileprivate let first_post_example_2: String = NSLocalizedString("This is my first post on Nostr 💜. I love drawing and folding Origami!\n\nNice to meet you all! #introductions #plebchain ", comment: "First post example given to the user during onboarding, as a suggestion as to what they could post first")
fileprivate let first_post_example_3: String = NSLocalizedString("For #Introductions! I’m a software developer.\n\nMy side interests include languages and I am striving to be a #polyglot - I am a native English speaker and can speak French, German and Japanese.", comment: "First post example given to the user during onboarding, as a suggestion as to what they could post first")
fileprivate let first_post_example_4: String = NSLocalizedString("Howdy! I’m a graphic designer during the day and coder at night, but I’m also trying to spend more time outdoors.\n\nHope to meet folks who are on their own journeys to a peaceful and free life!", comment: "First post example given to the user during onboarding, as a suggestion as to what they could post first")

struct OnboardingSuggestionsView: View {

    @StateObject var model: SuggestedUsersViewModel
    @State var current_page: Int = 0
    let first_post_examples: [String] = [first_post_example_1, first_post_example_2, first_post_example_3, first_post_example_4]
    let initial_text_suffix: String = "\n\n#introductions"

    @Environment(\.dismiss) var dismiss
    
    func next_page() {
        withAnimation {
            current_page += 1
        }
    }
    
    private var canLeaveInterestSelectionPage: Bool {
        let count = model.interests.count
        return count > 0
    }
    
    /// Save the user's selected interests to NDB
    private func saveInterestsToNdb() {
        // Convert the selected interests to hashtags for the NIP51 interest list
        let interestItems = model.interests.map { interest in
            NIP51.InterestList.InterestItem.hashtag(interest.rawValue)
        }
        
        // Create the interest list
        let interestList = NIP51.InterestList(interests: Array(interestItems))
        
        // Convert to a NostrEvent and send to NDB
        guard let keypair = model.damus_state.keypair.to_full(),
              let event = interestList.toNostrEvent(keypair: keypair, timestamp: nil) else {
            return      // Not a big deal, fail silently
        }
        
        // Send the event to NostrDB to allow us to retrieve later
        // Did not send this to the network yet because:
        // 1. I believe we should add an opt-out/opt-in button.
        // 2. If we do, and the user accepts to share it, it will be an awkward situation considering:
        //     - We don't show that anywhere else yet
        //     - We don't have other mechanisms to allow the user to edit this yet
        //
        // Therefore, it is better to just save it locally, and retrieve this once we build out https://github.com/damus-io/damus/issues/3042
        model.damus_state.nostrNetwork.sendToNostrDB(event: event)
    }

    var body: some View {
        NavigationView {
            TabView(selection: $current_page) {
                InterestSelectionView(damus_state: model.damus_state, next_page: {
                    self.next_page()
                }, selectedInterests: $model.interests, isNextEnabled: canLeaveInterestSelectionPage)
                    .navigationTitle(NSLocalizedString("Select your interests", comment: "Title for a screen asking the user for interests"))
                    .navigationBarTitleDisplayMode(.inline)
                    .tag(0)
                
                if canLeaveInterestSelectionPage {
                    
                    OnboardingContentSettings(model: model, next_page: self.next_page, settings: model.damus_state.settings, selectedInterests: $model.interests)
                        .navigationTitle(NSLocalizedString("Content settings", comment: "Title for an onboarding screen showing user some content settings"))
                        .navigationBarTitleDisplayMode(.inline)
                        .tag(1)
                    
                    SuggestedUsersPageView(model: model, next_page: self.next_page)
                        .navigationTitle(NSLocalizedString("Who to Follow", comment: "Title for a screen displaying suggestions of who to follow"))
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarItems(leading: Button(action: {
                            self.next_page()
                        }, label: {
                            Text("Skip", comment: "Button to dismiss the suggested users screen")
                                .font(.subheadline.weight(.semibold))
                        })
                            .accessibilityIdentifier(AppAccessibilityIdentifiers.onboarding_sheet_skip_button.rawValue)
                        )
                        .tag(2)
                    
                    PostView(
                        action: .posting(.user(model.damus_state.pubkey)),
                        damus_state: model.damus_state,
                        prompt_view: {
                            AnyView(
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Add your first post", comment: "Prompt given to the user during onboarding, suggesting them to write their first post")
                                }
                                    .foregroundColor(.secondary)
                                    .font(.callout)
                                    .padding(.top, 10)
                            )
                        },
                        placeholder_messages: self.first_post_examples,
                        initial_text_suffix: self.initial_text_suffix
                    )
                    .onReceive(handle_notify(.post)) { _ in
                        // NOTE: Even though PostView already calls `dismiss`, that is not guaranteed to work under deeply nested views.
                        // Thus, we should also call `dismiss` from here (a direct subview of a sheet), which is explicitly supported by Apple.
                        // See https://github.com/damus-io/damus/issues/1726 for more context and information
                        dismiss()
                    }
                    .tag(3)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: current_page) { newPage in
                // If the user just swiped from the interests page (0) to the next page (1),
                // save their interests to NDB
                if newPage == 1 && current_page == 1 {
                    saveInterestsToNdb()
                }
            }
        }
    }
}

fileprivate struct SuggestedUsersPageView: View {
    var model: SuggestedUsersViewModel
    var next_page: (() -> Void)
    
    var body: some View {
        VStack {
            if let suggestions = model.suggestions {
                List {
                    ForEach(suggestions, id: \.self) { followPack in
                        Section {
                            ForEach(followPack.publicKeys, id: \.self) { pk in
                                if let usersInterests = model.interestUserMap[pk],
                                   !usersInterests.intersection(model.interests).isEmpty && usersInterests.intersection(model.disinterests).isEmpty,
                                   let user = model.suggestedUser(pubkey: pk) {
                                    SuggestedUserView(user: user, damus_state: model.damus_state)
                                }
                            }
                        } header: {
                            SuggestedUsersSectionHeader(followPack: followPack, model: model)
                        }
                    }
                }
                .listStyle(.plain)
            }
            else {
                ProgressView()
            }
            
            Spacer()
            
            Button(action: {
                self.next_page()
            }) {
                Text("Continue", comment: "Button to dismiss suggested users view and continue to the main app")
                    .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
        }
    }
}

struct SuggestedUsersSectionHeader: View {
    let followPack: FollowPackEvent
    let model: SuggestedUsersViewModel
    var body: some View {
        HStack {
            Text(followPack.title ?? NSLocalizedString("Untitled Follow Pack", comment: "Default title for a follow pack if no title is specified"))
            Spacer()
            Button(NSLocalizedString("Follow All", comment: "Button to follow all users in this section")) {
                model.follow(pubkeys: followPack.publicKeys)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

struct SuggestedUsersView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingSuggestionsView(model: try! SuggestedUsersViewModel(damus_state: test_damus_state))
    }
}
