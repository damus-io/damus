//
//  DamusPurpleWelcomeView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-12-04.
//

import Foundation
import SwiftUI

fileprivate extension Animation {
    static func content() -> Animation {
        Animation.easeInOut(duration: 1).delay(3)
    }
}

struct DamusPurpleWelcomeView: View {
    @Environment(\.dismiss) var dismiss
    @State var start = false
    var next_page: () -> Void
    
    var body: some View {
        VStack {
            Image("damus-dark-logo")
                .resizable()
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(LinearGradient(
                            colors: [DamusColors.lighterPink.opacity(0.8), .white.opacity(0), DamusColors.deepPurple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing), lineWidth: 1)
                )
                .shadow(radius: 5)
                .padding(20)
                .opacity(start ? 1.0 : 0.0)
                .animation(.content(), value: start)
            
            Text("Welcome to Purple", comment: "Greeting to subscription service")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.black, .black, DamusColors.pink, DamusColors.lighterPink],
                        startPoint: start ? .init(x: -3, y: 4) : .bottomLeading,
                        endPoint: start ? .topTrailing : .init(x: 3, y: -4)
                    )
                )
                .opacity(start ? 1.0 : 0.0)
                .animation(Animation.easeInOut(duration: 3).delay(0), value: start)
            
            Image(systemName: "star.fill")
                .resizable()
                .frame(width: 96, height: 90)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.black, DamusColors.purple, .white, .white],
                        startPoint: start ? .init(x: -1, y: 1.5) : .bottomLeading,
                        endPoint: start ? .topTrailing : .init(x: 10, y: -11)
                    )
                )
                .animation(Animation.snappy(duration: 3).delay(1), value: start)
                .shadow(
                    color: start ? DamusColors.lightBackgroundPink : DamusColors.purple.opacity(0.3),
                    radius: start ? 30 : 10
                )
                .animation(Animation.snappy(duration: 3).delay(0), value: start)
                .scaleEffect(x: start ? 1 : 3, y: start ? 1 : 3)
                .opacity(start ? 1.0 : 0.0)
                .animation(Animation.snappy(duration: 2).delay(0), value: start)
            
            Text("Thank you very much for signing up for Damus\u{00A0}Purple. Your contribution helps us continue our fight for a more Open and Free\u{00A0}internet.\n\nYou will also get access to premium features, and a star badge on your profile.\n\nEnjoy!", comment: "Appreciation to user for purchasing subscription service")
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 20)
                .padding(.top, 50)
                .padding(.bottom, 20)
                .opacity(start ? 1.0 : 0.0)
                .animation(.content(), value: start)
            
            Button(action: {
                self.next_page()
            }, label: {
                HStack {
                    Spacer()
                    Text("Continue", comment: "Prompt to user to continue")
                    Spacer()
                }
            })
            .padding(.horizontal, 30)
            .buttonStyle(GradientButtonStyle())
            .opacity(start ? 1.0 : 0.0)
            .animation(Animation.easeInOut(duration: 2).delay(3), value: start)
        }
        .background(content: {
            ZStack {
                Image("purple-blue-gradient-1")
                    .offset(CGSize(width: 300.0, height: -0.0))
                    .opacity(start ? 1.0 : 0.2)
                    .background(.black)
                Image("stars-bg")
                    .resizable(resizingMode: .stretch)
                    .frame(width: 500, height: 500)
                    .offset(x: -100, y: 50)
                    .scaleEffect(start ? 1 : 1.1)
                    .animation(Animation.easeOut(duration: 3).delay(0), value: start)
                Image("purple-blue-gradient-1")
                    .offset(CGSize(width: 300.0, height: -0.0))
                    .opacity(start ? 1.0 : 0.2)
                
            }
        })
        .onAppear(perform: {
            // SwiftUI quirk #98332: If I try to trigger an immediate animation, the animation does not work when this view is placed under a TabView.
            // Triggering the animation only after a slight delay makes it work.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                withAnimation(.easeOut(duration: 6), {
                    start = true
                })
            })
            
        })
        .interactiveDismissDisabled()
    }
}

struct DamusPurpleWelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        DamusPurpleWelcomeView(next_page: {})
    }
}
