//
//  CarouselView.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import SwiftUI

struct CarouselItem: Identifiable {
    let image: Image
    let text: Text
    
    let id = UUID().uuidString
}

let carousel_items = [
    CarouselItem(image: Image("digital-nomad"), text: Text("Welcome to the social network \(Text("you").italic()) control.")),
    CarouselItem(image: Image("encrypted-message"),
                 text: Text("\(Text("Encrypted").bold()). End-to-End encrypted private messaging. Keep Big Tech out of your DMs")),
    CarouselItem(image: Image("undercover"),
                 text: Text("\(Text("Private").bold()). Creating an account doesn't require a phone number, email or name. Get started right away with zero friction.")),
    CarouselItem(image: Image("bitcoin-p2p"),
                 text: Text("\(Text("Earn Money").bold()). Tip your friend's posts and stack sats with Bitcoin⚡️, the native currency of the internet."))
]

struct CarouselView: View {
    var body: some View {
        TabView {
            ForEach(carousel_items) { item in
                VStack{
                    CarouselItemView(item: item)
                        .tabItem {
                            Text(item.id)
                        }
                    Spacer(minLength: 20.0)
                }
                
            }
        }
        .tabViewStyle(PageTabViewStyle())
    }
}

func CarouselText(_ txt: String) -> some View {
    return Text(txt)
}

struct CarouselItemView: View {
    let item: CarouselItem
    
    var body: some View {
        VStack(spacing: 30) {
            item.image
                .resizable()
                .frame(width: 120, height: 120)
            item.text
                .multilineTextAlignment(.center)
                .font(.title2)
                .foregroundColor(Color.white)
                .padding([.leading,.trailing], 50.0)
        }
    }
}
