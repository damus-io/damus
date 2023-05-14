//
//  SupporterBadge.swift
//  damus
//
//  Created by William Casarin on 2023-05-15.
//

import SwiftUI

struct SupporterBadge: View {
    let percent: Int
    
    let size: CGFloat = 17
    
    var body: some View {
        if percent < 100 {
            Image("star.fill")
                .resizable()
                .frame(width:size, height:size)
                .foregroundColor(support_level_color(percent))
        } else {
            Image("star.fill")
                .resizable()
                .frame(width:size, height:size)
                .foregroundStyle(GoldGradient)
        }
    }
}

func support_level_color(_ percent: Int) -> Color {
    if percent == 0 {
        return .gray
    }
    
    let percent_f = Double(percent) / 100.0
    let cutoff = 0.5
    let h = cutoff + (percent_f * cutoff); // Hue (note 0.2 = Green, see huge chart below)
    let s = 0.9; // Saturation
    let b = 0.9; // Brightness
    
    return Color(hue: h, saturation: s, brightness: b)
}

struct SupporterBadge_Previews: PreviewProvider {
    static func Level(_ p: Int) -> some View {
        HStack(alignment: .center) {
            SupporterBadge(percent: p)
                .frame(width: 50)
            Text(verbatim: p.formatted())
                .frame(width: 50)
        }
    }
    
    static var previews: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Level(1)
                Level(10)
                Level(20)
                Level(30)
                Level(40)
                Level(50)
            }
            Level(60)
            Level(70)
            Level(80)
            Level(90)
            Level(100)
        }
    }
}


