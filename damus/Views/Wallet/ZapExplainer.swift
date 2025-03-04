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
    
    var body: some View {
        ScrollView {

            Text("Get cash instantly from your followers")
                .font(.system(size: 50))
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.top)
            
            GetPaid
            
            Gift
            
            GiveThanks
            
            WhyZaps
            
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    FindWallet
                    
                    LinkAccount
                    
                    StartReceiving
                }
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
        .scrollIndicators(.never)
        .background(
            Image("eula-bg")
                .resizable()
                .blur(radius: 70)
                .ignoresSafeArea(),
            alignment: .top
        )
        .padding(.horizontal)
    }
    
    var GetPaid: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: {}, label: {
                    Image("zap.fill")
                        .resizable()
                        .frame(width: 25, height: 25)
                })
                .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), cornerRadius: 9999))
                .disabled(true)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Get paid for being you")
                        .font(.system(size: 20))
                        .fontWeight(.bold)
                    
                    Text("Setting up Zaps lets people know you're ready to start receiving money.")
                        .font(.system(size: 16))
                }
                .padding(.top, 9)
            }
        }
        .padding(.top)
    }
    
    var Gift: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 10)  {
                Button(action: {}, label: {
                    Image("gift")
                        .resizable()
                        .frame(width: 25, height: 25)
                })
                .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), cornerRadius: 9999))
                .disabled(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Let your fans show their support")
                        .font(.system(size: 20))
                        .fontWeight(.bold)
                    
                    Text("You drive the conversation and we want to make it easier for people to support your work beyond follows, reposts, and likes.")
                        .font(.system(size: 16))
                }
                .padding(.top, 9)
            }
        }
        .padding(.top)
    }
    
    var GiveThanks: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: {}, label: {
                    Image("heart.fill")
                        .resizable()
                        .frame(width: 25, height: 25)
                })
                .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), cornerRadius: 9999))
                .disabled(true)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Give thanks")
                        .font(.system(size: 20))
                        .fontWeight(.bold)
                    
                    Text("When supporters tip with Zaps, they can add a note and we can make it easy for you to instantly reply to show your gratitude.")
                        .font(.system(size: 16))
                }
                .padding(.top, 9)
            }
        }
        .padding(.top)
    }
    
    var WhyZaps: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Why add Zaps?")
                .font(.system(size: 20))
                .fontWeight(.bold)
            
            Text("Zaps are an easy way to support the incredible\nvoices that make up the conversation on nostr.\nHere's how it works")
                .lineLimit(4)
                .font(.system(size: 16))
        }
        .padding(.top, 30)
    }
    
    var FindWallet: some View {
        VStack(alignment: .leading, spacing: 5) {
            
            Button(action: {}, label: {
                Image("wallet.fill")
                    .resizable()
                    .frame(width: 25, height: 25)
            })
            .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), cornerRadius: 9999))
            .disabled(true)
            
            Text("Find a Wallet")
                .font(.system(size: 20))
                .fontWeight(.bold)
            
            Text("Choose the third-party payment provider you'd like to use")
                .font(.system(size: 14))
            
            Spacer()
        }
        .frame(maxWidth: 175, minHeight: 175)
        .padding(10)
        .background(DamusColors.neutral1)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(DamusColors.neutral1, lineWidth: 2)
        )
        .padding(.top, 20)
        
    }
    
    var LinkAccount: some View {
        VStack(alignment: .leading, spacing: 2) {
            
            Button(action: {}, label: {
                Image("link")
                    .resizable()
                    .frame(width: 25, height: 25)
            })
            .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), cornerRadius: 9999))
            .disabled(true)
            
            Text("Link your account")
                .font(.system(size: 20))
                .fontWeight(.bold)
            
            Text("Link to services that support Nostr Wallet Connect like Alby, Coinos and more.")
                .font(.system(size: 14))
            
            Spacer()
        }
        .frame(maxWidth: 175, minHeight: 175)
        .padding(10)
        .background(DamusColors.neutral1)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(DamusColors.neutral1, lineWidth: 2)
        )
        .padding(.top, 20)
        
    }
    
    var StartReceiving: some View {
        VStack(alignment: .leading, spacing: 2) {
            
            Button(action: {}, label: {
                Image("bitcoin")
                    .resizable()
                    .frame(width: 25, height: 25)
            })
            .buttonStyle(NeutralButtonStyle(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10), cornerRadius: 9999))
            .disabled(true)
            
            Text("Start receiving money")
                .font(.system(size: 20))
                .fontWeight(.bold)
            
            Text("People will be able to send you cash from your profile. No money goes to Damus.")
                .font(.system(size: 14))
            
            Spacer()
        }
        .frame(maxWidth: 175, minHeight: 175)
        .padding(10)
        .background(DamusColors.neutral1)
        .cornerRadius(10)
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
