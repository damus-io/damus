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
    let text_color: Color
    /// Number of stars to display: 1 per year of membership, capped at 10.
    var star_count: Int {
        guard let duration = purple_account?.active_membership_duration else {
            return 1
        }
        let years = Int(duration / DamusPurple.Account.one_year)
        return min(max(years + 1, 1), 10)
    }

    init(percent: Int?, purple_account: DamusPurple.Account? = nil, style: Style, text_color: Color = .secondary) {
        self.percent = percent
        self.purple_account = purple_account
        self.style = style
        self.text_color = text_color
    }

    let size: CGFloat = 17

    var body: some View {
        HStack {
            if let purple_account, purple_account.active == true {
                HStack(spacing: 1) {
                    if star_count > 1 {
                        MultiStar(count: star_count, size: size)
                    } else {
                        StarShape()
                            .frame(width: size, height: size)
                            .foregroundStyle(GoldGradient)
                    }

                    if self.style == .full,
                       let ordinal = self.purple_account?.ordinal() {
                        Text(ordinal)
                            .foregroundStyle(text_color)
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
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: Text {
        if purple_account?.active == true {
            let years = star_count - 1
            if years > 0 {
                return Text("Purple supporter, \(years)-year member", comment: "Accessibility label for multi-star tenure badge")
            }
            return Text("Purple supporter", comment: "Accessibility label for standard purple badge")
        }
        if let percent {
            return Text("Supporter, \(percent) percent", comment: "Accessibility label for non-purple supporter badge")
        }
        return Text("")
    }

    enum Style {
        case full       // Shows the entire badge with a purple subscriber number if present
        case compact    // Does not show purple subscriber number. Only shows the star (if applicable)
    }
}


struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = min(rect.width, rect.height) / 2
        let points = 5
        let adjustment: CGFloat = .pi / 2

        for i in 0..<points * 2 {
            let angle = (CGFloat(i) * .pi / CGFloat(points)) - adjustment
            let pointRadius = i % 2 == 0 ? radius : radius * 0.4
            let point = CGPoint(x: center.x + pointRadius * cos(angle), y: center.y + pointRadius * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// Multi-star badge for tenure Purple members. Displays `count` overlapping stars.
struct MultiStar: View {
    let count: Int
    let size: CGFloat
    var starOffset: CGFloat = 5

    var body: some View {
        if #available(iOS 17.0, *) {
            MultiStarShape(count: count, starOffset: starOffset)
                .frame(width: size, height: size)
                .foregroundStyle(GoldGradient)
                .padding(.trailing, starOffset * CGFloat(count - 1))
        } else {
            Fallback(count: count, size: size, starOffset: starOffset)
        }
    }

    @available(iOS 17.0, *)
    struct MultiStarShape: Shape {
        var count: Int
        var strokeSize: CGFloat = 3
        var starOffset: CGFloat

        func path(in rect: CGRect) -> Path {
            let star = StarShape().path(in: rect)
            let largerStar = StarShape().path(in: rect.insetBy(dx: -strokeSize, dy: -strokeSize))

            var result = star.subtracting(largerStar.offsetBy(dx: starOffset, dy: 0))

            for i in 1..<count {
                let offset = starOffset * CGFloat(i)
                let starAtOffset = star.offsetBy(dx: offset, dy: 0)
                if i < count - 1 {
                    result = result.union(
                        starAtOffset.subtracting(largerStar.offsetBy(dx: starOffset * CGFloat(i + 1), dy: 0))
                    )
                } else {
                    result = result.union(starAtOffset)
                }
            }

            return result
        }
    }

    /// Fallback for iOS 16 and below.
    struct Fallback: View {
        var count: Int
        var size: CGFloat
        var starOffset: CGFloat

        var body: some View {
            HStack {
                StarShape()
                    .frame(width: size, height: size)
                    .foregroundStyle(GoldGradient)

                ForEach(1..<count, id: \.self) { _ in
                    StarShape()
                        .fill(GoldGradient)
                        .overlay(
                            StarShape()
                                .stroke(Color.damusAdaptableWhite, lineWidth: 1)
                        )
                        .frame(width: size + 1, height: size + 1)
                        .padding(.leading, -size - starOffset)
                }
            }
            .padding(.trailing, CGFloat(count - 1) * -3)
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
                purple_account: DamusPurple.Account(pubkey: test_pubkey, created_at: .now, expiry: .now.addingTimeInterval(10000), subscriber_number: subscriber_number, active: true, active_membership_duration: 0),
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

#Preview("Tenure badges") {
    let account = { (years: Double) in
        DamusPurple.Account(pubkey: test_pubkey, created_at: .now, expiry: .now.addingTimeInterval(10000), subscriber_number: 3, active: true, active_membership_duration: years * DamusPurple.Account.one_year + 1)
    }
    ScrollView {
        VStack(alignment: .leading) {
            ForEach(0..<10, id: \.self) { year in
                HStack {
                    SupporterBadge(percent: nil, purple_account: account(Double(year)), style: .full)
                    Text("\(year)+ year\(year == 1 ? "" : "s") — \(year + 1) star\(year == 0 ? "" : "s")")
                        .font(.caption)
                }
            }
        }
    }
}
