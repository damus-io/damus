//
//  SetupView.swift
//  damus
//
//  Created by William Casarin on 2022-05-18.
//

import SwiftUI

func hex_col(r: UInt8, g: UInt8, b: UInt8) -> Color {
    return Color(.sRGB,
                 red: Double(r) / Double(0xff),
                 green: Double(g) / Double(0xff),
                 blue: Double(b) / Double(0xff),
                 opacity: 1.0)
}


struct SetupView: View {
    @StateObject var navigationCoordinator: NavigationCoordinator = NavigationCoordinator()
    
    var body: some View {
        NavigationStack(path: $navigationCoordinator.path) {
            ZStack {
                VStack(alignment: .center) {
                    Spacer()
                    
                    Image("logo-nobg")
                        .resizable()
                        .shadow(color: DamusColors.purple, radius: 2)
                        .frame(width: 56, height: 56, alignment: .center)
                        .padding(.top, 20.0)

                    Text("Welcome to Damus", comment: "Welcome text shown on the first screen when user is not logged in.")
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundStyle(DamusLogoGradient.gradient)

                    Text("The go-to iOS Nostr client", comment: "Quick description of what Damus is")
                        .foregroundColor(DamusColors.mediumGrey)
                        .padding(.top, 10)
                    
                    WhatIsNostr()
                        .padding()
                    
                    WhyWeNeedNostr()
                        .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        navigationCoordinator.push(route: Route.EULA)
                    }) {
                        HStack {
                            Text("Let's get started!", comment: "Button to continue to login page.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
                    }
                    .buttonStyle(GradientButtonStyle())
                    .padding()
                }
            }
            .background(DamusBackground(maxHeight: 300), alignment: .top)
            .navigationDestination(for: Route.self) { route in
                route.view(navigationCoordinator: navigationCoordinator, damusState: DamusState.empty)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct LearnAboutNostrLink: View {
    @Environment(\.openURL) var openURL
    var body: some View {
        HStack {
            Button(action: {
                openURL(URL(string: "https://nostr.com")!)
            }, label: {
                Text("Learn more about Nostr", comment: "Button that opens up a webpage where the user can learn more about Nostr.")
                    .foregroundColor(.accentColor)
            })
            
            Image(systemName: "arrow.up.right")
                .font(.footnote)
                .foregroundColor(.accentColor)
        }
    }
}

struct WhatIsNostr: View {
    var body: some View {
        HStack(alignment: .top) {
            Image("nostr-logo")
            VStack(alignment: .leading) {
                Text("What is Nostr?", comment: "Heading text for section describing what is Nostr.")
                    .fontWeight(.bold)
                    .padding(.vertical, 10)
                
                Text("Nostr is a protocol, designed for simplicity, that aims to create a censorship-resistant global social network", comment: "Description about what is Nostr.")
                    .foregroundColor(DamusColors.mediumGrey)
                
                LearnAboutNostrLink()
                    .padding(.top, 10)
            }
        }
    }
}

struct WhyWeNeedNostr: View {
    var body: some View {
        HStack(alignment: .top) {
            Image("lightbulb")
            VStack(alignment: .leading) {
                Text("Why we need Nostr?", comment: "Heading text for section describing why Nostr is needed.")
                    .fontWeight(.bold)
                    .padding(.vertical, 10)
                
                Text("Social media has developed into a key way information flows around the world. Unfortunately, our current social media systems are broken", comment: "Description about why Nostr is needed.")
                    .foregroundColor(DamusColors.mediumGrey)
            }
        }
    }
}

struct SetupView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            SetupView()
                .previewDevice(PreviewDevice(rawValue: "iPhone SE (3rd generation)"))
            SetupView()
                .previewDevice(PreviewDevice(rawValue: "iPhone 13 Pro Max"))
        }
    }
}

