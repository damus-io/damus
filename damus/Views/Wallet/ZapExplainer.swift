//
//  ZapExplainer.swift
//  damus
//
//  Created by eric on 2/12/25.
//

import SwiftUI

struct ZapExplainerView: View {
    
    @Binding var show_introduction: Bool
    var nav: NavigationCoordinator
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack {
                Text("Get cash instantly from your followers", comment: "Feature description for receiving money instantly.")
                    .font(.veryLargeTitle)
                    .multilineTextAlignment(.center)
                    .padding(.top)
                
                VStack(alignment: .leading) {
                    GetPaid
                    Gift
                    GiveThanks
                }
                
                WhyZaps
                
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        FindWallet
                        
                        LinkAccount
                        
                        StartReceiving
                    }
                    .padding(5)
                }
                .scrollIndicators(.hidden)
                
                Button(action: {
                    show_introduction = false
                }) {
                    HStack {
                        Text("Set up wallet", comment: "Text for button to disconnect from Nostr Wallet Connect lightning wallet.")
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
                }
                .buttonStyle(GradientButtonStyle())
                .padding(.top, 30)
                
                Button(action: {
                    nav.popToRoot()
                }) {
                    HStack {
                        Text("Maybe later", comment: "Text for button to disconnect from Nostr Wallet Connect lightning wallet.")
                    }
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 18, alignment: .center)
                    .padding()
                }
                .buttonStyle(NeutralButtonStyle())
            }
            .padding(.bottom)
            .padding(.horizontal)
        }
        .scrollIndicators(.never)
        .background(
            Image("eula-bg")
                .resizable()
                .blur(radius: 70)
                .opacity(colorScheme == .light ? 0.6 : 1.0)
                .ignoresSafeArea(),
            alignment: .top
        )
    }
    
    var GetPaid: some View {
        self.benefitPoint(
            imageName: "zap.fill",
            heading: NSLocalizedString("Get paid for being you", comment: "Description for monetizing one's presence."),
            description: NSLocalizedString("Setting up Zaps lets people know you're ready to start receiving money.", comment: "Information about enabling payments.")
        )
    }
    
    var Gift: some View {
        self.benefitPoint(
            imageName: "gift",
            heading: NSLocalizedString("Let your fans show their support", comment: "Heading pointing out a benefit of connecting a lightning wallet."),
            description: NSLocalizedString("You drive the conversation and we want to make it easier for people to support your work beyond follows, reposts, and likes.", comment: "Text explaining the benefit of connecting a lightning wallet for content creators.")
        )
    }
    
    var GiveThanks: some View {
        self.benefitPoint(
            imageName: "gift",
            heading: NSLocalizedString("Give thanks", comment: "Heading explaining a benefit of connecting a lightning wallet."),
            description: NSLocalizedString("When supporters tip with Zaps, they can add a note and we can make it easy for you to instantly reply to show your gratitude.", comment: "Description explaining a benefit of connecting a lightning wallet.")
        )
    }
    
    func benefitPoint(imageName: String, heading: String, description: String) -> some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: {}, label: {
                    Image(imageName)
                        .resizable()
                        .frame(width: 25, height: 25)
                })
                .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), cornerRadius: 9999))
                .disabled(true)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text(heading)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(description)
                        .font(.body)
                }
                .padding(.top, 9)
            }
        }
        .padding(.top)
    }
    
    var WhyZaps: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Why add Zaps?", comment: "Heading to explain the benefits of zaps.")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Zaps are an easy way to support the incredible\nvoices that make up the conversation on nostr.\nHere's how it works", comment: "Describing the functional benefits of Zaps.")
                .lineLimit(4)
                .font(.body)
        }
        .padding(.top, 30)
    }
    
    var FindWallet: some View {
        self.WhyAddZapsBox(
            iconName: "wallet.fill",
            heading: NSLocalizedString("Find a Wallet", comment: "The heading for one of the \"Why add Zaps?\" boxes"),
            description: NSLocalizedString("Choose the third-party payment provider you'd like to use.", comment: "The description for one of the \"Why add Zaps?\" boxes")
        )
    }
    
    var LinkAccount: some View {
        self.WhyAddZapsBox(
            iconName: "link",
            heading: NSLocalizedString("Link your account", comment: "The heading for one of the \"Why add Zaps?\" boxes"),
            description: NSLocalizedString("Link to services that support Nostr Wallet Connect like Alby, Coinos and more.", comment: "The description for one of the \"Why add Zaps?\" boxes")
        )
    }
    
    var StartReceiving: some View {
        self.WhyAddZapsBox(
            iconName: "bitcoin",
            heading: NSLocalizedString("Start receiving money", comment: "The heading for one of the \"Why add Zaps?\" boxes"),
            description: NSLocalizedString("People will be able to send you cash from your profile. No money goes to Damus.", comment: "The description for one of the \"Why add Zaps?\" boxes")
        )
    }
    
    func WhyAddZapsBox(iconName: String, heading: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: {}, label: {
                Image(iconName)
                    .resizable()
                    .frame(width: 25, height: 25)
            })
            .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), cornerRadius: 9999))
            .disabled(true)
            
            Text(heading)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 2)
            
            Text(description)
                .font(.caption)
            
            Spacer()
        }
        .frame(maxWidth: 175, minHeight: 175)
        .padding(10)
        .background(DamusColors.neutral1)
        .cornerRadius(15)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(DamusColors.neutral1, lineWidth: 2)
        )
        .padding(.top, 20)
    }
}

struct ZapExplainerView_Previews: PreviewProvider {
    static var previews: some View {
        ZapExplainerView(show_introduction: .constant(true), nav: .init())
    }
}
