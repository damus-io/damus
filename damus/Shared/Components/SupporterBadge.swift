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
    /// Determines the badge variant based on membership tenure.
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
    }
    
    enum Style {
        case full       // Shows the entire badge with a purple subscriber number if present
        case compact    // Does not show purple subscriber number. Only shows the star (if applicable)
    }
    
    /// Badge variants based on membership tenure.
    enum BadgeVariant {
        /// A normal badge for new members.
        case normal
        /// A special badge for members subscribed more than one year.
        case oneYearSpecial
        /// A special badge for members subscribed more than three years.
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

/// A triple star badge for members subscribed more than three years.
///
/// Displays three overlapping stars using path operations on iOS 17+,
/// or falls back to layered star views on earlier iOS versions.
///
/// - Parameters:
///   - size: The width and height of each individual star.
///   - starOffset: Horizontal spacing between overlapping stars. Defaults to 5.
struct TripleStar: View {
    /// The width and height of each individual star.
    let size: CGFloat
    /// Horizontal spacing between overlapping stars.
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

    /// A shape that renders three overlapping stars using path boolean operations.
    ///
    /// Available on iOS 17+ where `Path.subtracting` and `Path.union` are supported.
    ///
    /// - Parameters:
    ///   - strokeSize: The size of the gap carved between adjacent stars. Defaults to 3.
    ///   - starOffset: Horizontal offset between each star's position.
    @available(iOS 17.0, *)
    struct TripleStarShape: Shape {
        /// The size of the gap carved between adjacent stars.
        var strokeSize: CGFloat = 3
        /// Horizontal offset between each star's position.
        var starOffset: CGFloat

        /// Creates a path of three overlapping stars with carved gaps between them.
        ///
        /// - Parameter rect: The bounding rectangle for the leftmost star.
        /// - Returns: A combined path of three stars with the middle and right stars
        ///            offset horizontally and gaps carved where they overlap.
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

    /// A fallback view for iOS 16 and below using layered star views.
    ///
    /// Since path boolean operations are unavailable pre-iOS 17, this view
    /// stacks three separate `StarShape` views with stroke outlines to
    /// simulate the overlapping effect.
    ///
    /// - Parameters:
    ///   - size: The width and height of each star.
    ///   - starOffset: Horizontal spacing used to overlap the stars.
    struct Fallback: View {
        /// The width and height of each star.
        var size: CGFloat
        /// Horizontal spacing used to overlap the stars.
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

                StarShape()
                    .fill(GoldGradient)
                    .overlay(
                        StarShape()
                            .stroke(Color.damusAdaptableWhite, lineWidth: 1)
                    )
                    .frame(width: size + 1, height: size + 1)
                    .padding(.leading, -size - starOffset)
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
    VStack {
        Text(verbatim: "Normal badge (new member)")
        HStack(alignment: .center) {
            SupporterBadge(
                percent: nil,
                purple_account: DamusPurple.Account(pubkey: test_pubkey, created_at: .now, expiry: .now.addingTimeInterval(10000), subscriber_number: 3, active: true, attributes: []),
                style: .full
            )
                .frame(width: 100)
        }

        Text(verbatim: "Double star (1+ year member)")
        HStack(alignment: .center) {
            SupporterBadge(
                percent: nil,
                purple_account: DamusPurple.Account(pubkey: test_pubkey, created_at: .now, expiry: .now.addingTimeInterval(10000), subscriber_number: 3, active: true, attributes: [.memberForMoreThanOneYear]),
                style: .full
            )
                .frame(width: 100)
        }

        Text(verbatim: "Triple star (3+ year member)")
        HStack(alignment: .center) {
            SupporterBadge(
                percent: nil,
                purple_account: DamusPurple.Account(pubkey: test_pubkey, created_at: .now, expiry: .now.addingTimeInterval(10000), subscriber_number: 3, active: true, attributes: [.memberForMoreThanOneYear, .memberForMoreThanThreeYears]),
                style: .full
            )
                .frame(width: 100)
        }

        Text(verbatim: "Double star shape (alt background)")
            .multilineTextAlignment(.center)

        if #available(iOS 17.0, *) {
            HStack(alignment: .center) {
                DoubleStar.DoubleStarShape(starOffset: 5)
                    .frame(width: 17, height: 17)
                    .padding(.trailing, -8)
            }
            .background(Color.blue)
        }

        Text(verbatim: "Triple star shape (alt background)")
            .multilineTextAlignment(.center)

        if #available(iOS 17.0, *) {
            HStack(alignment: .center) {
                TripleStar.TripleStarShape(starOffset: 5)
                    .frame(width: 17, height: 17)
                    .padding(.trailing, -8)
            }
            .background(Color.blue)
        }

        Text(verbatim: "Double star fallback (iOS 16)")
        HStack(alignment: .center) {
            DoubleStar.Fallback(size: 17, starOffset: 5)
        }

        Text(verbatim: "Triple star fallback (iOS 16)")
        HStack(alignment: .center) {
            TripleStar.Fallback(size: 17, starOffset: 5)
        }
    }
}


