//
//  SignalView.swift
//  damus
//
//  Created by William Casarin on 2023-04-14.
//

import SwiftUI

struct SignalView: View {
    let state: DamusState
    @ObservedObject var signal: SignalModel

    static let num_bars = 4
    static let bar_heights: [CGFloat] = [4, 7, 10, 13]
    static let bar_width: CGFloat = 3
    static let bar_spacing: CGFloat = 2

    var ratio: Double {
        guard signal.max_signal > 0 else { return 0 }
        return Double(signal.signal) / Double(signal.max_signal)
    }

    var active_bars: Int {
        if signal.signal == 0 { return 0 }
        return max(1, min(Self.num_bars, Int(ceil(ratio * Double(Self.num_bars)))))
    }

    var active_color: Color {
        if ratio < 0.5 {
            let t = ratio * 2.0
            return Color(
                red: 1.0,
                green: 0.4 + 0.4 * t,
                blue: 0.4
            )
        } else {
            let t = (ratio - 0.5) * 2.0
            return Color(
                red: 1.0 - 0.6 * t,
                green: 0.8,
                blue: 0.4
            )
        }
    }

    var inactive_color: Color {
        Color.gray.opacity(0.3)
    }

    var body: some View {
        Group {
            if signal.max_signal > 0 && signal.signal < signal.max_signal {
                NavigationLink(value: Route.RelayConfig) {
                    HStack(alignment: .bottom, spacing: Self.bar_spacing) {
                        ForEach(0..<Self.num_bars, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(i < active_bars ? active_color : inactive_color)
                                .frame(width: Self.bar_width, height: Self.bar_heights[i])
                        }
                    }
                }
                .frame(width: 30, height: 30)
                .accessibilityLabel(Text("\(signal.signal)/\(signal.max_signal) relays connected"))
            }
        }
    }
}

struct SignalView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 20) {
            SignalView(state: test_damus_state, signal: SignalModel(signal: 0, max_signal: 10))
            SignalView(state: test_damus_state, signal: SignalModel(signal: 3, max_signal: 10))
            SignalView(state: test_damus_state, signal: SignalModel(signal: 5, max_signal: 10))
            SignalView(state: test_damus_state, signal: SignalModel(signal: 10, max_signal: 10))
        }
    }
}
