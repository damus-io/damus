//
//  ProfilePicView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI

let PFP_SIZE: CGFloat? = 52.0
let CORNER_RADIUS: CGFloat = 32

func id_to_color(_ id: String) -> Color {
    return hex_to_rgb(id)
}

func highlight_color(_ h: Highlight) -> Color {
    switch h {
    case .main: return Color.red
    case .reply: return Color.black
    case .none: return Color.black
    case .custom(let c, _): return c
    }
}

func pfp_line_width(_ h: Highlight) -> CGFloat {
    switch h {
    case .reply: return 0
    case .none: return 0
    case .main: return 2
    case .custom(_, let lw): return CGFloat(lw)
    }
}

struct ProfilePicView: View {
    let picture: String?
    let size: CGFloat
    let highlight: Highlight
    
    var Placeholder: some View {
        Color.purple.opacity(0.2)
    }
    
    var MainContent: some View {
        Group {
            if let pic = picture.flatMap({ URL(string: $0) }) {
                AsyncImage(url: pic) { img in
                    img.resizable()
                } placeholder: { Placeholder }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
                .padding(2)
            } else {
                Placeholder
                    .frame(width: size, height: size)
                    .cornerRadius(CORNER_RADIUS)
                    .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
                    .padding(2)
            }
        }
    }
    
    var body: some View {
        MainContent
    }
}

struct ProfilePicView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicView(picture: "http://cdn.jb55.com/img/red-me.jpg", size: 64, highlight: .none)
    }
}
    

func hex_to_rgb(_ hex: String) -> Color {
    guard hex.count >= 6 else {
        return Color.black
    }
    
    let arr = Array(hex.utf8)
    var rgb: [UInt8] = []
    var i: Int = 0
    
    while i < 6 {
        let cs1 = arr[i]
        let cs2 = arr[i+1]
        
        guard let c1 = char_to_hex(cs1) else {
            return Color.black
        }

        guard let c2 = char_to_hex(cs2) else {
            return Color.black
        }
        
        rgb.append((c1 << 4) | c2)
        i += 2
    }

    return Color.init(
        .sRGB,
        red: Double(rgb[0]) / 255,
        green: Double(rgb[1]) / 255,
        blue:  Double(rgb[2]) / 255,
        opacity: 1
    )
}
