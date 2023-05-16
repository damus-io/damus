//
//  TwitterUserSearchView.swift
//  damus
//
//  Created by Joel Klabo on 5/10/23.
//

import SwiftUI
import Kingfisher

struct User: Identifiable {
    let id: Int
    let username: String
}

struct TwitterUserSearchView: View {
    
    let state: DamusState
    
    @StateObject private var model = TwitterUserSearchModel()

    
    private let pinkGradient = LinearGradient(gradient:
                                                Gradient(colors: [Color(#colorLiteral(red: 0.8274509804, green: 0.2980392157, blue: 0.8509803922, alpha: 1)), Color(#colorLiteral(red: 0.9764705882, green: 0.4117647059, blue: 0.7137254902, alpha: 1))]),
                                              startPoint: .top,
                                              endPoint: .bottom)
        
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack {
            
            TwitterSearchBar(searchText: $model.searchText)
            
            Group {
                switch model.state {
                case .empty:
                    Group {
                        Spacer()
                        Text("No results")
                    }
                case .loading:
                    Group {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: DamusColors.purple))
                    }
                case .results(let results):
                    Group {
                        List(results) { user in
                            HStack {
                                if case .pub(let pubkey) = decode_bech32_key(user.id) {
                                    let target = FollowTarget.pubkey(pubkey)
                                    InnerProfilePicView(url: URL(string: user.profile),
                                                        fallbackUrl: nil,
                                                        pubkey: target.pubkey,
                                                        size: 42,
                                                        highlight: .none,
                                                        disable_animation: false)
                                    Text(user.twitter_handle)
                                    Spacer()
                                    GradientFollowButton(target: target, follows_you: false, follow_state: state.contacts.follow_state(target.pubkey))
                                } else {
                                    EmptyView()
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                case .error(let error):
                    Group {
                        Spacer()
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                    }
                }
                
            }
            
            Spacer()
            
            Group {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .font(.callout.weight(.semibold))
                        .padding([.top, .bottom], 10)
                        .padding([.leading, .trailing], 12)
                        .background(pinkGradient)
                        .cornerRadius(12)
                }
                .padding([.leading, .trailing], 24)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Who to follow")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: Button(action: {
            if case let .results(users) = model.state {
                for user in users {
                    if case .pub(let pubkey) = decode_bech32_key(user.id) {
                        if state.contacts.follow_state(pubkey) == .unfollows {
                            let target: FollowTarget = .pubkey(pubkey)
                            notify(.follow, target)
                        }
                    }
                }
            }
        }, label: {
            Text("Follow All")
                .foregroundColor(Color(#colorLiteral(red: 0.8274509804, green: 0.2980392157, blue: 0.8509803922, alpha: 1)))
                .font(.subheadline.weight(.semibold))
        }))
    }
}

struct TwitterUserSearchView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        NavigationView {
            TwitterUserSearchView(state: ds)
        }
    }
}
