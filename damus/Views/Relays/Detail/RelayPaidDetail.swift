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
    
    func Amount(unit: String, amount: Int64) -> some View {
        HStack {
            if unit == "msats" {
                Text("\(format_msats(amount))")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(DamusColors.white)
            } else {
                Text("\(amount) \(unit)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(DamusColors.white)
            }
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
                                Text(verbatim: "Paid Relay")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(DamusColors.white)
                            }
                        } else if let subscription = fees?.subscription {
                            if !subscription.isEmpty {
                                Amount(unit: subscription[0].unit, amount: subscription[0].amount)
                                Text("/ \(timeString(time: subscription[0].period))")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(DamusColors.white)
                            }
                        } else if let publication = fees?.publication {
                            if !publication.isEmpty {
                                Amount(unit: publication[0].unit, amount: publication[0].amount)
                                Text("/ event")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(DamusColors.white)
                            }
                        } else {
                            Text(verbatim: "Paid Relay")
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
