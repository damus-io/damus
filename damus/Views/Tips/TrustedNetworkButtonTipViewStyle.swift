//
//  TrustedNetworkButtonTipViewStyle.swift
//  damus
//
//  Created by Terry Yiu on 6/7/25.
//

import TipKit

// (tyiu): Apple's native popover tips have a lot of rendering and race condition issues --
// text being rendered in the wrong locations or not at all, or the tip gets opened in full screen.
//
// Instead, we are introducing this custom popover tip view style to emulate a similar look and feel.
// The main thing needed from this view style is really just an arrow on the top right corner
// to point to the TrustedNetworkButton on the NotificationsView and DirectMessagesview.
@available(iOS 17, *)
struct TrustedNetworkButtonTipViewStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            // Arrow pointing up to the button (positioned at top right)
            HStack {
                Spacer()
                Triangle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 24, height: 14)
            }

            HStack(alignment: .top, spacing: 12) {
                // Icon
                configuration.image
                    .foregroundStyle(.tint)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    configuration.title
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    configuration.message
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { configuration.tip.invalidate(reason: .tipClosed) }) {
                    Image(systemName: "xmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(.tertiaryLabel))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(
                .rect(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: 0
                )
            )
        }
    }
}

// Custom triangle shape for the popover arrow
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}
