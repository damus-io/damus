//
//  SuggestedUsersView.swift
//  damus
//
//  Created by klabo on 7/17/23.
//

import SwiftUI

struct SuggestedUsersView: View {

    @StateObject var model: SuggestedUsersViewModel

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
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
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text(NSLocalizedString("Continue", comment: "Button to dismiss suggested users view and continue to the main app"))
                        .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(GradientButtonStyle())
                .padding([.leading, .trailing], 24)
                .padding(.bottom, 16)
            }
            .navigationTitle(NSLocalizedString("Who to Follow", comment: "Title for a screen displaying suggestions of who to follow"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(action: {
                presentationMode.wrappedValue.dismiss()
            }, label: {
                Text(NSLocalizedString("Skip", comment: "Button to dismiss the suggested users screen"))
                    .font(.subheadline.weight(.semibold))
            }))
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
        SuggestedUsersView(model: SuggestedUsersViewModel(damus_state: test_damus_state()))
    }
}
