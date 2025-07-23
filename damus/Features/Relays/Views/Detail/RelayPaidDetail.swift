//
//  RelayPaidDetail.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import SwiftUI

struct RelayPaidDetail: View {
    let payments_url: String?
    var fees: Fees? = nil
    @Environment(\.openURL) var openURL
    
    func timeString(time: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.year, .month, .day, .hour, .minute, .second]
        formatter.unitsStyle = .full
        let formattedString = formatter.string(from: TimeInterval(time)) ?? ""
        return formattedString
    }

    func displayAmount(unit: String, amount: Int64) -> String {
        if unit == "msats" {
            format_msats(amount)
        } else {
            "\(amount) \(unit)"
        }
    }

    func Amount(unit: String, amount: Int64) -> some View {
        HStack {
            let displayString = displayAmount(unit: unit, amount: amount)
            Text(displayString)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(DamusColors.white)
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if let url = payments_url.flatMap({ URL(string: $0) }) {
                    RelayType(is_paid: true)
                        .zIndex(1)
                    
                    Button(action: {
                        openURL(url)
                    }, label: {
                        if let admission = fees?.admission {
                            if !admission.isEmpty {
                                Amount(unit: admission[0].unit, amount: admission[0].amount)
                            } else {
                                Text("Paid Relay", comment: "Text indicating that this is a paid relay.")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(DamusColors.white)
                            }
                        } else if let subscription = fees?.subscription {
                            if !subscription.isEmpty {
                                Text("\(displayAmount(unit: subscription[0].unit, amount: subscription[0].amount)) / \(timeString(time: subscription[0].period))", comment: "Amount of money required to subscribe to the Nostr relay. In English, this would look something like '4,000 sats / 30 days', meaning it costs 4000 sats to subscribe to the Nostr relay for 30 days.")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(DamusColors.white)
                            }
                        } else if let publication = fees?.publication {
                            if !publication.isEmpty {
                                Text("\(displayAmount(unit: publication[0].unit, amount: publication[0].amount)) / event", comment: "Amount of money required to publish to the Nostr relay. In English, this would look something like '10 sats / event', meaning it costs 10 sats to publish one event.")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(DamusColors.white)
                            }
                        } else {
                            Text("Paid Relay", comment: "Text indicating that this is a paid relay.")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(DamusColors.white)
                        }
                    })
                    .padding(EdgeInsets(top: 3, leading: 25, bottom: 3, trailing: 10))
                    .background(DamusColors.bitcoin.opacity(0.7))
                    .cornerRadius(15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(DamusColors.warningBorder, lineWidth: 1)
                    )
                    .padding(.leading, 1)
                }
            }
        }
    }
}

struct RelayPaidDetail_Previews: PreviewProvider {
    static var previews: some View {
        let admission = Admission(amount: 1000000, unit: "msats")
        let sub = Subscription(amount: 5000000, unit: "msats", period: 2592000)
        let pub = Publication(kinds: [1, 4], amount: 100, unit: "msats")
        let fees = Fees(admission: [admission], subscription: [sub], publication: [pub])
        RelayPaidDetail(payments_url: "https://jb55.com", fees: fees)
    }
}
