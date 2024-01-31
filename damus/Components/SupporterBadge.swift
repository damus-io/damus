//
//  SupporterBadge.swift
//  damus
//
//  Created by William Casarin on 2023-05-15.
//

import SwiftUI

struct SupporterBadge: View {
    let percent: Int?
    let purple_account: DamusPurple.Account?
    let style: Style
    
    init(percent: Int?, purple_account: DamusPurple.Account? = nil, style: Style) {
        self.percent = percent
        self.purple_account = purple_account
        self.style = style
    }
    
    let size: CGFloat = 17
    
    var body: some View {
        HStack {
            if let purple_account, purple_account.active == true {
                HStack(spacing: 1) {
                    Image("star.fill")
                        .resizable()
                        .frame(width:size, height:size)
                        .foregroundStyle(GoldGradient)
                    if self.style == .full {
                        Text("\(format_date(date: purple_account.created_at, time_style: .none))")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            else if let percent, percent < 100 {
                Image("star.fill")
                    .resizable()
                    .frame(width:size, height:size)
                    .foregroundColor(support_level_color(percent))
            } else if let percent, percent == 100 {
                Image("star.fill")
                    .resizable()
                    .frame(width:size, height:size)
                    .foregroundStyle(GoldGradient)
            }
        }
    }
    
    enum Style {
        case full       // Shows the entire badge with a purple subscriber number if present
        case compact    // Does not show purple subscriber number. Only shows the star (if applicable)
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
            SupporterBadge(percent: p, style: .full)
                .frame(width: 50)
            Text(verbatim: p.formatted())
                .frame(width: 50)
        }
    }
    
    static func Purple(_ subscriber_number: Int) -> some View {
        HStack(alignment: .center) {
            SupporterBadge(
                percent: nil,
                purple_account: DamusPurple.Account(pubkey: test_pubkey, created_at: .now, expiry: .now.addingTimeInterval(10000), subscriber_number: subscriber_number, active: true),
                style: .full
            )
                .frame(width: 100)
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
            Purple(1)
            Purple(2)
            Purple(3)
            Purple(99)
            Purple(100)
            Purple(1971)
        }
    }
}


