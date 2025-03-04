//
//  TransactionsView.swift
//  damus
//
//  Created by eric on 1/23/25.
//

import SwiftUI

struct TransactionView: View {
    
    let damus_state: DamusState
    var transaction: NWCTransaction
    
    var body: some View {
        let txType = transaction.type == "incoming" ? "arrow-bottom-left" : "arrow-top-right"
        let txColor = transaction.type == "incoming" ? DamusColors.success : Color.gray
        let txOp = transaction.type == "incoming" ? "+" : "-"
        let created_at = Date.init(timeIntervalSince1970: TimeInterval(transaction.created_at))
        let formatter = RelativeDateTimeFormatter()
        let relativeDate = formatter.localizedString(for: created_at, relativeTo: Date.now)
        let event = decode_nostr_event_json(transaction.description ?? "")
        let pubkey = (event?.pubkey ?? ANON_PUBKEY)
        
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                ZStack {
                    ProfilePicView(pubkey: pubkey, size: 45, highlight: .custom(.damusAdaptableBlack, 0.1), profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation)
                    
                    Image(txType)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .foregroundColor(.white)
                        .padding(2)
                        .background(txColor)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.damusAdaptableWhite, lineWidth: 1.0))
                        .padding(.top, 25)
                        .padding(.leading, 35)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    
                    let profile_txn = damus_state.profiles.lookup(id: pubkey, txn_name: "txview-profile")
                    let profile = profile_txn?.unsafeUnownedValue
                    
                    if let display_name = profile?.display_name {
                        Text(display_name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DamusColors.adaptableBlack)
                    } else if let name = profile?.name {
                        Text(verbatim: "@" + name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DamusColors.adaptableBlack)
                    } else {
                        Text("Unknown")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DamusColors.adaptableBlack)
                    }
                    
                    Text("\(relativeDate)")
                        .font(.system(size: 14))
                        .foregroundColor(Color.gray)
                }
                .padding(.horizontal, 10)
                
                Spacer()

                Text("\(txOp) \(transaction.amount/1000) sats")
                    .font(.system(size: 20))
                    .foregroundColor(txColor)
                    .bold()
            }
            .frame(maxWidth: .infinity, minHeight: 75, alignment: .center)
            .padding(.horizontal, 10)
            .background(DamusColors.neutral1)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DamusColors.neutral3, lineWidth: 1)
            )
        }
    }
    
}

struct TransactionsView: View {
    
    let damus_state: DamusState
    var transactions: [NWCTransaction]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest transactions")
                .foregroundStyle(DamusColors.neutral6)
            
            if transactions.isEmpty {
                HStack {
                    Text("No transactions yet")
                        .foregroundStyle(DamusColors.neutral6)
                }
                .frame(maxWidth: .infinity, minHeight: 75, alignment: .center)
                .padding(.horizontal, 10)
                .background(DamusColors.neutral1)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DamusColors.neutral3, lineWidth: 1)
                )
            } else {
                ForEach(transactions, id: \.self) { transaction in
                    TransactionView(damus_state: damus_state, transaction: transaction)
                }
            }
        }
    }
}

struct TransactionsView_Previews: PreviewProvider {
    static let tds = test_damus_state
    static let transaction1: NWCTransaction = NWCTransaction(type: "incoming", invoice: "", description: "{\"id\":\"7c0999a5870ca3ba0186a29a8650152b555cee29b53b5b8747d8a3798042d01c\",\"pubkey\":\"b8851a06dfd79d48fc325234a15e9a46a32a0982a823b54cdf82514b9b120ba1\",\"created_at\":1736383715,\"kind\":9734,\"tags\":[[\"p\",\"520830c334a3f79f88cac934580d26f91a7832c6b21fb9625690ea2ed81b5626\"],[\"amount\",\"21000\"],[\"e\",\"a25e152a4cd1b3bbc3d22e8e9315d8ea1f35c227b2f212c7cff18abff36fa208\"],[\"relays\",\"wss://nos.lol\",\"wss://nostr.wine\",\"wss://premium.primal.net\",\"wss://relay.damus.io\",\"wss://relay.nostr.band\",\"wss://relay.nostrarabia.com\"]],\"content\":\"🫡 Onward!\",\"sig\":\"e77d16822fa21b9c2e6b580b51c470588052c14aeb222f08f0e735027e366157c8742a6d5cb850780c2bf44ac63d89b048e5cc56dd47a1bfc740a3173e578f4e\"}", description_hash: "", preimage: "", payment_hash: "1234567890", amount: 21000, fees_paid: 0, created_at: 1737736866, expires_at: 0, settled_at: 0)
    static let transaction2: NWCTransaction = NWCTransaction(type: "incoming", invoice: "", description: "", description_hash: "", preimage: "", payment_hash: "123456789033", amount: 100000000, fees_paid: 0, created_at: 1737690090, expires_at: 0, settled_at: 0)
    static let transaction3: NWCTransaction = NWCTransaction(type: "outgoing", invoice: "", description: "", description_hash: "", preimage: "", payment_hash: "123456789042", amount: 303000, fees_paid: 0, created_at: 1737590101, expires_at: 0, settled_at: 0)
    static let transaction4: NWCTransaction = NWCTransaction(type: "incoming", invoice: "", description: "", description_hash: "", preimage: "", payment_hash: "1234567890662", amount: 720000, fees_paid: 0, created_at: 1737090300, expires_at: 0, settled_at: 0)
    static var test_transactions: [NWCTransaction] = [transaction1, transaction2, transaction3, transaction4]
    
    static var previews: some View {
        TransactionsView(damus_state: tds, transactions: test_transactions)
    }
}
