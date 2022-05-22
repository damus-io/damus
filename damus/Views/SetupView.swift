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

enum SetupState {
    case home
    case create_account
    case login
}

struct DamusGradient: View {
    var body: some View {
        LinearGradient(colors: damus_grad, startPoint: .bottomLeading, endPoint: .topTrailing)
            .edgesIgnoringSafeArea([.top,.bottom])
    }
}

struct SetupView: View {
    @State var state: SetupState? = .home
    
    var body: some View {
        NavigationView {
            ZStack {
                DamusGradient()
                
                VStack(alignment: .center) {
                    NavigationLink(destination: CreateAccountView(), tag: .create_account, selection: $state ) {
                        EmptyView()
                    }
                    
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
                    
                    DamusWhiteButton("Create Account") {
                        self.state = .create_account
                    }
                    
                    Button("Login") {
                        notify(.login, ())
                    }
                    .padding([.top, .bottom], 20)
                    .foregroundColor(.white)
                    
                    Spacer()
                }
            }
            .padding(.top, -80)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

func DamusWhiteButton(_ title: String, action: @escaping () -> ()) -> some View {
    return Button(action: action) {
        Text(title)
            .frame(width: 300, height: 50)
            .font(.body.bold())
            .contentShape(Rectangle())
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 4.0)
                    .stroke(Color.white, lineWidth: 2.0)
                    .background(Color.white.opacity(0.15))
            )
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

