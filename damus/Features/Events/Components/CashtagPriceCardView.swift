//
//  CashtagPriceCardView.swift
//  damus
//
//  Compact price card shown under a note that mentions a cashtag like $BTC.
//  Price data comes from Ciphering (ciphering.io).
//

import SwiftUI
import Charts

/// Renders one price card per cashtag found in a note.
struct CashtagPriceCardsView: View {
    let cashtags: [Cashtag]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cashtags, id: \.self) { tag in
                CashtagPriceCardView(cashtag: tag)
            }
        }
        .padding(.top, 6)
    }
}

/// A single ticker card: symbol, price, 24h change and a small sparkline.
/// Silently renders nothing on network failure so the note is never broken.
struct CashtagPriceCardView: View {
    let cashtag: Cashtag

    @State private var price: CashtagPrice? = nil
    @State private var failed = false

    private var isUp: Bool { (price?.change24h ?? 0) >= 0 }
    private var trendColor: Color { isUp ? DamusColors.green : .red }

    private static let priceFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f
    }()

    var body: some View {
        Group {
            if let price {
                card(price)
            } else if !failed {
                placeholder
            }
            // failed → EmptyView, note renders as if no card existed
        }
        .task(id: cashtag.symbol) { await load() }
    }

    /// Loading skeleton, same height as the real card to avoid layout jumps.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(DamusColors.adaptableGrey)
            .frame(height: 64)
            .shimmer(true)
    }

    private func card(_ p: CashtagPrice) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("$\(p.symbol)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DamusColors.purple)
                Text(Self.priceFormatter.string(from: NSNumber(value: p.price)) ?? "—")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(String(format: "%@%.2f%% · 24h", isUp ? "+" : "", p.change24h))
                    .font(.caption)
                    .foregroundColor(trendColor)
            }

            Spacer(minLength: 0)

            if let spark = p.sparkline, spark.count > 1 {
                sparkline(spark)
                    .frame(width: 96, height: 36)
            }
        }
        .padding(12)
        .background(DamusColors.adaptableGrey)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DamusColors.adaptableLighterGrey, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.symbol) price \(p.price), 24 hour change \(p.change24h) percent")
    }

    private func sparkline(_ values: [Double]) -> some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(x: .value("t", item.offset), y: .value("price", item.element))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(trendColor)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (values.min() ?? 0)...(values.max() ?? 1))
    }

    private func load() async {
        do {
            let p = try await CashtagPriceService.shared.price(for: cashtag.symbol)
            await MainActor.run { self.price = p }
        } catch {
            await MainActor.run { self.failed = true }
        }
    }
}

struct CashtagPriceCardView_Previews: PreviewProvider {
    static var previews: some View {
        CashtagPriceCardView(cashtag: Cashtag(symbol: "BTC"))
            .padding()
    }
}
