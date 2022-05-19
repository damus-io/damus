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

let damus_grad_c1 = hex_col(r: 0x1c, g: 0x55, b: 0xff)
let damus_grad_c2 = hex_col(r: 0x7f, g: 0x35, b: 0xab)
let damus_grad_c3 = hex_col(r: 0xff, g: 0x0b, b: 0xd6)
let damus_grad = [damus_grad_c1, damus_grad_c2, damus_grad_c3]

struct SetupView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: damus_grad, startPoint: .bottomLeading, endPoint: .topTrailing)
                .edgesIgnoringSafeArea([.top,.bottom])
            
            VStack(alignment: .center) {
                Image("logo-nobg")
                    .resizable()
                    .frame(width: 128.0, height: 128.0, alignment: .center)
                    .padding([.top], 20.0)
                Text("Damus")
                    .font(Font.custom("Nunito", size: 50.0))
                    .kerning(-2)
                    .foregroundColor(.white)
                
                CarouselView()
                
                Spacer()
                
                Button("Create Account") {
                    print("Create Account")
                }
                .font(.body.bold())
                .foregroundColor(.white)
                .frame(width: 300, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 4.0)
                        .stroke(Color.white, lineWidth: 2.0)
                        .background(Color.white.opacity(0.15))
                )
                
                Button("Login") {
                    notify(.login, ())
                }
                .foregroundColor(.white)
                .padding([.top], 20)
                
                Spacer()
            }
        }
    }
}

func CarouselText(_ txt: String) -> some View {
    return Text(txt)
}

struct CarouselItem: Identifiable {
    let image: Image
    let text: Text
    
    let id = UUID().uuidString
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
                CarouselItemView(item: item)
                    .tabItem {
                        Text(item.image)
                    }
            }
        }
        .tabViewStyle(PageTabViewStyle())
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
