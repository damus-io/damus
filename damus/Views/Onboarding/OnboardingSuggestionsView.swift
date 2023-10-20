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

    @Environment(\.presentationMode) private var presentationMode
    
    func next_page() {
        withAnimation {
            current_page += 1
        }
    }

    var body: some View {
        NavigationView {
            TabView(selection: $current_page) {
                SuggestedUsersPageView(model: model, next_page: self.next_page)
                    .navigationTitle(NSLocalizedString("Who to Follow", comment: "Title for a screen displaying suggestions of who to follow"))
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarItems(leading: Button(action: {
                        self.next_page()
                    }, label: {
                        Text(NSLocalizedString("Skip", comment: "Button to dismiss the suggested users screen"))
                            .font(.subheadline.weight(.semibold))
                    }))
                    .tag(0)
                
                PostView(
                    action: .posting(.user(model.damus_state.pubkey)),
                    damus_state: model.damus_state, 
                    prompt_view: {
                        AnyView(
                            HStack {
                                Image(systemName: "sparkles")
                                Text(NSLocalizedString("Add your first post", comment: "Prompt given to the user during onboarding, suggesting them to write their first post"))
                            }
                                .foregroundColor(.secondary)
                                .font(.callout)
                                .padding(.top, 10)
                        )
                    },
                    placeholder_messages: self.first_post_examples,
                    initial_text_suffix: self.initial_text_suffix
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}

fileprivate struct SuggestedUsersPageView: View {
    var model: SuggestedUsersViewModel
    var next_page: (() -> Void)
    
    var body: some View {
        VStack {
            List {
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.users, id: \.self) { pk in
                            if let user = model.suggestedUser(pubkey: pk) {
                                SuggestedUserView(user: user, damus_state: model.damus_state)
                            }
                        }
                    } header: {
                        SuggestedUsersSectionHeader(group: group, model: model)
                    }
                }
            }
            .listStyle(.plain)
            
            Spacer()
            
            Button(action: {
                self.next_page()
            }) {
                Text(NSLocalizedString("Continue", comment: "Button to dismiss suggested users view and continue to the main app"))
                    .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle())
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
        }
    }
}

struct SuggestedUsersSectionHeader: View {
    let group: SuggestedUserGroup
    let model: SuggestedUsersViewModel
    var body: some View {
        HStack {
            Text(group.title.uppercased())
            Spacer()
            Button(NSLocalizedString("Follow All", comment: "Button to follow all users in this section")) {
                model.follow(pubkeys: group.users)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

struct SuggestedUsersView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingSuggestionsView(model: SuggestedUsersViewModel(damus_state: test_damus_state))
    }
}
