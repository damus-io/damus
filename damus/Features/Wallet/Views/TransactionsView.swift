//
//  TransactionsView.swift
//  damus
//
//  Created by eric on 1/23/25.
//

import SwiftUI

struct TransactionView: View {
    @Environment(\.redactionReasons) var redactionReasons

    let damus_state: DamusState
    var transaction: WalletConnect.Transaction

    @Binding var hide_balance: Bool

    var body: some View {
        let redactedForPrivacy = redactionReasons.contains(.privacy)
        let isIncomingTransaction = transaction.type == "incoming"
        let txType = isIncomingTransaction ? "arrow-bottom-left" : "arrow-top-right"
        let txColor = (isIncomingTransaction && !hide_balance && !redactedForPrivacy) ? DamusColors.success : Color.gray
        let txOp = isIncomingTransaction ? "+" : "-"
        let created_at = Date.init(timeIntervalSince1970: TimeInterval(transaction.created_at))
        let formatter = RelativeDateTimeFormatter()
        let relativeDate = formatter.localizedString(for: created_at, relativeTo: Date.now)
        let event = decode_nostr_event_json(transaction.description ?? "") ?? transaction.metadata?.nostr
        let pubkey = self.pubkeyToDisplay(for: event, isIncomingTransaction: isIncomingTransaction)
        
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                ZStack {
                    ProfilePicView(pubkey: pubkey ?? ANON_PUBKEY, size: 45, highlight: .custom(.damusAdaptableBlack, 0.1), profiles: damus_state.profiles, disable_animation: damus_state.settings.disable_animation, privacy_sensitive: true, damusState: damus_state)
                        .onTapGesture {
                            if let pubkey {
                                damus_state.nav.push(route: Route.ProfileByKey(pubkey: pubkey))
                            }
                        }

                    if !hide_balance && !redactedForPrivacy {
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
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    
                    Text(self.userDisplayName(pubkey: pubkey))
                        .font(.headline)
                        .bold()
                        .foregroundColor(DamusColors.adaptableBlack)
                    
                    Text(relativeDate)
                        .font(.caption)
                        .foregroundColor(Color.gray)
                }
                .padding(.horizontal, 10)
                
                Spacer()

                if hide_balance {
                    Text(verbatim: "*****")
                        .font(.headline)
                        .foregroundColor(txColor)
                        .bold()
                } else {
                    Text(verbatim: "\(txOp) \(format_msats(transaction.amount))")
                        .font(.headline)
                        .foregroundColor(txColor)
                        .bold()
                }
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
    
    func pubkeyToDisplay(for zapRequest: NostrEvent?, isIncomingTransaction: Bool) -> Pubkey? {
        guard let zapRequest else { return nil }
        if isIncomingTransaction {
            return zapRequest.pubkey    // We want to know who sent it to us
        }
        else {
            return zapRequest.referenced_pubkeys.first  // We want to know who we sent it to
        }
    }
    
    func userDisplayName(pubkey: Pubkey?) -> String {
        guard let pubkey else {
            return NSLocalizedString("Unknown", comment: "A name label for an unknown user")
        }

        let profile = try? damus_state.profiles.lookup(id: pubkey)

        return Profile.displayName(profile: profile, pubkey: pubkey).displayName
    }
    
}

struct TransactionsView: View {
    
    let damus_state: DamusState
    let transactions: [WalletConnect.Transaction]?
    var sortedTransactions: [WalletConnect.Transaction]? {
        transactions?.sorted(by: { $0.created_at > $1.created_at })
    }

    @Binding var hide_balance: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest transactions", comment: "Heading for latest wallet transactions list")
                .foregroundStyle(DamusColors.neutral6)

            Group {
                if let sortedTransactions {
                    if sortedTransactions.isEmpty {
                        emptyTransactions
                    } else {
                        ForEach(sortedTransactions, id: \.self) { transaction in
                            TransactionView(damus_state: damus_state, transaction: transaction, hide_balance: $hide_balance)
                        }
                    }
                }
                else {
                    // Make sure we do not show "No transactions yet" to the user when still loading (or when failed to load)
                    // This is important because if we show that when things are not loaded properly, we risk scaring the user into thinking that they have lost funds.
                    emptyTransactions
                        .redacted(reason: .placeholder)
                        .shimmer(true)
                }
            }
            .privacySensitive()
        }
    }
    
    var emptyTransactions: some View {
        HStack {
            Text("No transactions yet", comment: "Message shown when no transactions are available")
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
    }
}

struct TransactionsView_Previews: PreviewProvider {
    static let tds = test_damus_state
    static let transaction1: WalletConnect.Transaction = WalletConnect.Transaction(type: "incoming", invoice: "", description: "{\"id\":\"7c0999a5870ca3ba0186a29a8650152b555cee29b53b5b8747d8a3798042d01c\",\"pubkey\":\"b8851a06dfd79d48fc325234a15e9a46a32a0982a823b54cdf82514b9b120ba1\",\"created_at\":1736383715,\"kind\":9734,\"tags\":[[\"p\",\"520830c334a3f79f88cac934580d26f91a7832c6b21fb9625690ea2ed81b5626\"],[\"amount\",\"21000\"],[\"e\",\"a25e152a4cd1b3bbc3d22e8e9315d8ea1f35c227b2f212c7cff18abff36fa208\"],[\"relays\",\"wss://nos.lol\",\"wss://nostr.wine\",\"wss://premium.primal.net\",\"wss://relay.damus.io\",\"wss://relay.nostr.band\",\"wss://relay.nostrarabia.com\"]],\"content\":\"🫡 Onward!\",\"sig\":\"e77d16822fa21b9c2e6b580b51c470588052c14aeb222f08f0e735027e366157c8742a6d5cb850780c2bf44ac63d89b048e5cc56dd47a1bfc740a3173e578f4e\"}", description_hash: "", preimage: "", payment_hash: "1234567890", amount: 21000, fees_paid: 0, created_at: 1737736866, expires_at: 0, settled_at: 0, metadata: nil)
    static let transaction2: WalletConnect.Transaction = WalletConnect.Transaction(type: "incoming", invoice: "", description: "", description_hash: "", preimage: "", payment_hash: "123456789033", amount: 100000000, fees_paid: 0, created_at: 1737690090, expires_at: 0, settled_at: 0, metadata: nil)
    static let transaction3: WalletConnect.Transaction = WalletConnect.Transaction(type: "outgoing", invoice: "", description: "", description_hash: "", preimage: "", payment_hash: "123456789042", amount: 303000, fees_paid: 0, created_at: 1737590101, expires_at: 0, settled_at: 0, metadata: nil)
    static let transaction4: WalletConnect.Transaction = WalletConnect.Transaction(type: "incoming", invoice: "", description: "", description_hash: "", preimage: "", payment_hash: "1234567890662", amount: 720000, fees_paid: 0, created_at: 1737090300, expires_at: 0, settled_at: 0, metadata: nil)
    static var test_transactions: [WalletConnect.Transaction] = [transaction1, transaction2, transaction3, transaction4]

    @State private static var hide_balance: Bool = false

    static var previews: some View {
        TransactionsView(damus_state: tds, transactions: test_transactions, hide_balance: $hide_balance)
    }
}
