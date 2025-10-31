//
//  SetupView.swift
//  damus
//
//  Created by William Casarin on 2022-05-18.
//

import SwiftUI


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

                    Text("The social network you control", comment: "Quick description of what Damus is")
                        .foregroundColor(DamusColors.neutral6)
                        .padding(.top, 10)
                    
                    Spacer()
                    
                    Button(action: {
                        navigationCoordinator.push(route: Route.CreateAccount)
                    }) {
                        HStack {
                            Text("Create Account", comment: "Button to continue to the create account page.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
                    }
                    .buttonStyle(GradientButtonStyle())
                    .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_up_option_button.rawValue)
                    .padding(.horizontal)
                    
                    Button(action: {
                        navigationCoordinator.push(route: Route.Login)
                    }) {
                        HStack {
                            Text("Sign In", comment: "Button to continue to login page.")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: 12, alignment: .center)
                    }
                    .buttonStyle(GradientButtonStyle())
                    .accessibilityIdentifier(AppAccessibilityIdentifiers.sign_in_option_button.rawValue)
                    .padding()

                    Button(action: {
                        navigationCoordinator.push(route: Route.EULA)
                    }, label: {
                        HStack {
                            Text("By continuing, you agree to our EULA", comment: "Disclaimer to user that they are agreeing to the End User License Agreement if they create an account or sign in.")
                                .font(.subheadline)
                                .foregroundColor(DamusColors.neutral6)

                            Image(systemName: "arrow.forward")
                        }
                    })
                    .padding(.vertical, 5)
                    .padding(.bottom)
                }
            }
            .background(DamusBackground(maxHeight: UIScreen.main.bounds.size.height/2), alignment: .top)
            .navigationDestination(for: Route.self) { route in
                route.view(navigationCoordinator: navigationCoordinator, damusState: DamusState.empty)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationViewStyle(StackNavigationViewStyle())
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

