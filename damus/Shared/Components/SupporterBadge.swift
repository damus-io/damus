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
    var badge_variant: BadgeVariant {
        guard let attributes = purple_account?.attributes else {
            return .normal
        }
        if attributes.contains(.memberForMoreThanThreeYears) {
            return .threeYearSpecial
        }
        if attributes.contains(.memberForMoreThanOneYear) {
            return .oneYearSpecial
        }
        return .normal
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
                    switch self.badge_variant {
                    case .normal:
                        StarShape()
                            .frame(width:size, height:size)
                            .foregroundStyle(GoldGradient)
                    case .oneYearSpecial:
                        DoubleStar(size: size)
                    case .threeYearSpecial:
                        TripleStar(size: size)
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
            switch badge_variant {
            case .threeYearSpecial:
                return Text("Purple supporter, three-year member", comment: "Accessibility label for triple star badge")
            case .oneYearSpecial:
                return Text("Purple supporter, one-year member", comment: "Accessibility label for double star badge")
            case .normal:
                return Text("Purple supporter", comment: "Accessibility label for standard purple badge")
            }
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
    
    enum BadgeVariant {
        case normal
        case oneYearSpecial
        case threeYearSpecial
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

struct DoubleStar: View {
    let size: CGFloat
    var starOffset: CGFloat = 5
    
    var body: some View {
        if #available(iOS 17.0, *) {
            DoubleStarShape(starOffset: starOffset)
                .frame(width: size, height: size)
                .foregroundStyle(GoldGradient)
                .padding(.trailing, starOffset)
        } else {
            Fallback(size: size, starOffset: starOffset)
        }
    }
    
    @available(iOS 17.0, *)
    struct DoubleStarShape: Shape {
        var strokeSize: CGFloat = 3
        var starOffset: CGFloat

        func path(in rect: CGRect) -> Path {
            let normalSizedStarPath = StarShape().path(in: rect)
            let largerStarPath = StarShape().path(in: rect.insetBy(dx: -strokeSize, dy: -strokeSize))
            
            let finalPath = normalSizedStarPath
                .subtracting(
                    largerStarPath.offsetBy(dx: starOffset, dy: 0)
                )
                .union(
                    normalSizedStarPath.offsetBy(dx: starOffset, dy: 0)
                )
            
            return finalPath
        }
    }
    
    /// A fallback view for those who cannot run iOS 17
    struct Fallback: View {
        var size: CGFloat
        var starOffset: CGFloat

        var body: some View {
            HStack {
                StarShape()
                    .frame(width: size, height: size)
                    .foregroundStyle(GoldGradient)

                StarShape()
                    .fill(GoldGradient)
                    .overlay(
                        StarShape()
                            .stroke(Color.damusAdaptableWhite, lineWidth: 1)
                    )
                    .frame(width: size + 1, height: size + 1)
                    .padding(.leading, -size - starOffset)
            }
            .padding(.trailing, -3)
        }
    }
}

/// Triple star badge for 3+ year Purple members.
struct TripleStar: View {
    let size: CGFloat
    var starOffset: CGFloat = 5

    var body: some View {
        if #available(iOS 17.0, *) {
            TripleStarShape(starOffset: starOffset)
                .frame(width: size, height: size)
                .foregroundStyle(GoldGradient)
                .padding(.trailing, starOffset * 2)
        } else {
            Fallback(size: size, starOffset: starOffset)
        }
    }

    @available(iOS 17.0, *)
    struct TripleStarShape: Shape {
        var strokeSize: CGFloat = 3
        var starOffset: CGFloat

        func path(in rect: CGRect) -> Path {
            let normalSizedStarPath = StarShape().path(in: rect)
            let largerStarPath = StarShape().path(in: rect.insetBy(dx: -strokeSize, dy: -strokeSize))

            let finalPath = normalSizedStarPath
                .subtracting(
                    largerStarPath.offsetBy(dx: starOffset, dy: 0)
                )
                .union(
                    normalSizedStarPath.offsetBy(dx: starOffset, dy: 0)
                        .subtracting(
                            largerStarPath.offsetBy(dx: starOffset * 2, dy: 0)
                        )
                )
                .union(
                    normalSizedStarPath.offsetBy(dx: starOffset * 2, dy: 0)
                )

            return finalPath
        }
    }

    /// Fallback for iOS 16 and below.
    struct Fallback: View {
        var size: CGFloat
        var starOffset: CGFloat

        private var overlappingStar: some View {
            StarShape()
                .fill(GoldGradient)
                .overlay(
                    StarShape()
                        .stroke(Color.damusAdaptableWhite, lineWidth: 1)
                )
                .frame(width: size + 1, height: size + 1)
                .padding(.leading, -size - starOffset)
        }

        var body: some View {
            HStack {
                StarShape()
                    .frame(width: size, height: size)
                    .foregroundStyle(GoldGradient)
                overlappingStar
                overlappingStar
            }
            .padding(.trailing, -6)
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
                purple_account: DamusPurple.Account(pubkey: test_pubkey, created_at: .now, expiry: .now.addingTimeInterval(10000), subscriber_number: subscriber_number, active: true, attributes: []),
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
    let account = { (attrs: DamusPurple.Account.PurpleAccountAttributes) in
        DamusPurple.Account(pubkey: test_pubkey, created_at: .now, expiry: .now.addingTimeInterval(10000), subscriber_number: 3, active: true, attributes: attrs)
    }
    VStack {
        SupporterBadge(percent: nil, purple_account: account([]), style: .full)
        SupporterBadge(percent: nil, purple_account: account([.memberForMoreThanOneYear]), style: .full)
        SupporterBadge(percent: nil, purple_account: account([.memberForMoreThanOneYear, .memberForMoreThanThreeYears]), style: .full)
    }
}
