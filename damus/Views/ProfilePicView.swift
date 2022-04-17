//
//  ProfilePicView.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import SwiftUI
import CachedAsyncImage

let PFP_SIZE: CGFloat? = 64
let CORNER_RADIUS: CGFloat = 32

func id_to_color(_ id: String) -> Color {
    return .init(hex: String(id.reversed().prefix(6)))
}

func highlight_color(_ h: Highlight) -> Color {
    switch h {
    case .none: return Color.black
    case .main: return Color.red
    case .referenced(let id): return Color.blue
    case .replied_to: return Color.blue
    }
}

func pfp_line_width(_ h: Highlight) -> CGFloat {
    if h.is_none {
        return 0
    }
    return 4
}

struct ProfilePicView: View {
    let picture: String?
    let size: CGFloat
    let highlight: Highlight

    var body: some View {
        if let pic = picture.flatMap({ URL(string: $0) }) {
            AsyncImage(url: pic) { img in
                img.resizable()
            } placeholder: {
                Color.purple.opacity(0.1)
            }
            .frame(width: PFP_SIZE, height: PFP_SIZE)
            .clipShape(Circle())
            .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
            .padding(2)
        } else {
            Color.purple.opacity(0.1)
                .frame(width: PFP_SIZE, height: PFP_SIZE)
                .cornerRadius(CORNER_RADIUS)
                .overlay(Circle().stroke(highlight_color(highlight), lineWidth: pfp_line_width(highlight)))
                .padding(2)
        }
    }
}

struct ProfilePicView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicView(picture: "http://cdn.jb55.com/img/red-me.jpg", size: 64, highlight: .none)
    }
}
    

extension Color {
    init(hex: String) {
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
